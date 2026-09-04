function [objectiveValue,details] = ...
    networkObjective( ...
        sensorDecision, ...
        database, ...
        objectiveMode)
% NETWORKOBJECTIVE Evaluate one candidate surface-sensor network.
%
% Inputs:
%   sensorDecision - Vector of candidate indices defining the network.
%                    The network size is the length of this vector and may
%                    be any positive integer up to the available candidate
%                    count. Network-size study choices belong to the run
%                    configuration, not to the precomputed database.
%
%   database       - Optimization database created by
%                    optimization.buildOptimizationDatabase.
%
%   objectiveMode  - "information" or "coverage".
%
% Outputs:
%   objectiveValue - Objective value for minimization.
%
%   details        - Optional diagnostic structure. When requested, both
%                    information and coverage metrics are evaluated.
%
% The objective uses an index-vector decision representation rather than a
% full S-element binary vector. For example:
%
%       [31 104 587]
%
% represents a three-sensor network.
%
% Candidate indices are canonicalized by sorting. Duplicate indices are
% infeasible.
%
% IMPORTANT:
% Only the selected sensor rows/slices are passed to the information and
% coverage objectives. Therefore, objective cost scales primarily with the
% selected network size rather than the total number of candidate sites.
%
% database.study.networkSizes is retained as study metadata only. It does
% not constrain evaluation, so one production database can be reused for
% different network-size studies without rebuilding it.

arguments
    sensorDecision double
    database (1,1) struct
    objectiveMode (1,1) string
end

%% ========================================================================
%  Basic database information
%  ========================================================================

objectiveMode = ...
    lower(objectiveMode);

numberOfCandidates = ...
    database.meta.numberOfCandidates;

numberOfObjects = ...
    database.meta.numberOfObjects;

infeasiblePenalty = ...
    database.objective.infeasiblePenalty;

sensorIndicesInput = ...
    sensorDecision(:);

networkSize = ...
    length(sensorIndicesInput);

%% ========================================================================
%  Initialize diagnostics
%  ========================================================================

details = struct();

details.feasible = ...
    false;

details.reason = ...
    "";

details.objectiveMode = ...
    objectiveMode;

details.objectiveValue = ...
    infeasiblePenalty;

details.networkSize = ...
    networkSize;

details.inputSensorIndices = ...
    sensorIndicesInput;

details.sensorIndices = ...
    sensorIndicesInput;

details.selectedSensors = ...
    false(numberOfCandidates,1);

details.informationObjectiveValue = ...
    NaN;

details.coverageObjectiveValue = ...
    NaN;

details.informationScore = ...
    NaN;

details.coverageScore = ...
    NaN;

details.informationByObject = ...
    NaN(numberOfObjects,1);

details.coverageByObject = ...
    NaN(numberOfObjects,1);

%% ========================================================================
%  Objective-mode validation
%  ========================================================================

validObjectiveModes = ...
    ["information","coverage"];

if ~ismember(objectiveMode,validObjectiveModes)

    error( ...
        "networkObjective:InvalidObjectiveMode", ...
        "objectiveMode must be ""information"" or ""coverage"".");
end

if isfield(database.objective,"supportedModes")

    supportedModes = ...
        string(database.objective.supportedModes);

elseif isfield(database.study,"objectiveModes")

    supportedModes = ...
        string(database.study.objectiveModes);

else

    supportedModes = ...
        validObjectiveModes;
end

if ~ismember(objectiveMode,supportedModes)

    error( ...
        "networkObjective:UnsupportedObjectiveMode", ...
        "Objective mode %s is not enabled for this database.", ...
        objectiveMode);
end

%% ========================================================================
%  Validate network size
%  ========================================================================

if networkSize < 1

    details.reason = ...
        "empty_network";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

if networkSize > numberOfCandidates

    details.reason = ...
        "network_larger_than_candidate_set";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

%% ========================================================================
%  Validate candidate indices
%  ========================================================================

if any(~isfinite(sensorIndicesInput))

    details.reason = ...
        "nonfinite_candidate_index";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

if any(sensorIndicesInput ~= round(sensorIndicesInput))

    details.reason = ...
        "noninteger_candidate_index";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

sensorIndicesInput = ...
    round(sensorIndicesInput);

if any(sensorIndicesInput < 1) || ...
        any(sensorIndicesInput > numberOfCandidates)

    details.reason = ...
        "candidate_index_out_of_range";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

if length(unique(sensorIndicesInput)) ~= networkSize

    details.reason = ...
        "duplicate_candidate_index";

    objectiveValue = ...
        infeasiblePenalty;

    return
end

%% ========================================================================
%  Canonicalize network
%  ========================================================================

sensorIndices = ...
    sort(sensorIndicesInput);

selectedSensorsFull = ...
    false(numberOfCandidates,1);

selectedSensorsFull(sensorIndices) = ...
    true;

details.sensorIndices = ...
    sensorIndices;

details.selectedSensors = ...
    selectedSensorsFull;

%% ========================================================================
%  Slice database to selected sensors
%  ========================================================================
%
% The downstream covariance code sees only the selected N_s sensors.
% Therefore it does not repeatedly scan every candidate location during
% every covariance update.

selectedAvailability = ...
    database.visibility.filteredAvailability( ...
        sensorIndices,:,:);

selectedJacobians = ...
    database.tracking.measurementJacobianHistories( ...
        :,:,sensorIndices,:,:);

numberOfSelectedSensors = ...
    length(sensorIndices);

selectedSensorMask = ...
    true(numberOfSelectedSensors,1);

%% Measurement covariance

measurementCovariances = ...
    database.measurement.covariance;

numberOfMeasurementCovariances = ...
    size(measurementCovariances,3);

if numberOfMeasurementCovariances == 1

    selectedMeasurementCovariances = ...
        measurementCovariances;

elseif numberOfMeasurementCovariances == numberOfCandidates

    selectedMeasurementCovariances = ...
        measurementCovariances(:,:,sensorIndices);

else

    error( ...
        "networkObjective:InvalidMeasurementCovariance", ...
        [ ...
        "Measurement covariance must contain either one shared " ...
        "covariance or one covariance per candidate sensor." ...
        ]);
end

%% ========================================================================
%  Determine required calculations
%  ========================================================================

calculateInformation = ...
    objectiveMode == "information";

calculateCoverage = ...
    objectiveMode == "coverage";

% If diagnostics are requested, calculate both metrics so the winning
% network can always be characterized with both objective definitions.
if nargout > 1

    calculateInformation = ...
        true;

    calculateCoverage = ...
        true;
end

%% ========================================================================
%  Information objective
%  ========================================================================

if calculateInformation

    [informationObjectiveValue,informationByObject] = ...
        optimization.informationObjective( ...
            selectedSensorMask, ...
            database.prior.initialCovariances, ...
            database.tracking.stateTransitionHistories, ...
            database.tracking.processNoiseHistories, ...
            selectedJacobians, ...
            selectedAvailability, ...
            selectedMeasurementCovariances, ...
            database.estimation.stateScales, ...
            database.estimation.objectWeights);

    informationScore = ...
        -informationObjectiveValue;

    details.informationObjectiveValue = ...
        informationObjectiveValue;

    details.informationScore = ...
        informationScore;

    details.informationByObject = ...
        informationByObject;
end

%% ========================================================================
%  Coverage objective
%  ========================================================================

if calculateCoverage

    [coverageObjectiveValue,coverageByObject] = ...
        optimization.coverageObjective( ...
            selectedSensorMask, ...
            selectedAvailability, ...
            database.estimation.objectWeights);

    coverageScore = ...
        -coverageObjectiveValue;

    details.coverageObjectiveValue = ...
        coverageObjectiveValue;

    details.coverageScore = ...
        coverageScore;

    details.coverageByObject = ...
        coverageByObject;
end

%% ========================================================================
%  Return requested objective
%  ========================================================================

switch objectiveMode

    case "information"

        objectiveValue = ...
            details.informationObjectiveValue;

    case "coverage"

        objectiveValue = ...
            details.coverageObjectiveValue;
end

details.feasible = ...
    true;

details.reason = ...
    "feasible";

details.objectiveValue = ...
    objectiveValue;

end

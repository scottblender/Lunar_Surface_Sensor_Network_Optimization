function [objectiveValue,details] = ...
    networkObjective( ...
        sensorDecision, ...
        database, ...
        objectiveMode)
% NETWORKOBJECTIVE - Evaluate one candidate surface-sensor network.
%
% Inputs:
%   - sensorDecision - Vector of distinct, 1-based candidate-site IDs.
%   - database - Frozen optimization database.
%   - objectiveMode - "information" or "coverage".
%
% Outputs:
%   - objectiveValue - Network score for minimization.
%   - details - Optional information and coverage diagnostics.
%
% Notes:
%   - IDs are sorted; duplicates receive the infeasible penalty.
%   - Only selected sensor data are loaded and evaluated.

arguments
    sensorDecision double
    database (1,1) struct
    objectiveMode (1,1) string
end

%% Basic database information
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

%% Initialize diagnostics
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

%% Objective-mode validation
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

%% Validate network size
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

%% Validate candidate indices
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

% Deterministic CLPS deployment views allow at most one sensor per anchor site.
if isfield(database,"config") && isfield(database.config,"domainComparison") && ...
        isfield(database.config.domainComparison,"enforceSiteGroups") && ...
        database.config.domainComparison.enforceSiteGroups
    if isfield(database.config.domainComparison,"anchorMembership")
        membership=database.config.domainComparison.anchorMembership(sensorIndicesInput,:);
        if ~optimization.canAssignDistinctAnchors(membership)
            details.reason="duplicate_clps_site"; objectiveValue=infeasiblePenalty; return;
        end
    else
        groups = database.config.domainComparison.prefilterSiteIds( ...
            database.candidates.originalIndices(sensorIndicesInput));
        if any(strlength(groups)==0) || numel(unique(groups))~=networkSize
            details.reason = "duplicate_clps_site";
            objectiveValue = infeasiblePenalty;
            return
        end
    end
end

%% Canonicalize network
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

%% Slice database to selected sensors
% Pass only selected sensors to avoid scanning the global grid during each update.

if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)

    selectedAvailability = ...
        optimization.loadChunkedCandidateData( ...
            database,sensorIndices,"filteredAvailability");
else
    selectedAvailability = ...
        database.visibility.filteredAvailability( ...
            sensorIndices,:,:);
end

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

%% Determine required calculations
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

%% Information objective
if calculateInformation

    % Load only selected Jacobian slices through the global-to-chunk index map.
    if isfield(database.tracking,"measurementJacobianChunks") && ...
            ~isempty(database.tracking.measurementJacobianChunks)

        selectedJacobians = ...
            optimization.loadChunkedCandidateData( ...
                database,sensorIndices,"measurementJacobianHistories");
    else
        selectedJacobians = ...
            database.tracking.measurementJacobianHistories( ...
                :,:,sensorIndices,:,:);
    end

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

%% Coverage objective
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

%% Return requested objective
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

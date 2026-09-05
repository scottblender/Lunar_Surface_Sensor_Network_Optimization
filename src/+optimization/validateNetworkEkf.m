function validation = validateNetworkEkf(database,sensorIndices,userConfig)
% VALIDATENETWORDEKF Run a deterministic noisy EKF validation for one network.
%
% The global optimizer uses the deterministic covariance-only objective in
% optimization.networkObjective. This function is intentionally separate
% from the search FE budget. It generates one fixed RA/Dec noise realization
% and runs the state-updating lunar-surface EKF for every RSO using the
% selected sensor network.
%
% The measurement-noise realization is reproducible and network independent:
% a full candidate-by-time noise field is generated from one fixed seed for
% every RSO before the selected sensors are extracted. Therefore, if two
% candidate networks share a sensor/time measurement, that common
% measurement receives exactly the same noise realization.
%
% Inputs
%   database      - Frozen optimization database.
%   sensorIndices - Selected candidate indices, Ns-by-1.
%   userConfig    - Optional configuration structure.
%
% Configuration fields
%   measurementNoiseSeed       - Fixed noise seed. Default 5000.
%   initialPerturbationScale    - Scale on deterministic P0-consistent
%                                 initial error. Default 1.
%   initialPerturbationDirection- 6x1 normalized-coordinate direction.
%   demFile                    - Optional DEM override. By default the DEM
%                                 recorded in database.meta.demSource is used.
%
% Output
%   validation - EKF histories, errors, three-sigma measures, innovations,
%                measurement availability, and per-RSO summary metrics.

arguments
    database (1,1) struct
    sensorIndices (:,1) double
    userConfig (1,1) struct = struct()
end

%% Configuration

defaultConfig = struct();
defaultConfig.measurementNoiseSeed = 5000;
defaultConfig.initialPerturbationScale = 1;
defaultConfig.initialPerturbationDirection = [1;-1;0.5;0.25;-0.25;0.125];
defaultConfig.demFile = "";

config = mergeStruct(defaultConfig,userConfig);

validateattributes(config.measurementNoiseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
validateattributes(config.initialPerturbationScale,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(config.initialPerturbationDirection,{'numeric'}, ...
    {'vector','numel',6,'real','finite'});

%% Required database fields

requiredTopLevelFields = [ ...
    "meta"
    "config"
    "candidates"
    "truth"
    "prior"
    "tracking"
    "visibility"
    "measurement"
    "estimation"
    ];

for fieldIndex = 1:numel(requiredTopLevelFields)
    fieldName = requiredTopLevelFields(fieldIndex);
    assert(isfield(database,fieldName), ...
        "validateNetworkEkf:MissingDatabaseField", ...
        "Database field '%s' is required.",fieldName);
end

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

sensorIndices = sort(round(sensorIndices(:)));

assert(~isempty(sensorIndices), ...
    "validateNetworkEkf:EmptyNetwork", ...
    "At least one sensor must be selected.");
assert(all(isfinite(sensorIndices)) && ...
    all(sensorIndices >= 1) && ...
    all(sensorIndices <= numberOfCandidates), ...
    "validateNetworkEkf:InvalidSensorIndex", ...
    "Selected sensor indices are outside the candidate set.");
assert(numel(unique(sensorIndices)) == numel(sensorIndices), ...
    "validateNetworkEkf:DuplicateSensorIndex", ...
    "Selected sensor indices must be unique.");

numberOfSelectedSensors = numel(sensorIndices);

%% Load the same DEM used by the optimization database

moonRadiusKm = database.config.moon.radiusKm;
moonMuKm3S2 = database.config.moon.muKm3S2;
theta0Rad = database.config.moon.theta0Rad;
moonAngularRate = 2*pi/database.config.moon.siderealPeriodSeconds;

dem = loadValidationDem(database,config.demFile,moonRadiusKm);

%% Shared validation data

observationTimesUnique = database.tracking.times(:);
numberOfTimes = numel(observationTimesUnique);

truthStateHistories = database.truth.optimizationStateHistories;

assert(size(truthStateHistories,1) == 6 && ...
    size(truthStateHistories,2) == numberOfTimes && ...
    size(truthStateHistories,3) == numberOfObjects, ...
    "validateNetworkEkf:InvalidTruthDimensions", ...
    "Optimization truth histories have unexpected dimensions.");

filteredAvailability = database.visibility.filteredAvailability;

assert(size(filteredAvailability,1) == numberOfCandidates && ...
    size(filteredAvailability,2) == numberOfTimes && ...
    size(filteredAvailability,3) == numberOfObjects, ...
    "validateNetworkEkf:InvalidAvailabilityDimensions", ...
    "Filtered availability has unexpected dimensions.");

measurementCovariance = database.measurement.covariance;
measurementNoiseFactor = chol(measurementCovariance,"lower");

initialCovariance = database.prior.initialCovariance;
initialCovarianceFactor = chol(initialCovariance,"lower");

perturbationDirection = config.initialPerturbationDirection(:);
perturbationDirection = perturbationDirection/norm(perturbationDirection);

initialError = config.initialPerturbationScale * ...
    initialCovarianceFactor * perturbationDirection;

% Schedule every selected sensor at every tracking epoch. The EKF accepts
% nondecreasing times, so multiple sensors at one epoch are processed as
% sequential zero-time measurement updates after a single propagation.
observationTimes = repelem(observationTimesUnique,numberOfSelectedSensors);
scheduledSensorIndices = repmat(sensorIndices,numberOfTimes,1);
sensorLatitudes = database.candidates.latitudesRad(scheduledSensorIndices);
sensorLongitudes = database.candidates.longitudesRad(scheduledSensorIndices);

numberOfScheduledObservations = numel(observationTimes);
epochFinalObservationIndices = ...
    (numberOfSelectedSensors:numberOfSelectedSensors:numberOfScheduledObservations).';

%% Allocate validation histories

stateHistories = nan(6,numberOfTimes,numberOfObjects);
covarianceHistories = nan(6,6,numberOfTimes,numberOfObjects);
innovationHistories = nan(2,numberOfScheduledObservations,numberOfObjects);
measurementAvailable = false(numberOfScheduledObservations,numberOfObjects);
rightAscension = nan(numberOfScheduledObservations,numberOfObjects);
declination = nan(numberOfScheduledObservations,numberOfObjects);

positionErrorNormsKm = nan(numberOfTimes,numberOfObjects);
velocityErrorNormsKmS = nan(numberOfTimes,numberOfObjects);
positionThreeSigmaNormsKm = nan(numberOfTimes,numberOfObjects);
velocityThreeSigmaNormsKmS = nan(numberOfTimes,numberOfObjects);
measurementUpdateCounts = zeros(numberOfObjects,1);

%% Fixed measurement-noise realization

previousRandomState = rng;
randomStateCleanup = onCleanup(@() rng(previousRandomState)); %#ok<NASGU>
rng(config.measurementNoiseSeed,"twister");

for objectIndex = 1:numberOfObjects

    % Generate the full candidate-by-time noise field before selecting the
    % network. This makes common measurements identical across networks.
    fullNoise = measurementNoiseFactor * ...
        randn(2,numberOfCandidates*numberOfTimes);

    fullNoise = reshape(fullNoise,2,numberOfCandidates,numberOfTimes);
    selectedNoise = reshape(fullNoise(:,sensorIndices,:), ...
        2,numberOfScheduledObservations);

    objectAvailability = reshape( ...
        filteredAvailability(sensorIndices,:,objectIndex), ...
        numberOfScheduledObservations,1);

    objectRightAscension = nan(numberOfScheduledObservations,1);
    objectDeclination = nan(numberOfScheduledObservations,1);

    availableObservationIndices = find(objectAvailability);

    for availableIndex = 1:numel(availableObservationIndices)
        observationIndex = availableObservationIndices(availableIndex);

        timeIndex = floor((observationIndex-1)/numberOfSelectedSensors) + 1;
        selectedSensorIndex = mod(observationIndex-1,numberOfSelectedSensors) + 1;

        trueMeasurement = measurements.surfaceRaDecMeasurement( ...
            truthStateHistories(:,timeIndex,objectIndex), ...
            observationTimesUnique(timeIndex), ...
            database.candidates.latitudesRad(sensorIndices(selectedSensorIndex)), ...
            database.candidates.longitudesRad(sensorIndices(selectedSensorIndex)), ...
            dem, ...
            moonRadiusKm, ...
            theta0Rad, ...
            moonAngularRate);

        noisyMeasurement = trueMeasurement + selectedNoise(:,observationIndex);
        noisyMeasurement(1) = mod(noisyMeasurement(1),2*pi);

        objectRightAscension(observationIndex) = noisyMeasurement(1);
        objectDeclination(observationIndex) = noisyMeasurement(2);
    end

    initialStateEstimate = ...
        database.prior.initialStates(:,objectIndex) + initialError;

    [scheduledStateHistory,scheduledCovarianceHistory, ...
        scheduledInnovationHistory] = estimation.lunarSurfaceEkf( ...
            database.prior.referenceTime, ...
            observationTimes, ...
            objectRightAscension, ...
            objectDeclination, ...
            sensorLatitudes, ...
            sensorLongitudes, ...
            dem, ...
            objectAvailability, ...
            initialStateEstimate, ...
            initialCovariance, ...
            measurementCovariance, ...
            database.estimation.accelerationNoiseIntensity, ...
            moonMuKm3S2, ...
            moonRadiusKm, ...
            theta0Rad, ...
            moonAngularRate);

    objectStateHistory = scheduledStateHistory(:,epochFinalObservationIndices);
    objectCovarianceHistory = scheduledCovarianceHistory(:,:,epochFinalObservationIndices);

    stateHistories(:,:,objectIndex) = objectStateHistory;
    covarianceHistories(:,:,:,objectIndex) = objectCovarianceHistory;
    innovationHistories(:,:,objectIndex) = scheduledInnovationHistory;
    measurementAvailable(:,objectIndex) = objectAvailability;
    rightAscension(:,objectIndex) = objectRightAscension;
    declination(:,objectIndex) = objectDeclination;

    stateError = objectStateHistory - truthStateHistories(:,:,objectIndex);

    positionErrorNormsKm(:,objectIndex) = ...
        vecnorm(stateError(1:3,:),2,1).';
    velocityErrorNormsKmS(:,objectIndex) = ...
        vecnorm(stateError(4:6,:),2,1).';

    for timeIndex = 1:numberOfTimes
        positionCovariance = objectCovarianceHistory(1:3,1:3,timeIndex);
        velocityCovariance = objectCovarianceHistory(4:6,4:6,timeIndex);

        positionThreeSigmaNormsKm(timeIndex,objectIndex) = ...
            3*sqrt(max(0,trace(positionCovariance)));
        velocityThreeSigmaNormsKmS(timeIndex,objectIndex) = ...
            3*sqrt(max(0,trace(velocityCovariance)));
    end

    measurementUpdateCounts(objectIndex) = nnz(objectAvailability);
end

%% Summary metrics

rmsPositionErrorKm = sqrt(mean(positionErrorNormsKm.^2,1)).';
rmsVelocityErrorKmS = sqrt(mean(velocityErrorNormsKmS.^2,1)).';
maximumPositionErrorKm = max(positionErrorNormsKm,[],1).';
maximumVelocityErrorKmS = max(velocityErrorNormsKmS,[],1).';

objectIndex = (1:numberOfObjects).';
summaryTable = table( ...
    objectIndex, ...
    measurementUpdateCounts, ...
    rmsPositionErrorKm, ...
    maximumPositionErrorKm, ...
    rmsVelocityErrorKmS, ...
    maximumVelocityErrorKmS, ...
    'VariableNames',{ ...
        'ObjectIndex', ...
        'MeasurementUpdates', ...
        'RmsPositionErrorKm', ...
        'MaximumPositionErrorKm', ...
        'RmsVelocityErrorKmS', ...
        'MaximumVelocityErrorKmS'});

%% Output

validation = struct();
validation.version = "lunar_network_ekf_validation_v1";
validation.created = string(datetime("now"));
validation.sensorIndices = sensorIndices;
validation.sensorLatitudesRad = database.candidates.latitudesRad(sensorIndices);
validation.sensorLongitudesRad = database.candidates.longitudesRad(sensorIndices);
validation.measurementNoiseSeed = config.measurementNoiseSeed;
validation.initialPerturbationScale = config.initialPerturbationScale;
validation.initialPerturbationDirection = perturbationDirection;
validation.initialError = initialError;
validation.demSource = string(resolveDemFile(database,config.demFile));
validation.times = observationTimesUnique;
validation.observationTimes = observationTimes;
validation.scheduledSensorIndices = scheduledSensorIndices;
validation.truthStateHistories = truthStateHistories;
validation.stateHistories = stateHistories;
validation.covarianceHistories = covarianceHistories;
validation.innovationHistories = innovationHistories;
validation.measurementAvailable = measurementAvailable;
validation.rightAscension = rightAscension;
validation.declination = declination;
validation.positionErrorNormsKm = positionErrorNormsKm;
validation.velocityErrorNormsKmS = velocityErrorNormsKmS;
validation.positionThreeSigmaNormsKm = positionThreeSigmaNormsKm;
validation.velocityThreeSigmaNormsKmS = velocityThreeSigmaNormsKmS;
validation.measurementUpdateCounts = measurementUpdateCounts;
validation.rmsPositionErrorKm = rmsPositionErrorKm;
validation.rmsVelocityErrorKmS = rmsVelocityErrorKmS;
validation.maximumPositionErrorKm = maximumPositionErrorKm;
validation.maximumVelocityErrorKmS = maximumVelocityErrorKmS;
validation.summaryTable = summaryTable;
validation.config = config;

end

function dem = loadValidationDem(database,demFileOverride,moonRadiusKm)
% Load either the current Final_Lunar_DEM.mat or the legacy interpolant MAT.

demFile = resolveDemFile(database,demFileOverride);

assert(isfile(demFile), ...
    "validateNetworkEkf:DemNotFound", ...
    "Validation DEM was not found: %s",demFile);

fileVariables = whos("-file",demFile);
variableNames = string({fileVariables.name});

if any(variableNames == "DEM")
    [dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
        string(demFile),moonRadiusKm,24,48);
    return
end

if any(variableNames == "F")
    loadedData = load(demFile,"F");
    sourceDem = loadedData.F;

    latitudeGrid = sourceDem.GridVectors{1}(:);
    longitudeGrid = sourceDem.GridVectors{2}(:);
    elevationGrid = sourceDem.Values;

    if max(abs(latitudeGrid)) > pi/2 + 1e-6
        latitudeGrid = deg2rad(latitudeGrid);
    end
    if max(abs(longitudeGrid)) > 2*pi + 1e-6
        longitudeGrid = deg2rad(longitudeGrid);
    end

    if longitudeGrid(end) < 2*pi-1e-10
        longitudeGrid = [longitudeGrid;2*pi];
        elevationGrid = [elevationGrid,elevationGrid(:,1)];
    end

    dem = griddedInterpolant( ...
        {latitudeGrid,longitudeGrid},elevationGrid,"linear","nearest");
    return
end

error("validateNetworkEkf:UnsupportedDemFile", ...
    "DEM MAT file must contain either DEM or F.");
end

function demFile = resolveDemFile(database,demFileOverride)

if strlength(string(demFileOverride)) > 0
    demFile = string(demFileOverride);
elseif isfield(database,"meta") && isfield(database.meta,"demSource")
    demFile = string(database.meta.demSource);
elseif isfield(database,"config") && isfield(database.config,"demSource")
    demFile = string(database.config.demSource);
else
    demFile = "";
end

assert(strlength(demFile) > 0, ...
    "validateNetworkEkf:MissingDemSource", ...
    ["The database does not identify its DEM source. Supply " ...
     "userConfig.demFile explicitly."]);
end

function output = mergeStruct(defaults,override)

output = defaults;
fields = fieldnames(override);

for fieldIndex = 1:numel(fields)
    fieldName = fields{fieldIndex};
    overrideValue = override.(fieldName);

    if isfield(output,fieldName) && ...
            isstruct(output.(fieldName)) && isscalar(output.(fieldName)) && ...
            isstruct(overrideValue) && isscalar(overrideValue)
        output.(fieldName) = mergeStruct(output.(fieldName),overrideValue);
    else
        output.(fieldName) = overrideValue;
    end
end
end

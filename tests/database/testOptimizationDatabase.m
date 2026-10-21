function tests = testOptimizationDatabase
% TESTOPTIMIZATIONDATABASE - Verify reduced builds, scalability, and saved production chunks.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root); setupProject;
testCase.TestData.root = root;
end

function setup(testCase)
previous = rng;
testCase.addTeardown(@()rng(previous));
end

function testReducedBuild(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");

%% Test definition
networkSizes = sort(unique([3,5,7]));

%% Load DEM
demPath = fullfile( projectRoot, "data", "Synthetic_Lunar_DEM.mat");
assert(isfile(demPath), "Synthetic DEM file was not found.");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( string(demPath), 1737.4, 24, 48);

%% Constants
moonRadius = 1737.4;
moonMu = 4902.800066;

%% Small deterministic RSO population
rsoNames = [ "LRO-like 50 km polar"
    "Chandrayaan-like 100 km polar"
    "200 km, 60 deg inclined"
];
truthInitialStates = zeros(6,3);
truthInitialStates(:,1) = circularOrbitState( moonRadius+50, deg2rad(90), deg2rad(37), 0, moonMu);
truthInitialStates(:,2) = circularOrbitState( moonRadius+100, deg2rad(90), deg2rad(120), ...
        deg2rad(35), moonMu);
truthInitialStates(:,3) = circularOrbitState( moonRadius+200, deg2rad(60), deg2rad(205.2), ...
        deg2rad(-90), moonMu);
customCatalog = table( rsoNames, 'VariableNames',{'Name'});

%% Eight candidate locations
candidateLatitudes = deg2rad([ -84.000000
    -89.505332
    -76.149000
    -76.000000
    -85.000000
    -80.000000
    -88.000000
    -78.000000
    ]);
candidateLongitudes = deg2rad([ 37.000000
    102.857143
    115.200000
    300.000000
      0.000000
     60.000000
    180.000000
    240.000000
    ]);
assert(length(candidateLatitudes) == 8, "The test requires eight candidate locations.");
assert(max(networkSizes) <= length(candidateLatitudes), ...
    "The largest configured network exceeds the test candidate set.");

%% Temporary database file
temporaryFile = string(tempname) + ".mat";
cleanupObject = onCleanup(@()cleanupFile(temporaryFile)); %#ok<NASGU>

%% Reduced test configuration
config = struct();
config.outputFile = temporaryFile;
config.overwriteOutput = false;
config.demSource = string(demPath);
config.study.networkSizes = networkSizes;
config.study.objectiveModes = ["information","coverage"];

%% Custom RSOs
config.rso.customInitialStatesMoonInertial = truthInitialStates;
config.rso.customCatalog = customCatalog;

%% Custom candidate set
config.candidates.customLatitudesRad = candidateLatitudes;
config.candidates.customLongitudesRad = candidateLongitudes;
config.candidateFilter.enabled = false;

%% Terrain
config.terrain.maximumRangeKm = 100;
config.terrain.rangeStepKm = 1.0;
config.terrain.horizonAzimuthStepRad = deg2rad(2);
config.terrain.horizonMarginRad = 0;

%% Visibility
config.visibility.minimumElevationRad = 0;
config.visibility.minimumAngularSeparationRad = deg2rad(20);

%% Tracking
config.tracking.outputStepSeconds = 30;
config.tracking.finalTimeSeconds = 8*3600;

%% Measurement noise
config.measurement.rightAscensionSigmaRad = deg2rad(1/3600);
config.measurement.declinationSigmaRad = deg2rad(1/3600);

%% One reference IOD calibration
config.iod.referencePeriapsisAltitudeKm = 50;
config.iod.referenceEccentricity = 0;
config.iod.referenceInclinationRad = deg2rad(90);
config.iod.referenceRaanRad = deg2rad(37);
config.iod.referenceArgumentOfPeriapsisRad = 0;
config.iod.referenceTrueAnomalyRad = 0;
config.iod.referenceSensorLatitudeRad = deg2rad(-89.505332);
config.iod.referenceSensorLongitudeRad = deg2rad(102.857143);
config.iod.outputStepSeconds = 10;
config.iod.desiredObservationCount = 15;
config.iod.searchEndFraction = 0.40;
config.iod.numberOfMonteCarloSamples = 20;
config.iod.measurementNoiseSeedBase = 700;
config.iod.monteCarloSeedBase = 900;

%% Estimation
config.estimation.accelerationNoiseIntensity = 1e-15;
config.estimation.stateScales = [1;1;1;1e-3;1e-3;1e-3];
config.estimation.objectWeights = ones(3,1);

%% Build database
database = optimization.buildOptimizationDatabase( dem, config);

%% Structural checks
numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;
numberOfOptimizationTimes = database.meta.numberOfOptimizationEpochs;
assert(numberOfObjects == 3, "Unexpected RSO count.");
assert(numberOfCandidates == 8, "Unexpected candidate count.");
assert(isequal( database.study.networkSizes, networkSizes), "Network-size configuration changed.");
assert(all(ismember( ["information","coverage"], database.study.objectiveModes)), ...
    "Objective-mode configuration is incomplete.");
assert(database.prior.referenceTime == 0, "Optimization prior reference time should be zero.");

%% Fixed-P0 and IOD calibration checks
P0 = database.prior.initialCovariance;
assert(isequal(size(P0),[6,6]), "Fixed P0 is not 6x6.");
assert(all(isfinite(P0),"all"), "Fixed P0 contains nonfinite values.");
[~,positiveDefiniteFlag] = chol( 0.5*(P0+P0.'), "lower");
assert(positiveDefiniteFlag == 0, "Fixed P0 is not positive definite.");
assert( length(database.iod.calibration.acquisitionIndices) == config.iod.desiredObservationCount, ...
    "Reference IOD did not use the requested observation count.");
assert( database.iod.calibration.desiredObservationCount == config.iod.desiredObservationCount, ...
    "Stored IOD observation-count metadata is inconsistent.");
assert( database.iod.calibration.outputStepSeconds == config.iod.outputStepSeconds, ...
    "Stored IOD cadence is inconsistent.");
assert( database.iod.calibration.diagnostics.numberOfRequestedSamples == ...
    config.iod.numberOfMonteCarloSamples, "Reference IOD Monte Carlo sample count changed.");
assert( database.iod.calibration.diagnostics.numberOfSuccessfulSamples >= ...
    ceil(0.8*config.iod.numberOfMonteCarloSamples), ...
    "Reference IOD Monte Carlo convergence was insufficient.");
for objectIndex = 1:numberOfObjects
    objectP0 = database.prior.initialCovariances(:,:,objectIndex);
    assert(isequal(objectP0,P0), "RSO %d does not use the common fixed P0.", objectIndex);
end
assert(max(abs( database.prior.initialStates - truthInitialStates),[],"all") < 1e-12, ...
    "Nominal prior states do not equal truth states at t = 0.");

%% Tracking dimensions and numerical checks
assert( isequal( size(database.visibility.filteredAvailability), ...
        [numberOfCandidates,numberOfOptimizationTimes,numberOfObjects]), ...
    "Filtered availability dimensions are incorrect.");
assert(size(database.tracking.measurementJacobianHistories,1) == 2, ...
    "Jacobian measurement dimension is incorrect.");
assert(size(database.tracking.measurementJacobianHistories,2) == 3, ...
    "Database should store only the three nonzero position Jacobian columns.");
assert(string(database.meta.measurementJacobianStorage) == "position_only", ...
    "Compact Jacobian storage metadata is incorrect.");
assert(size( database.tracking.measurementJacobianHistories,3) == numberOfCandidates, ...
    "Jacobian candidate dimension is incorrect.");
assert(size( database.tracking.measurementJacobianHistories,4) == numberOfOptimizationTimes, ...
    "Jacobian time dimension is incorrect.");
assert(size( database.tracking.measurementJacobianHistories,5) == numberOfObjects, ...
    "Jacobian RSO dimension is incorrect.");
assert(all(isfinite( database.tracking.referenceStateHistories),"all"), ...
    "Reference states contain nonfinite values.");
assert(all(isfinite( database.tracking.stateTransitionHistories),"all"), ...
    "STM history contains nonfinite values.");
assert(all(isfinite( database.tracking.processNoiseHistories),"all"), ...
    "Process-noise history contains nonfinite values.");
assert(all(isfinite( database.tracking.measurementJacobianHistories),"all"), ...
    "Measurement Jacobians contain nonfinite values.");
assert(all( database.visibility.filteredAvailability <= database.visibility.terrainAvailability, ...
    "all"), "Filtered visibility exceeds terrain visibility.");
assert(all( database.visibility.terrainAvailability <= database.visibility.geometricAvailability, ...
    "all"), "Terrain visibility exceeds geometric visibility.");

%% Representative nested networks for every configured size
maximumNetworkSize = max(networkSizes);
maximumNetwork = (1:maximumNetworkSize).';
numberOfNetworkSizes = length(networkSizes);
representativeNetworks = cell(numberOfNetworkSizes,1);
for sizeIndex = 1:numberOfNetworkSizes
    representativeNetworks{sizeIndex} = maximumNetwork(1:networkSizes(sizeIndex));
end

%% Evaluate both objectives for every configured size
informationObjectives = zeros(numberOfNetworkSizes,1);
coverageObjectives = zeros(numberOfNetworkSizes,1);
for sizeIndex = 1:numberOfNetworkSizes
    currentNetwork = representativeNetworks{sizeIndex};
    informationObjectives(sizeIndex) = optimization.networkObjective( currentNetwork, database, ...
            "information");
    coverageObjectives(sizeIndex) = optimization.networkObjective( currentNetwork, database, ...
            "coverage");
end
assert(all(isfinite(informationObjectives)), "One or more information objectives are nonfinite.");
assert(all(isfinite(coverageObjectives)), "One or more coverage objectives are nonfinite.");
for sizeIndex = 2:numberOfNetworkSizes
    assert( coverageObjectives(sizeIndex) <= coverageObjectives(sizeIndex-1)+1e-12, ...
        "Adding sensors reduced coverage.");
end

%% Verify selected-sensor slicing is numerically equivalent
baseNetwork = representativeNetworks{1};
fullSelectedSensors = false(numberOfCandidates,1);
fullSelectedSensors(baseNetwork) = true;
[directInformationObjective,directInformationByObject] = optimization.informationObjective( ...
        fullSelectedSensors, database.prior.initialCovariances, ...
        database.tracking.stateTransitionHistories, database.tracking.processNoiseHistories, ...
        database.tracking.measurementJacobianHistories, database.visibility.filteredAvailability, ...
        database.measurement.covariance, database.estimation.stateScales, ...
        database.estimation.objectWeights);
[directCoverageObjective,directCoverageByObject] = optimization.coverageObjective( ...
        fullSelectedSensors, database.visibility.filteredAvailability, ...
        database.estimation.objectWeights);
informationTolerance = 1e-12*max(1,abs(informationObjectives(1)));
assert(abs( directInformationObjective-informationObjectives(1)) <= informationTolerance, ...
    "Selected-sensor slicing changed the information objective.");
assert(abs( directCoverageObjective-coverageObjectives(1)) <= 1e-12, ...
    "Selected-sensor slicing changed the coverage objective.");

%% Determinism and sensor-order invariance
informationRepeat = optimization.networkObjective( baseNetwork, database, "information");
assert(abs( informationRepeat-informationObjectives(1)) <= informationTolerance, ...
    "Information objective is not deterministic.");
permutedNetwork = baseNetwork(end:-1:1);
informationPermuted = optimization.networkObjective( permutedNetwork, database, "information");
coveragePermuted = optimization.networkObjective( permutedNetwork, database, "coverage");
assert(abs( informationPermuted-informationObjectives(1)) <= informationTolerance, ...
    "Information objective depends on sensor ordering.");
assert(abs( coveragePermuted-coverageObjectives(1)) <= 1e-12, ...
    "Coverage objective depends on sensor ordering.");

%% Detailed objective diagnostics
[detailedObjective,details] = optimization.networkObjective( baseNetwork, database, "information");
assert(details.feasible, "Valid network was classified as infeasible.");
assert(isequal( details.sensorIndices, sort(baseNetwork(:))), "Selected candidate indices changed.");
assert(abs( detailedObjective-informationObjectives(1)) <= informationTolerance, ...
    "Detailed information result is inconsistent.");
assert(max(abs( details.informationByObject-directInformationByObject)) <= informationTolerance, ...
    "Information-by-object diagnostics changed after slicing.");
assert(max(abs( details.coverageByObject-directCoverageByObject)) <= 1e-12, ...
    "Coverage-by-object diagnostics changed after slicing.");

%% Verify the database can be reused for an unconfigured network size
reusableNetworkSize = find(~ismember(1:numberOfCandidates,networkSizes),1,"first");
assert(~isempty(reusableNetworkSize), ...
    "The test requires at least one network size outside study metadata.");
reusableNetwork = (1:reusableNetworkSize).';
[reusableInformationObjective,reusableDetails] = optimization.networkObjective( reusableNetwork, ...
        database, "information");
reusableCoverageObjective = optimization.networkObjective( reusableNetwork, database, "coverage");
assert(isfinite(reusableInformationObjective), ...
    "An unconfigured network size produced a nonfinite information objective.");
assert(isfinite(reusableCoverageObjective), ...
    "An unconfigured network size produced a nonfinite coverage objective.");
assert(reusableDetails.feasible, ...
    "An unconfigured but valid network size was classified as infeasible.");
assert(reusableDetails.networkSize == reusableNetworkSize, ...
    "Unconfigured network-size diagnostics are inconsistent.");
assert(reusableInformationObjective ~= database.objective.infeasiblePenalty, ...
    "A valid unconfigured network size was penalized.");
assert(reusableCoverageObjective ~= database.objective.infeasiblePenalty, ...
    "A valid unconfigured network size was penalized.");

%% Penalty handling
if length(baseNetwork) >= 2
    duplicateNetwork = baseNetwork;
    duplicateNetwork(2) = duplicateNetwork(1);
    duplicateObjective = optimization.networkObjective( duplicateNetwork, database, "coverage");
    assert( duplicateObjective == database.objective.infeasiblePenalty, ...
        "Duplicate candidate indices were not penalized.");
end
outOfRangeNetwork = baseNetwork;
outOfRangeNetwork(end) = numberOfCandidates+1;
outOfRangeObjective = optimization.networkObjective( outOfRangeNetwork, database, "information");
assert( outOfRangeObjective == database.objective.infeasiblePenalty, ...
    "Out-of-range candidate was not penalized.");
emptyObjective = optimization.networkObjective( zeros(0,1), database, "coverage");
assert( emptyObjective == database.objective.infeasiblePenalty, "An empty network was not penalized.");

%% Saved database
assert(isfile(temporaryFile), "Database file was not saved.");
savedData = load(temporaryFile,"database");
assert(isfield(savedData,"database"), "Saved MAT file does not contain database.");
assert(isequal( savedData.database.prior.initialCovariance, database.prior.initialCovariance), ...
    "Saved fixed P0 differs from returned fixed P0.");
end

function testScalableBuild(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");

%% Pilot definition
numberOfPilotCandidates = 100;
expectedNumberOfObjects = 20;

% Current study values. Change only this vector to exercise different
% network sizes; the rest of this test is size agnostic.
networkSizes = sort(unique([3,5,7,10]));

%% Constants
moonRadius = 1737.4;

%% Load DEM
demPath = fullfile( projectRoot, "data", "Synthetic_Lunar_DEM.mat");
assert(isfile(demPath), "Synthetic DEM file was not found.");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( string(demPath), moonRadius, 24, 48);

%% Complete production candidate grid
[fullCandidateLatitudes,fullCandidateLongitudes] = digitalElevationModel.buildCandidateSensorGrid( ...
        deg2rad([-90,0]), deg2rad([0,360]), 15, moonRadius);
numberOfFullCandidates = length(fullCandidateLatitudes);
assert(numberOfFullCandidates == 84794, "Unexpected full southern-hemisphere candidate count.");
assert(numberOfFullCandidates >= numberOfPilotCandidates, ...
    "Production candidate grid is smaller than the requested pilot.");
fprintf("\n");
fprintf("Full production candidate grid\n");
fprintf("------------------------------\n");
fprintf("Candidate locations: %d\n",numberOfFullCandidates);

%% Spatially distributed pilot subset
pilotCandidateIndices = selectSpatialPilotCandidates( fullCandidateLatitudes, ...
        fullCandidateLongitudes, numberOfPilotCandidates);
pilotCandidateLatitudes = fullCandidateLatitudes(pilotCandidateIndices);
pilotCandidateLongitudes = fullCandidateLongitudes(pilotCandidateIndices);
fprintf("Pilot candidate locations: %d\n", length(pilotCandidateIndices));

%% Temporary output
temporaryFile = string(tempname) + ".mat";
cleanupObject = onCleanup(@()cleanupFile(temporaryFile)); %#ok<NASGU>

%% Production-like configuration
config = struct();
config.outputFile = temporaryFile;
config.overwriteOutput = false;
config.demSource = string(demPath);
config.study.networkSizes = networkSizes;
config.study.objectiveModes = ["information","coverage"];

%% 20 production RSOs
config.rso.selection = "generated";
config.rso.numberOfGeneratedObjects = expectedNumberOfObjects;
config.rso.periapsisAltitudeLimitsKm = [50,5000];
config.rso.inclinationLimitsRad = deg2rad([0,180]);
config.rso.eccentricityLimits = [0,0.8];

%% Pilot candidate locations
config.candidates.customLatitudesRad = pilotCandidateLatitudes;
config.candidates.customLongitudesRad = pilotCandidateLongitudes;
config.candidateFilter.enabled = true;
config.candidateFilter.minimumGeometricEpochsForAnyObject = 1;
config.candidateFilter.minimumFilteredEpochsTotal = 1;

%% Production terrain
config.terrain.maximumRangeKm = 100;
config.terrain.rangeStepKm = 0.5;
config.terrain.horizonAzimuthStepRad = deg2rad(0.1);
config.terrain.horizonMarginRad = 0;

%% Visibility
config.visibility.minimumElevationRad = 0;
config.visibility.minimumAngularSeparationRad = deg2rad(20);
config.visibility.earthRadiusKm = 6378.1366;
config.visibility.sunRadiusKm = 695700;

%% Tracking
config.tracking.outputStepSeconds = 60;
config.tracking.finalTimeSeconds = 8*3600;

%% Measurement
config.measurement.rightAscensionSigmaRad = deg2rad(1/3600);
config.measurement.declinationSigmaRad = deg2rad(1/3600);

%% One fixed-P0 reference IOD
config.iod.referencePeriapsisAltitudeKm = 50;
config.iod.referenceEccentricity = 0;
config.iod.referenceInclinationRad = deg2rad(90);
config.iod.referenceRaanRad = deg2rad(37);
config.iod.referenceArgumentOfPeriapsisRad = 0;
config.iod.referenceTrueAnomalyRad = 0;
config.iod.referenceSensorLatitudeRad = deg2rad(-89.505332);
config.iod.referenceSensorLongitudeRad = deg2rad(102.857143);
config.iod.outputStepSeconds = 10;
config.iod.desiredObservationCount = 15;
config.iod.searchEndFraction = 0.40;
config.iod.numberOfMonteCarloSamples = 500;
config.iod.measurementNoiseSeedBase = 1000;
config.iod.monteCarloSeedBase = 2000;

%% Estimation
config.estimation.accelerationNoiseIntensity = 1e-15;
config.estimation.stateScales = [1;1;1;1e-3;1e-3;1e-3];
config.estimation.objectWeights = ones(expectedNumberOfObjects,1);

%% Build
fprintf("\n");
fprintf("============================================================\n");
fprintf("Starting 20-RSO scalability database build\n");
fprintf("============================================================\n");
databaseTimer = tic;
database = optimization.buildOptimizationDatabase( dem, config);
measuredBuildRuntimeSeconds = toc(databaseTimer);

%% Structural checks
numberOfObjects = database.meta.numberOfObjects;
numberOfCandidatesRetained = database.meta.numberOfCandidates;
numberOfOptimizationTimes = database.meta.numberOfOptimizationEpochs;
assert(numberOfObjects == expectedNumberOfObjects, "Expected 20 RSOs.");
assert(numberOfCandidatesRetained >= max(networkSizes), ...
    "Too few candidate locations survived screening.");
assert(numberOfOptimizationTimes == config.tracking.finalTimeSeconds / ...
    config.tracking.outputStepSeconds, "Unexpected optimization epoch count.");
assert(isequal(database.study.networkSizes,networkSizes), ...
    "Database network-size configuration changed.");

%% Verify single fixed P0 and exact IOD calibration
P0 = database.prior.initialCovariance;
assert(all(isfinite(P0),"all"), "Fixed P0 contains nonfinite values.");
[~,positiveDefiniteFlag] = chol( 0.5*(P0+P0.'), "lower");
assert(positiveDefiniteFlag == 0, "Fixed P0 is not positive definite.");
for objectIndex = 1:numberOfObjects
    assert(isequal( database.prior.initialCovariances(:,:,objectIndex), P0), ...
        "RSO %d does not use the common fixed P0.", objectIndex);
end
assert( length(database.iod.calibration.acquisitionIndices) == config.iod.desiredObservationCount, ...
    "Reference IOD did not use the requested observation count.");
assert( database.iod.calibration.desiredObservationCount == config.iod.desiredObservationCount, ...
    "Stored IOD observation-count metadata is inconsistent.");
assert( database.iod.calibration.outputStepSeconds == config.iod.outputStepSeconds, ...
    "Stored IOD cadence is inconsistent.");
assert( database.iod.calibration.diagnostics.numberOfRequestedSamples == ...
    config.iod.numberOfMonteCarloSamples, "Reference IOD Monte Carlo sample count changed.");
assert( database.iod.calibration.diagnostics.numberOfSuccessfulSamples >= ...
    ceil(0.8*config.iod.numberOfMonteCarloSamples), ...
    "Reference IOD Monte Carlo convergence is below 80 percent.");

%% All 20 RSOs remain in population regardless of visibility
assert(height(database.rso.catalog) == expectedNumberOfObjects, ...
    "An RSO was removed from the population.");
assert(size( database.visibility.filteredAvailability,3) == expectedNumberOfObjects, ...
    "Visibility database does not contain all 20 RSOs.");

%% Accepted measurements by RSO
acceptedObservationsByObject = reshape( sum( database.visibility.filteredAvailability, [1,2]), ...
        numberOfObjects, 1);
unobservableObjectMask = acceptedObservationsByObject == 0;
numberOfUnobservableObjects = nnz(unobservableObjectMask);
assert(all(isfinite(acceptedObservationsByObject)), "Observation counts are invalid.");

%% Numerical database checks
assert(all(isfinite( database.tracking.referenceStateHistories),"all"));
assert(all(isfinite( database.tracking.stateTransitionHistories),"all"));
assert(all(isfinite( database.tracking.processNoiseHistories),"all"));
assert(size(database.tracking.measurementJacobianHistories,2) == 3, ...
    "Scalability database did not use compact position-only Jacobians.");
assert(all(isfinite( database.tracking.measurementJacobianHistories),"all"));
assert(all( database.visibility.filteredAvailability <= database.visibility.terrainAvailability, ...
    "all"));
assert(all( database.visibility.terrainAvailability <= database.visibility.geometricAvailability, ...
    "all"));

%% Representative nested networks for every configured size
maximumNetworkSize = max(networkSizes);
maximumNetwork = evenlyDistributedIndices( numberOfCandidatesRetained, maximumNetworkSize);
numberOfNetworkSizes = length(networkSizes);
representativeNetworks = cell(numberOfNetworkSizes,1);
for sizeIndex = 1:numberOfNetworkSizes
    representativeNetworks{sizeIndex} = maximumNetwork(1:networkSizes(sizeIndex));
end

%% Objective timing for every configured network size
informationObjectives = zeros(numberOfNetworkSizes,1);
coverageObjectives = zeros(numberOfNetworkSizes,1);
informationRuntimes = zeros(numberOfNetworkSizes,1);
coverageRuntimes = zeros(numberOfNetworkSizes,1);
for sizeIndex = 1:numberOfNetworkSizes
    currentNetwork = representativeNetworks{sizeIndex};
    timer = tic;
    informationObjectives(sizeIndex) = optimization.networkObjective( currentNetwork, database, ...
            "information");
    informationRuntimes(sizeIndex) = toc(timer);
    timer = tic;
    coverageObjectives(sizeIndex) = optimization.networkObjective( currentNetwork, database, ...
            "coverage");
    coverageRuntimes(sizeIndex) = toc(timer);
end
assert(all(isfinite(informationObjectives)), "At least one information objective is nonfinite.");
assert(all(isfinite(coverageObjectives)), "At least one coverage objective is nonfinite.");
for sizeIndex = 2:numberOfNetworkSizes
    assert( coverageObjectives(sizeIndex) <= coverageObjectives(sizeIndex-1)+1e-12, ...
        "Adding sensors reduced coverage.");
end

%% Slicing equivalence, determinism, and sensor-order invariance
baseNetwork = representativeNetworks{1};
fullSelectedSensors = false(numberOfCandidatesRetained,1);
fullSelectedSensors(baseNetwork) = true;
[directInformationObjective,directInformationByObject] = optimization.informationObjective( ...
        fullSelectedSensors, database.prior.initialCovariances, ...
        database.tracking.stateTransitionHistories, database.tracking.processNoiseHistories, ...
        database.tracking.measurementJacobianHistories, database.visibility.filteredAvailability, ...
        database.measurement.covariance, database.estimation.stateScales, ...
        database.estimation.objectWeights);
[directCoverageObjective,directCoverageByObject] = optimization.coverageObjective( ...
        fullSelectedSensors, database.visibility.filteredAvailability, ...
        database.estimation.objectWeights);
informationTolerance = 1e-12*max(1,abs(informationObjectives(1)));
assert(abs( directInformationObjective-informationObjectives(1)) <= informationTolerance, ...
    "Selected-sensor slicing changed the information objective.");
assert(abs( directCoverageObjective-coverageObjectives(1)) <= 1e-12, ...
    "Selected-sensor slicing changed the coverage objective.");
informationRepeat = optimization.networkObjective( baseNetwork, database, "information");
assert(abs( informationRepeat-informationObjectives(1)) <= informationTolerance, ...
    "Information objective is not deterministic.");
permutedNetwork = baseNetwork(end:-1:1);
informationPermuted = optimization.networkObjective( permutedNetwork, database, "information");
coveragePermuted = optimization.networkObjective( permutedNetwork, database, "coverage");
assert(abs( informationPermuted-informationObjectives(1)) <= informationTolerance, ...
    "Information objective depends on sensor order.");
assert(abs( coveragePermuted-coverageObjectives(1)) <= 1e-12, ...
    "Coverage objective depends on sensor order.");
[~,details] = optimization.networkObjective( baseNetwork, database, "information");
assert(max(abs( details.informationByObject-directInformationByObject)) <= informationTolerance, ...
    "Information-by-object diagnostics changed after slicing.");
assert(max(abs( details.coverageByObject-directCoverageByObject)) <= 1e-12, ...
    "Coverage-by-object diagnostics changed after slicing.");

%% Memory accounting
jacobianBytes = numel( database.tracking.measurementJacobianHistories) * 8;
stateTransitionBytes = numel( database.tracking.stateTransitionHistories) * 8;
processNoiseBytes = numel( database.tracking.processNoiseHistories) * 8;
referenceStateBytes = numel( database.tracking.referenceStateHistories) * 8;
filteredAvailabilityBytes = numel( database.visibility.filteredAvailability);
majorTrackingBytes = jacobianBytes + stateTransitionBytes + processNoiseBytes + ...
    referenceStateBytes + filteredAvailabilityBytes;
pilotRetentionFraction = numberOfCandidatesRetained / numberOfPilotCandidates;
estimatedFullRetainedCandidates = round( pilotRetentionFraction * numberOfFullCandidates);
jacobianBytesPerCandidate = jacobianBytes / numberOfCandidatesRetained;
estimatedFullJacobianBytes = jacobianBytesPerCandidate * estimatedFullRetainedCandidates;
end

function testProductionChunks(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");

%% Load core production database
databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
assert(isfile(databaseFile), ["Production optimization database was not found. " ...
     "Run scripts/database/buildProductionOptimizationDatabase.m first.\n%s"], databaseFile);
databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), "optimization_database.mat does not contain database.");
database = databaseData.database;

%% Candidate-domain definition
moonRadiusKm = 1737.4;
expectedLatitudeBandRad = deg2rad([-90,0]);
expectedLongitudeBandRad = deg2rad([0,360]);
expectedSpacingKm = 15;
[expectedCandidateLatitudes,expectedCandidateLongitudes] = ...
    digitalElevationModel.buildCandidateSensorGrid( expectedLatitudeBandRad, ...
        expectedLongitudeBandRad, expectedSpacingKm, moonRadiusKm);
expectedInitialCandidates = numel(expectedCandidateLatitudes);
assert(expectedInitialCandidates == 84794, ...
    "The expected 15-km southern-hemisphere grid count changed.");
assert(max(abs(database.config.candidates.latitudeBandRad(:) - expectedLatitudeBandRad(:))) < 1e-12, ...
    "Production database does not use the full southern hemisphere.");
assert(max(abs(database.config.candidates.longitudeBandRad(:) - ...
    expectedLongitudeBandRad(:))) < 1e-12, "Production longitude domain is inconsistent.");
assert(abs(database.config.candidates.spacingKm-expectedSpacingKm) < 1e-12, ...
    "Production candidate spacing is not 15 km.");
assert(database.meta.numberOfCandidatesBeforeFiltering == expectedInitialCandidates, ...
    "Initial candidate count does not match the southern-hemisphere grid.");

%% Timing / RSO definition
expectedTrackingStepSeconds = 10*60;
expectedFinalTimeSeconds = 3*24*3600;
expectedOptimizationEpochs = expectedFinalTimeSeconds/expectedTrackingStepSeconds;
assert(expectedOptimizationEpochs == 432);
assert(database.config.tracking.outputStepSeconds == expectedTrackingStepSeconds, ...
    "Production database does not use a 10-minute cadence.");
assert(database.config.tracking.finalTimeSeconds == expectedFinalTimeSeconds, ...
    "Production database does not use a three-day horizon.");
assert(database.meta.numberOfOptimizationEpochs == expectedOptimizationEpochs, ...
    "Production database does not contain 432 optimization epochs.");
assert(database.meta.numberOfObjects == 20, ...
    "Production database must contain the 20-object RSO population.");
trackingTimes = database.tracking.times(:);
assert(numel(trackingTimes) == expectedOptimizationEpochs, ...
    "Tracking-time vector has the wrong number of epochs.");
assert(abs(trackingTimes(1)-expectedTrackingStepSeconds) < 1e-9, ...
    "First optimization epoch should occur at 600 seconds.");
assert(abs(trackingTimes(end)-expectedFinalTimeSeconds) < 1e-9, ...
    "Last optimization epoch should occur at exactly three days.");
assert(all(abs(diff(trackingTimes)-expectedTrackingStepSeconds) < 1e-9), ...
    "Tracking times are not uniformly separated by 600 seconds.");

%% Core database must be lean
numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;
assert(numberOfCandidates >= 10 && numberOfCandidates <= expectedInitialCandidates, ...
    "Retained candidate count is invalid.");
assert(string(database.meta.version) == ...
    "lunar_surface_optimization_database_v5_chunked_candidate_data", ...
    "Production database version is not the early-chunked architecture.");
assert(ismember(string(database.meta.measurementJacobianStorage),["chunked_full_state","chunked_position","on_demand"]), ...
    "Production database does not use chunked full-state Jacobians.");
assert(string(database.meta.visibilityStorage) == "chunked_filtered_availability", ...
    "Production visibility is not stored in candidate chunks.");
assert(string(database.meta.terrainStorage) == "chunked_horizons", ...
    "Production terrain is not stored in candidate chunks.");
assert(ismember(database.meta.measurementJacobianStateColumns,[3 6]), ...
    "Production Jacobians must retain all six state columns.");
assert(database.meta.numberOfMeasurementJacobianChunks == 6, ...
    "Production database must contain six candidate chunks.");
assert(isempty(database.tracking.measurementJacobianHistories), ...
    "Core database should not contain a monolithic Jacobian array.");
assert(isempty(database.visibility.filteredAvailability), ...
    "Core database should not contain monolithic filtered visibility.");
assert(isempty(database.terrain.maximumTerrainElevationRad), ...
    "Core database should not contain monolithic terrain horizons.");

%% Chunk metadata and original equal-count partition
chunks = database.tracking.measurementJacobianChunks;
assert(numel(chunks) == 6, "Production database must contain six candidate chunks.");
assert(numel(database.visibility.candidateChunks) == 6, "Visibility chunk metadata are missing.");
assert(numel(database.terrain.candidateChunks) == 6, "Terrain chunk metadata are missing.");
originalChunkCounts = [chunks.numberOfOriginalCandidates].';
retainedChunkCounts = [chunks.numberOfRetainedCandidates].';
assert(sum(originalChunkCounts) == expectedInitialCandidates, ...
    "Original chunk counts do not cover the complete candidate grid.");
assert(max(originalChunkCounts)-min(originalChunkCounts) <= 1, ...
    "Original candidate chunks are not equal-sized to within one candidate.");
assert(sum(retainedChunkCounts) == numberOfCandidates, ...
    "Retained chunk counts do not cover the retained candidate set.");
expectedOriginalIndices = (1:expectedInitialCandidates).';
reconstructedOriginalIndices = zeros(0,1);
reconstructedRetainedGlobalIndices = zeros(0,1);
for chunkIndex = 1:6
    metadata = chunks(chunkIndex);
    chunkFile = string(metadata.filePath);
    assert(isfile(chunkFile), "Candidate chunk file was not found: %s",chunkFile);
    chunkMat = matfile(chunkFile);
    originalIndices = double(chunkMat.originalCandidateIndices(:,1));
    assert(numel(originalIndices) == metadata.numberOfOriginalCandidates, ...
        "Chunk %d original index count is inconsistent.",chunkIndex);
    assert(originalIndices(1) == metadata.firstOriginalCandidateIndex && ...
        originalIndices(end) == metadata.lastOriginalCandidateIndex, ...
        "Chunk %d original index bounds are inconsistent.",chunkIndex);
    reconstructedOriginalIndices = [ reconstructedOriginalIndices
        originalIndices]; %#ok<AGROW>
    terrainSize = size(chunkMat,'maximumTerrainElevationRad');
    assert(terrainSize(1) == metadata.numberOfOriginalCandidates, ...
        "Chunk %d terrain candidate dimension is inconsistent.",chunkIndex);
    assert(terrainSize(2) == numel(database.terrain.horizonAzimuthsRad), ...
        "Chunk %d terrain azimuth dimension is inconsistent.",chunkIndex);
    retainedGlobal = double(chunkMat.retainedGlobalCandidateIndices(:,1));
    retainedOriginal = double(chunkMat.retainedOriginalCandidateIndices(:,1));
    assert(numel(retainedGlobal) == metadata.numberOfRetainedCandidates, ...
        "Chunk %d retained global index count is inconsistent.",chunkIndex);
    assert(numel(retainedOriginal) == metadata.numberOfRetainedCandidates, ...
        "Chunk %d retained original index count is inconsistent.",chunkIndex);
    if metadata.numberOfRetainedCandidates > 0
        assert(all(diff(retainedGlobal) == 1), ...
            "Chunk %d retained global indices are not contiguous.",chunkIndex);
        visibilitySize = size(chunkMat,'filteredAvailability');
        assert(visibilitySize(1) == metadata.numberOfRetainedCandidates && ...
            visibilitySize(2) == expectedOptimizationEpochs && visibilitySize(3) == numberOfObjects, ...
            "Chunk %d final visibility dimensions are inconsistent.",chunkIndex);
        if database.meta.measurementJacobianStorage ~= "on_demand"
        jacobianSize = size(chunkMat,'measurementJacobianHistories');
        assert(numel(jacobianSize) == 5 && jacobianSize(1) == 2 && jacobianSize(2) == database.meta.measurementJacobianStateColumns && ...
            jacobianSize(3) == metadata.numberOfRetainedCandidates && ...
            jacobianSize(4) == expectedOptimizationEpochs && jacobianSize(5) == numberOfObjects, ...
            "Chunk %d Jacobian dimensions are inconsistent.",chunkIndex);
        end
        mappedChunk = double(database.candidates.chunkIndex(retainedGlobal));
        mappedLocal = double(database.candidates.chunkLocalIndex(retainedGlobal));
        mappedOriginalLocal = double(database.candidates.originalChunkLocalIndex(retainedGlobal));
        assert(all(mappedChunk == chunkIndex), ...
            "Global-to-chunk map is incorrect for chunk %d.",chunkIndex);
        assert(isequal(mappedLocal(:), (1:metadata.numberOfRetainedCandidates).'), ...
            "Retained local-index map is incorrect for chunk %d.",chunkIndex);
        expectedOriginalLocal = retainedOriginal-metadata.firstOriginalCandidateIndex+1;
        assert(isequal(mappedOriginalLocal(:),expectedOriginalLocal(:)), ...
            "Original local-index map is incorrect for chunk %d.",chunkIndex);
    end
    reconstructedRetainedGlobalIndices = [ reconstructedRetainedGlobalIndices
        retainedGlobal]; %#ok<AGROW>
end
assert(isequal(reconstructedOriginalIndices,expectedOriginalIndices), ...
    "Original chunks do not cover every candidate exactly once.");
assert(isequal(reconstructedRetainedGlobalIndices,(1:numberOfCandidates).'), ...
    "Retained chunk indices do not cover every optimization candidate exactly once.");

%% Partial indexing checks for visibility, terrain, and Jacobians
sampleCandidates = unique(round(linspace(1,numberOfCandidates,6))).';
loadedAvailability = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"filteredAvailability");
assert(isequal(size(loadedAvailability), ...
    [numel(sampleCandidates),expectedOptimizationEpochs,numberOfObjects]), ...
    "Partial visibility lookup returned inconsistent dimensions.");
loadedTerrain = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"maximumTerrainElevationRad");
assert(isequal(size(loadedTerrain), ...
    [numel(sampleCandidates),numel(database.terrain.horizonAzimuthsRad)]), ...
    "Partial terrain lookup returned inconsistent dimensions.");
loadedJacobians = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"measurementJacobianHistories");
assert(size(loadedJacobians,1) == 2 && size(loadedJacobians,2) == 6 && ...
    size(loadedJacobians,3) == numel(sampleCandidates) && ...
    size(loadedJacobians,4) == expectedOptimizationEpochs && ...
    size(loadedJacobians,5) == numberOfObjects, ...
    "Partial Jacobian lookup returned inconsistent dimensions.");

%% Analytic Jacobian spot checks
syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
assert(isfile(syntheticDemFile), "Synthetic DEM was not found: %s",syntheticDemFile);
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( string(syntheticDemFile),moonRadiusKm,24,48);
sampleTimes = unique(round(linspace(1,expectedOptimizationEpochs,3))).';
sampleObjects = unique(round(linspace(1,numberOfObjects,3))).';
moonAngularRate = 2*pi/double(database.config.moon.siderealPeriodSeconds);
theta0Rad = double(database.config.moon.theta0Rad);
maximumJacobianError = 0;
for sampleIndex = 1:3
    candidateIndex = sampleCandidates(sampleIndex);
    timeIndex = sampleTimes(sampleIndex);
    objectIndex = sampleObjects(sampleIndex);
    storedJacobian = optimization.loadChunkedCandidateData( ...
        database,candidateIndex,"measurementJacobianHistories");
    storedJacobian = storedJacobian(:,:,1,timeIndex,objectIndex);
    analyticJacobian = measurements.surfaceRaDecJacobian( ...
        database.tracking.referenceStateHistories(:,timeIndex,objectIndex), ...
        database.tracking.times(timeIndex), database.candidates.latitudesRad(candidateIndex), ...
        database.candidates.longitudesRad(candidateIndex), dem, moonRadiusKm, theta0Rad, ...
        moonAngularRate);
    maximumJacobianError = max( maximumJacobianError, ...
        max(abs(storedJacobian-analyticJacobian),[],"all"));
    assert(all(storedJacobian(:,4:6) == 0,"all"), ...
        "Stored full Jacobian velocity columns are not identically zero.");
end
assert(maximumJacobianError < 1e-12, "Chunked Jacobians do not match the analytic RA/Dec Jacobian.");

%% Objective smoke test across chunk boundaries
nonemptyChunks = find([chunks.numberOfRetainedCandidates] > 0);
representativeNetwork = zeros(0,1);
for chunkIndex = nonemptyChunks(:).'
    candidatesInChunk = find( double(database.candidates.chunkIndex) == chunkIndex);
    representativeNetwork(end+1,1) = ... %#ok<SAGROW>
        candidatesInChunk(round((numel(candidatesInChunk)+1)/2));
    if numel(representativeNetwork) == 3
        break
    end
end
if numel(representativeNetwork) < 3
    representativeNetwork = unique(round(linspace( 1,numberOfCandidates,3))).';
end
assert(numel(representativeNetwork) == 3, "Could not construct a representative three-sensor network.");
informationObjective = optimization.networkObjective( representativeNetwork,database,"information");
coverageObjective = optimization.networkObjective( representativeNetwork,database,"coverage");
assert(isfinite(informationObjective), "Chunked information objective is nonfinite.");
assert(isfinite(coverageObjective), "Chunked coverage objective is nonfinite.");
informationRepeat = optimization.networkObjective( representativeNetwork,database,"information");
informationTolerance = 1e-12*max(1,abs(informationObjective));
assert(abs(informationRepeat-informationObjective) <= informationTolerance, ...
    "Chunked information objective is not deterministic.");

%% Off-grid evaluator agrees at exact frozen candidate locations

%% Resolve DEM
candidateDemFiles = strings(0,1);
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateDemFiles(end+1,1) = string(database.meta.demSource); %#ok<SAGROW>
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateDemFiles(end+1,1) = string(database.config.demSource); %#ok<SAGROW>
end
candidateDemFiles = [candidateDemFiles; ...
    string(fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat")); ...
    string(fullfile(projectRoot,"data","Full_Resolution_DEM.mat"))];
demFile = "";
for index = 1:numel(candidateDemFiles)
    if strlength(candidateDemFiles(index)) > 0 && isfile(candidateDemFiles(index))
        demFile = candidateDemFiles(index);
        break
    end
end
assert(strlength(demFile) > 0,"No compatible lunar DEM was found.");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( demFile,database.config.moon.radiusKm,24,48);

%% Representative discrete network
numberOfCandidates = database.meta.numberOfCandidates;
sensorIndices = unique(round(linspace(1,numberOfCandidates,3))).';
assert(numel(sensorIndices) == 3,"Could not construct a 3-sensor test network.");
latitudesRad = database.candidates.latitudesRad(sensorIndices);
longitudesRad = database.candidates.longitudesRad(sensorIndices);

%% Continuous evaluation
continuous = optimization.evaluatePerturbedNetwork( latitudesRad,longitudesRad,database,dem);

%% Discrete evaluation
[informationObjective,informationDetails] = ...
    optimization.networkObjective(sensorIndices,database,"information");
[coverageObjective,coverageDetails] = optimization.networkObjective(sensorIndices,database,"coverage");
informationTolerance = 1e-7*max(1,abs(informationObjective));
coverageTolerance = 1e-10*max(1,abs(coverageObjective));
assert(abs(continuous.informationObjectiveValue-informationObjective) <= informationTolerance, ...
    ["Continuous information objective does not reproduce the discrete " ...
     "candidate objective. Continuous %.12g, discrete %.12g."], ...
    continuous.informationObjectiveValue,informationObjective);
assert(abs(continuous.coverageObjectiveValue-coverageObjective) <= coverageTolerance, ...
    ["Continuous coverage objective does not reproduce the discrete " ...
     "candidate objective. Continuous %.12g, discrete %.12g."], ...
    continuous.coverageObjectiveValue,coverageObjective);
assert(max(abs(continuous.informationByObject-informationDetails.informationByObject)) <= ...
    1e-7*max(1,max(abs(informationDetails.informationByObject))), ...
    "Per-RSO information results differ from the discrete evaluator.");
assert(isequal(continuous.coverageByObject,coverageDetails.coverageByObject), ...
    "Per-RSO coverage results differ from the discrete evaluator.");
end

function state = circularOrbitState( orbitRadius, inclination, raan, trueAnomaly, moonMu)
rotationZ = [ cos(raan),-sin(raan),0
     sin(raan), cos(raan),0
     0,0,1
];
rotationX = [ 1,0,0
    0,cos(inclination),-sin(inclination)
    0,sin(inclination), cos(inclination)
];
perifocalPosition = orbitRadius*[ cos(trueAnomaly)
        sin(trueAnomaly)
        0
    ];
circularSpeed = sqrt(moonMu/orbitRadius);
perifocalVelocity = circularSpeed*[ -sin(trueAnomaly)
         cos(trueAnomaly)
         0
    ];
rotation = rotationZ*rotationX;
state = [ rotation*perifocalPosition
    rotation*perifocalVelocity
];
end

function cleanupFile(fileName)
if isfile(fileName)
    try
        delete(fileName);
    catch
    end
end
end

function selectedIndices = selectSpatialPilotCandidates( candidateLatitudes, candidateLongitudes, ...
        targetCount)
candidateLatitudes = candidateLatitudes(:);
candidateLongitudes = candidateLongitudes(:);
numberOfCandidates = length(candidateLatitudes);
assert(targetCount <= numberOfCandidates);
uniqueLatitudes = unique(candidateLatitudes);
numberOfLatitudeRings = length(uniqueLatitudes);
desiredNumberOfRings = min(12,numberOfLatitudeRings);
ringLocations = unique(round(linspace( 1, numberOfLatitudeRings, desiredNumberOfRings)));
selectedIndices = zeros(0,1);
numberPerRing = ceil(targetCount/length(ringLocations));
latitudeTolerance = 1e-12;
for ringIndex = 1:length(ringLocations)
    ringLatitude = uniqueLatitudes(ringLocations(ringIndex));
    ringIndices = find(abs( candidateLatitudes-ringLatitude) < latitudeTolerance);
    [~,longitudeOrder] = sort(candidateLongitudes(ringIndices));
    ringIndices = ringIndices(longitudeOrder);
    numberToTake = min(numberPerRing,length(ringIndices));
    locations = unique(round(linspace( 1, length(ringIndices), numberToTake)));
    selectedIndices = [ selectedIndices
        ringIndices(locations)
    ]; %#ok<AGROW>
end
selectedIndices = unique(selectedIndices,"stable");
if length(selectedIndices) < targetCount
    unused = setdiff( (1:numberOfCandidates).', selectedIndices, "stable");
    numberNeeded = targetCount-length(selectedIndices);
    fillLocations = unique(round(linspace( 1, length(unused), numberNeeded)));
    selectedIndices = [ selectedIndices
        unused(fillLocations)
    ];
end
if length(selectedIndices) > targetCount
    locations = round(linspace( 1, length(selectedIndices), targetCount));
    selectedIndices = selectedIndices(locations);
end
if length(selectedIndices) < targetCount
    unused = setdiff( (1:numberOfCandidates).', selectedIndices, "stable");
    numberNeeded = targetCount-length(selectedIndices);
    selectedIndices = [ selectedIndices
        unused(1:numberNeeded)
    ];
end
assert(length(selectedIndices) == targetCount);
assert(length(unique(selectedIndices)) == targetCount);
selectedIndices = sort(selectedIndices);
end

function indices = evenlyDistributedIndices( numberOfCandidates, numberToSelect)
assert(numberToSelect <= numberOfCandidates);
indices = unique(round(linspace( 1, numberOfCandidates, numberToSelect)));
if length(indices) < numberToSelect
    unused = setdiff( 1:numberOfCandidates, indices, "stable");
    indices = [ indices, unused(1:numberToSelect-length(indices)) ];
end
indices = sort(indices(:));
assert(length(indices) == numberToSelect);
assert(length(unique(indices)) == numberToSelect);
end

%% testProductionOptimizationDatabase
% Post-build validation of the production optimization database.
%
% Run immediately after scripts/buildProductionOptimizationDatabase.m and
% before starting the 12000-FE production campaign. This validates:
%   - full southern-hemisphere 15-km candidate grid;
%   - 20 RSOs, three-day arc, 10-minute cadence, 432 update epochs;
%   - six equal-count full 2x6 RA/Dec Jacobian chunk files;
%   - global candidate -> chunk/local index mapping;
%   - MATFILE partial indexing and analytic Jacobian agreement;
%   - deterministic information/coverage objective evaluation.

clear;
close all;
clc;

%% Project paths

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
dataDirectory = fullfile(projectRoot,"data");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

%% Load core production database

databaseFile = fullfile(resultsDirectory,"optimization_database.mat");

assert(isfile(databaseFile), ...
    ["Production optimization database was not found. " ...
     "Run scripts/buildProductionOptimizationDatabase.m first.\n%s"], ...
    databaseFile);

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
database = databaseData.database;

%% Candidate-domain definition

moonRadiusKm = 1737.4;
expectedLatitudeBandRad = deg2rad([-90,0]);
expectedLongitudeBandRad = deg2rad([0,360]);
expectedSpacingKm = 15;

[expectedCandidateLatitudes,expectedCandidateLongitudes] = ...
    digitalElevationModel.buildCandidateSensorGrid( ...
        expectedLatitudeBandRad, ...
        expectedLongitudeBandRad, ...
        expectedSpacingKm, ...
        moonRadiusKm);

expectedInitialCandidates = numel(expectedCandidateLatitudes);

assert(expectedInitialCandidates == 84794, ...
    "The expected 15-km southern-hemisphere grid count changed.");

assert(max(abs(database.config.candidates.latitudeBandRad(:) - ...
    expectedLatitudeBandRad(:))) < 1e-12, ...
    "Production database does not use the full southern hemisphere.");

assert(max(abs(database.config.candidates.longitudeBandRad(:) - ...
    expectedLongitudeBandRad(:))) < 1e-12, ...
    "Production longitude domain is inconsistent.");

assert(abs(database.config.candidates.spacingKm-expectedSpacingKm) < 1e-12, ...
    "Production candidate spacing is not 15 km.");

assert(database.meta.numberOfCandidatesBeforeFiltering == ...
    expectedInitialCandidates, ...
    "Initial candidate count does not match the southern-hemisphere grid.");

%% Timing / RSO definition

expectedTrackingStepSeconds = 10*60;
expectedFinalTimeSeconds = 3*24*3600;
expectedOptimizationEpochs = ...
    expectedFinalTimeSeconds/expectedTrackingStepSeconds;

assert(expectedOptimizationEpochs == 432);

assert(database.config.tracking.outputStepSeconds == ...
    expectedTrackingStepSeconds, ...
    "Production database does not use a 10-minute cadence.");

assert(database.config.tracking.finalTimeSeconds == ...
    expectedFinalTimeSeconds, ...
    "Production database does not use a three-day horizon.");

assert(database.meta.numberOfOptimizationEpochs == ...
    expectedOptimizationEpochs, ...
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

%% Retained candidates

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

assert(numberOfCandidates >= 10, ...
    "Production candidate filter retained fewer than ten sites.");
assert(numberOfCandidates <= expectedInitialCandidates, ...
    "Retained candidate count exceeds the unfiltered grid.");

assert(all(database.candidates.latitudesRad >= -pi/2-1e-12) && ...
       all(database.candidates.latitudesRad <= 1e-12), ...
    "A retained candidate lies outside the southern hemisphere.");

assert(size(database.visibility.filteredAvailability,1) == numberOfCandidates, ...
    "Visibility candidate dimension is inconsistent.");
assert(size(database.visibility.filteredAvailability,2) == expectedOptimizationEpochs, ...
    "Visibility time dimension is inconsistent.");
assert(size(database.visibility.filteredAvailability,3) == numberOfObjects, ...
    "Visibility RSO dimension is inconsistent.");

%% Chunked full-state Jacobian definition

assert(isfield(database.meta,"measurementJacobianStorage") && ...
    string(database.meta.measurementJacobianStorage) == "chunked_full_state", ...
    "Production database does not use chunked full-state Jacobians.");

assert(isfield(database.meta,"measurementJacobianStateColumns") && ...
    database.meta.measurementJacobianStateColumns == 6, ...
    "Production Jacobians must retain all six state columns.");

assert(isfield(database.meta,"numberOfMeasurementJacobianChunks") && ...
    database.meta.numberOfMeasurementJacobianChunks == 6, ...
    "Production database must contain six Jacobian chunks.");

assert(isfield(database.tracking,"measurementJacobianChunks") && ...
    numel(database.tracking.measurementJacobianChunks) == 6, ...
    "Jacobian chunk metadata are missing.");

assert(isfield(database.tracking,"measurementJacobianHistories") && ...
    isempty(database.tracking.measurementJacobianHistories), ...
    "Core database should not contain a monolithic Jacobian array.");

assert(isfield(database.candidates,"jacobianChunkIndex") && ...
    numel(database.candidates.jacobianChunkIndex) == numberOfCandidates, ...
    "Global-to-chunk candidate map is missing.");

assert(isfield(database.candidates,"jacobianChunkLocalIndex") && ...
    numel(database.candidates.jacobianChunkLocalIndex) == numberOfCandidates, ...
    "Global-to-local candidate map is missing.");

chunkCounts = zeros(6,1);
reconstructedGlobalIndices = zeros(0,1);

for chunkIndex = 1:6
    metadata = database.tracking.measurementJacobianChunks(chunkIndex);
    chunkFile = string(metadata.filePath);

    assert(isfile(chunkFile), ...
        "Jacobian chunk file was not found: %s",chunkFile);

    chunkMat = matfile(chunkFile);
    chunkSize = size(chunkMat,'measurementJacobianHistories');

    expectedChunkCount = double(metadata.numberOfCandidates);
    chunkCounts(chunkIndex) = expectedChunkCount;

    assert(numel(chunkSize) == 5 && ...
        chunkSize(1) == 2 && ...
        chunkSize(2) == 6 && ...
        chunkSize(3) == expectedChunkCount && ...
        chunkSize(4) == expectedOptimizationEpochs && ...
        chunkSize(5) == numberOfObjects, ...
        "Jacobian chunk %d has inconsistent dimensions.",chunkIndex);

    globalIndices = double(chunkMat.globalCandidateIndices(:));

    assert(numel(globalIndices) == expectedChunkCount, ...
        "Chunk %d global-index list has the wrong length.",chunkIndex);

    assert(globalIndices(1) == metadata.firstGlobalCandidateIndex && ...
        globalIndices(end) == metadata.lastGlobalCandidateIndex, ...
        "Chunk %d metadata does not match its stored global indices.",chunkIndex);

    expectedGlobalIndices = ...
        (metadata.firstGlobalCandidateIndex:metadata.lastGlobalCandidateIndex).';

    assert(isequal(globalIndices,expectedGlobalIndices), ...
        "Chunk %d global candidate indices are not contiguous.",chunkIndex);

    mappedChunk = double(database.candidates.jacobianChunkIndex(globalIndices));
    mappedLocal = double(database.candidates.jacobianChunkLocalIndex(globalIndices));

    assert(all(mappedChunk == chunkIndex), ...
        "Global-to-chunk map is incorrect for chunk %d.",chunkIndex);
    assert(isequal(mappedLocal(:),(1:expectedChunkCount).'), ...
        "Global-to-local map is incorrect for chunk %d.",chunkIndex);

    reconstructedGlobalIndices = [ ...
        reconstructedGlobalIndices
        globalIndices]; %#ok<AGROW>
end

assert(max(chunkCounts)-min(chunkCounts) <= 1, ...
    "Jacobian chunks are not equal-sized to within one candidate.");

assert(isequal(reconstructedGlobalIndices,(1:numberOfCandidates).'), ...
    "Chunk files do not cover every retained global candidate exactly once.");

%% Stored-vs-analytic Jacobian checks through partial indexing

syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
assert(isfile(syntheticDemFile), ...
    "Synthetic DEM was not found: %s",syntheticDemFile);

[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(syntheticDemFile),moonRadiusKm,24,48);

sampleCandidates = unique(round(linspace(1,numberOfCandidates,3))).';
sampleTimes = unique(round(linspace(1,expectedOptimizationEpochs,3))).';
sampleObjects = unique(round(linspace(1,numberOfObjects,3))).';

moonAngularRate = ...
    2*pi/double(database.config.moon.siderealPeriodSeconds);
theta0Rad = double(database.config.moon.theta0Rad);

maximumJacobianError = 0;

for sampleIndex = 1:min([numel(sampleCandidates),numel(sampleTimes),numel(sampleObjects)])
    candidateIndex = sampleCandidates(sampleIndex);
    timeIndex = sampleTimes(sampleIndex);
    objectIndex = sampleObjects(sampleIndex);

    loadedHistory = optimization.loadChunkedMeasurementJacobians( ...
        database,candidateIndex);

    storedJacobian = loadedHistory(:,:,1,timeIndex,objectIndex);

    analyticJacobian = measurements.surfaceRaDecJacobian( ...
        database.tracking.referenceStateHistories(:,timeIndex,objectIndex), ...
        database.tracking.times(timeIndex), ...
        database.candidates.latitudesRad(candidateIndex), ...
        database.candidates.longitudesRad(candidateIndex), ...
        dem, ...
        moonRadiusKm, ...
        theta0Rad, ...
        moonAngularRate);

    maximumJacobianError = max( ...
        maximumJacobianError, ...
        max(abs(storedJacobian-analyticJacobian),[],"all"));

    assert(all(storedJacobian(:,4:6) == 0,"all"), ...
        "Stored full Jacobian velocity columns are not identically zero.");
end

assert(maximumJacobianError < 1e-12, ...
    "Chunked Jacobians do not match the analytic RA/Dec Jacobian.");

%% Study metadata

expectedNetworkSizes = [3 5 7 10];
assert(isequal(double(database.study.networkSizes(:).'),expectedNetworkSizes), ...
    "Production database network-size metadata is inconsistent.");

objectiveModes = lower(string(database.study.objectiveModes));
assert(all(ismember(["information","coverage"],objectiveModes)), ...
    "Production database must support both information and coverage.");

%% Objective smoke test across chunk boundaries

representativeNetwork = zeros(6,1);
for chunkIndex = 1:6
    metadata = database.tracking.measurementJacobianChunks(chunkIndex);
    representativeNetwork(chunkIndex) = ...
        round((metadata.firstGlobalCandidateIndex + ...
        metadata.lastGlobalCandidateIndex)/2);
end

informationObjective = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"information");
coverageObjective = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"coverage");

assert(isfinite(informationObjective), ...
    "Chunked information objective is nonfinite.");
assert(isfinite(coverageObjective), ...
    "Chunked coverage objective is nonfinite.");

informationRepeat = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"information");

informationTolerance = 1e-12*max(1,abs(informationObjective));

assert(abs(informationRepeat-informationObjective) <= informationTolerance, ...
    "Chunked information objective is not deterministic.");

%% Storage summary

databaseInfo = dir(databaseFile);
databaseSizeGiB = double(databaseInfo.bytes)/1024^3;

actualChunkBytes = 0;
for chunkIndex = 1:6
    chunkInfo = dir(database.tracking.measurementJacobianChunks(chunkIndex).filePath);
    actualChunkBytes = actualChunkBytes + double(chunkInfo.bytes);
end

uncompressedJacobianGiB = ...
    (2*6*numberOfCandidates*expectedOptimizationEpochs*numberOfObjects*8) / ...
    1024^3;

fprintf("\n");
fprintf("Production optimization database validation\n");
fprintf("-------------------------------------------\n");
fprintf("Candidate domain:          -90 to 0 deg latitude\n");
fprintf("Grid spacing:              %.1f km\n",expectedSpacingKm);
fprintf("Initial candidates:        %d\n",expectedInitialCandidates);
fprintf("Retained candidates:       %d\n",numberOfCandidates);
fprintf("Chunk count:               %d\n",numel(chunkCounts));
fprintf("Chunk sizes:               ");
fprintf("%d ",chunkCounts);
fprintf("\n");
fprintf("Tracking horizon:          %.1f hr\n",expectedFinalTimeSeconds/3600);
fprintf("Tracking cadence:          %.1f min\n",expectedTrackingStepSeconds/60);
fprintf("Optimization epochs:       %d\n",expectedOptimizationEpochs);
fprintf("RSO population:            %d\n",numberOfObjects);
fprintf("Stored Jacobian shape:     2 x 6 x NcChunk x Nt x Nobj\n");
fprintf("Uncompressed Jacobians:    %.2f GiB\n",uncompressedJacobianGiB);
fprintf("Chunk files on disk:       %.2f GiB\n",actualChunkBytes/1024^3);
fprintf("Core MAT-file size:        %.2f GiB\n",databaseSizeGiB);
fprintf("Max Jacobian error:        %.3e\n",maximumJacobianError);
fprintf("Information objective:     %.8f\n",informationObjective);
fprintf("Coverage objective:        %.0f\n",coverageObjective);
fprintf("Southern domain:           passed\n");
fprintf("Equal-count chunks:        passed\n");
fprintf("Global/local index map:    passed\n");
fprintf("Partial MAT-file lookup:   passed\n");
fprintf("Analytic Jacobian check:   passed\n");
fprintf("Objective determinism:     passed\n");
fprintf("\n");
fprintf("testProductionOptimizationDatabase passed.\n");

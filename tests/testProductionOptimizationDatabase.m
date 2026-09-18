%% testProductionOptimizationDatabase
% Post-build validation of the chunked production optimization database.
%
% Run immediately after scripts/buildProductionOptimizationDatabase.m and
% before the 12000-FE production campaign. This verifies that candidate
% chunking begins at terrain generation and remains consistent through final
% visibility/Jacobian storage and objective partial indexing.

clear;
close all;
clc;

%% Paths

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
dataDirectory = fullfile(projectRoot,"data");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
assert(isfile(databaseFile), ...
    ["Production optimization database was not found. " ...
     "Run scripts/buildProductionOptimizationDatabase.m first.\n%s"], ...
    databaseFile);

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
database = databaseData.database;

%% Study definition

moonRadiusKm = 1737.4;
expectedLatitudeBandRad = deg2rad([-90,0]);
expectedLongitudeBandRad = deg2rad([0,360]);
expectedSpacingKm = 15;
expectedTrackingStepSeconds = 600;
expectedFinalTimeSeconds = 3*24*3600;
expectedOptimizationEpochs = 432;
expectedNumberOfObjects = 20;
expectedNumberOfChunks = 6;

[expectedLatitudes,expectedLongitudes] = ...
    digitalElevationModel.buildCandidateSensorGrid( ...
        expectedLatitudeBandRad, ...
        expectedLongitudeBandRad, ...
        expectedSpacingKm, ...
        moonRadiusKm);

expectedInitialCandidates = numel(expectedLatitudes);
assert(expectedInitialCandidates == 84794, ...
    "Expected southern-hemisphere candidate count changed.");

assert(database.meta.numberOfCandidatesBeforeFiltering == ...
    expectedInitialCandidates, ...
    "Initial candidate count is inconsistent.");
assert(database.meta.numberOfObjects == expectedNumberOfObjects, ...
    "Production database must contain 20 RSOs.");
assert(database.meta.numberOfOptimizationEpochs == ...
    expectedOptimizationEpochs, ...
    "Production database must contain 432 optimization epochs.");

assert(max(abs(database.config.candidates.latitudeBandRad(:) - ...
    expectedLatitudeBandRad(:))) < 1e-12);
assert(max(abs(database.config.candidates.longitudeBandRad(:) - ...
    expectedLongitudeBandRad(:))) < 1e-12);
assert(abs(database.config.candidates.spacingKm-expectedSpacingKm) < 1e-12);
assert(database.config.tracking.outputStepSeconds == ...
    expectedTrackingStepSeconds);
assert(database.config.tracking.finalTimeSeconds == ...
    expectedFinalTimeSeconds);

trackingTimes = database.tracking.times(:);
assert(numel(trackingTimes) == expectedOptimizationEpochs);
assert(abs(trackingTimes(1)-expectedTrackingStepSeconds) < 1e-9);
assert(abs(trackingTimes(end)-expectedFinalTimeSeconds) < 1e-9);
assert(all(abs(diff(trackingTimes)-expectedTrackingStepSeconds) < 1e-9));

%% Chunked storage metadata

assert(string(database.meta.measurementJacobianStorage) == ...
    "chunked_full_state", ...
    "Production Jacobians are not stored as chunked full-state arrays.");
assert(string(database.meta.visibilityStorage) == ...
    "chunked_filtered_availability", ...
    "Production visibility is not stored in candidate chunks.");
assert(string(database.meta.terrainStorage) == ...
    "chunked_horizons", ...
    "Production terrain horizons are not stored in candidate chunks.");
assert(database.meta.measurementJacobianStateColumns == 6);
assert(database.meta.numberOfMeasurementJacobianChunks == ...
    expectedNumberOfChunks);

assert(isempty(database.tracking.measurementJacobianHistories), ...
    "Core database must not contain a monolithic Jacobian array.");
assert(isempty(database.visibility.filteredAvailability), ...
    "Core database must not contain monolithic filtered availability.");
assert(isempty(database.terrain.maximumTerrainElevationRad), ...
    "Core database must not contain monolithic terrain horizons.");

chunkMetadata = database.tracking.measurementJacobianChunks;
assert(numel(chunkMetadata) == expectedNumberOfChunks);
assert(numel(database.visibility.candidateChunks) == expectedNumberOfChunks);
assert(numel(database.terrain.candidateChunks) == expectedNumberOfChunks);

originalChunkCounts = [chunkMetadata.numberOfOriginalCandidates].';
assert(sum(originalChunkCounts) == expectedInitialCandidates);
assert(max(originalChunkCounts)-min(originalChunkCounts) <= 1, ...
    "Initial candidate chunks are not equal-sized to within one candidate.");

%% Retained candidate maps

numberOfCandidates = database.meta.numberOfCandidates;
assert(numberOfCandidates >= 10);
assert(numel(database.candidates.chunkIndex) == numberOfCandidates);
assert(numel(database.candidates.chunkLocalIndex) == numberOfCandidates);
assert(numel(database.candidates.originalChunkLocalIndex) == numberOfCandidates);

assert(all(database.candidates.chunkIndex >= 1 & ...
    database.candidates.chunkIndex <= expectedNumberOfChunks));
assert(all(database.candidates.chunkLocalIndex >= 1));
assert(all(database.candidates.originalChunkLocalIndex >= 1));

assert(numel(database.candidates.prefilter.keepMask) == ...
    expectedInitialCandidates);
assert(size(database.candidates.prefilter.geometricCountsByObject,1) == ...
    expectedInitialCandidates);
assert(size(database.candidates.prefilter.filteredCountsByObject,1) == ...
    expectedInitialCandidates);

%% Validate every chunk without loading full arrays

reconstructedOriginalIndices = zeros(0,1);
reconstructedRetainedIndices = zeros(0,1);
actualChunkBytes = 0;

for chunkIndex = 1:expectedNumberOfChunks
    metadata = chunkMetadata(chunkIndex);
    chunkFile = string(metadata.filePath);

    assert(isfile(chunkFile), ...
        "Candidate chunk file was not found: %s",chunkFile);

    fileInfo = dir(chunkFile);
    actualChunkBytes = actualChunkBytes + double(fileInfo.bytes);

    chunkMat = matfile(chunkFile);

    originalIndices = double(chunkMat.originalCandidateIndices(:));
    expectedOriginalIndices = ...
        (metadata.firstOriginalCandidateIndex: ...
         metadata.lastOriginalCandidateIndex).';

    assert(isequal(originalIndices,expectedOriginalIndices), ...
        "Chunk %d original candidate indices are inconsistent.",chunkIndex);
    assert(numel(originalIndices) == metadata.numberOfOriginalCandidates);

    terrainSize = size(chunkMat,'maximumTerrainElevationRad');
    assert(terrainSize(1) == metadata.numberOfOriginalCandidates);
    assert(terrainSize(2) == numel(database.terrain.horizonAzimuthsRad));

    retainedGlobal = double(chunkMat.retainedGlobalCandidateIndices(:));
    retainedOriginal = double(chunkMat.retainedOriginalCandidateIndices(:));

    assert(numel(retainedGlobal) == metadata.numberOfRetainedCandidates);
    assert(numel(retainedOriginal) == metadata.numberOfRetainedCandidates);

    if metadata.numberOfRetainedCandidates > 0
        expectedRetainedGlobal = find( ...
            double(database.candidates.chunkIndex) == chunkIndex);

        assert(isequal(retainedGlobal,expectedRetainedGlobal), ...
            "Chunk %d retained global-index list is inconsistent.",chunkIndex);

        assert(isequal( ...
            double(database.candidates.chunkLocalIndex(retainedGlobal)), ...
            (1:numel(retainedGlobal)).'), ...
            "Chunk %d retained-local map is inconsistent.",chunkIndex);

        expectedOriginalLocal = ...
            retainedOriginal-metadata.firstOriginalCandidateIndex+1;

        assert(isequal( ...
            double(database.candidates.originalChunkLocalIndex(retainedGlobal)), ...
            expectedOriginalLocal), ...
            "Chunk %d original-local map is inconsistent.",chunkIndex);

        availabilitySize = size(chunkMat,'filteredAvailability');
        assert(isequal(availabilitySize, ...
            [metadata.numberOfRetainedCandidates, ...
             expectedOptimizationEpochs,expectedNumberOfObjects]), ...
            "Chunk %d filtered-availability dimensions are inconsistent.", ...
            chunkIndex);

        jacobianSize = size(chunkMat,'measurementJacobianHistories');
        assert(isequal(jacobianSize, ...
            [2,6,metadata.numberOfRetainedCandidates, ...
             expectedOptimizationEpochs,expectedNumberOfObjects]), ...
            "Chunk %d Jacobian dimensions are inconsistent.",chunkIndex);
    end

    reconstructedOriginalIndices = [ ...
        reconstructedOriginalIndices
        originalIndices]; %#ok<AGROW>

    reconstructedRetainedIndices = [ ...
        reconstructedRetainedIndices
        retainedGlobal]; %#ok<AGROW>
end

assert(isequal(reconstructedOriginalIndices, ...
    (1:expectedInitialCandidates).'), ...
    "Original candidate chunks contain gaps or duplicates.");

assert(isequal(reconstructedRetainedIndices, ...
    (1:numberOfCandidates).'), ...
    "Retained candidate chunks contain gaps or duplicates.");

%% Partial-index retrieval and analytic Jacobian verification

syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
assert(isfile(syntheticDemFile), ...
    "Synthetic DEM was not found: %s",syntheticDemFile);

[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(syntheticDemFile),moonRadiusKm,24,48);

sampleCandidates = unique(round(linspace(1,numberOfCandidates,3))).';
sampleTimes = unique(round(linspace(1,expectedOptimizationEpochs,3))).';
sampleObjects = unique(round(linspace(1,expectedNumberOfObjects,3))).';

sampleJacobians = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"measurementJacobianHistories");
sampleAvailability = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"filteredAvailability");
sampleHorizons = optimization.loadChunkedCandidateData( ...
    database,sampleCandidates,"maximumTerrainElevationRad");

assert(isequal(size(sampleJacobians), ...
    [2,6,numel(sampleCandidates), ...
     expectedOptimizationEpochs,expectedNumberOfObjects]));
assert(isequal(size(sampleAvailability), ...
    [numel(sampleCandidates), ...
     expectedOptimizationEpochs,expectedNumberOfObjects]));
assert(size(sampleHorizons,1) == numel(sampleCandidates));

moonAngularRate = ...
    2*pi/double(database.config.moon.siderealPeriodSeconds);
theta0Rad = double(database.config.moon.theta0Rad);

maximumJacobianError = 0;

for sampleIndex = 1:min([ ...
        numel(sampleCandidates),numel(sampleTimes),numel(sampleObjects)])

    candidateIndex = sampleCandidates(sampleIndex);
    timeIndex = sampleTimes(sampleIndex);
    objectIndex = sampleObjects(sampleIndex);

    analyticJacobian = measurements.surfaceRaDecJacobian( ...
        database.tracking.referenceStateHistories(:,timeIndex,objectIndex), ...
        database.tracking.times(timeIndex), ...
        database.candidates.latitudesRad(candidateIndex), ...
        database.candidates.longitudesRad(candidateIndex), ...
        dem, ...
        moonRadiusKm, ...
        theta0Rad, ...
        moonAngularRate);

    storedJacobian = ...
        sampleJacobians(:,:,sampleIndex,timeIndex,objectIndex);

    maximumJacobianError = max( ...
        maximumJacobianError, ...
        max(abs(storedJacobian-analyticJacobian),[],"all"));

    assert(all(storedJacobian(:,4:6) == 0,"all"), ...
        "Stored direct-velocity Jacobian columns are not zero.");
end

assert(maximumJacobianError < 1e-12, ...
    "Chunked Jacobians do not match the analytic measurement model.");

%% Objective lookup across chunk boundaries

representativeNetwork = zeros(expectedNumberOfChunks,1);

for chunkIndex = 1:expectedNumberOfChunks
    candidatesInChunk = find( ...
        double(database.candidates.chunkIndex) == chunkIndex);

    assert(~isempty(candidatesInChunk), ...
        "Chunk %d retained no candidates.",chunkIndex);

    representativeNetwork(chunkIndex) = ...
        candidatesInChunk(round((numel(candidatesInChunk)+1)/2));
end

informationObjective = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"information");
coverageObjective = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"coverage");

assert(isfinite(informationObjective));
assert(isfinite(coverageObjective));

informationRepeat = optimization.networkObjective( ...
    representativeNetwork(1:3),database,"information");

informationTolerance = 1e-12*max(1,abs(informationObjective));
assert(abs(informationRepeat-informationObjective) <= ...
    informationTolerance, ...
    "Chunked information objective is not deterministic.");

%% Summary

databaseInfo = dir(databaseFile);
databaseSizeGiB = double(databaseInfo.bytes)/1024^3;
uncompressedJacobianGiB = ...
    2*6*numberOfCandidates*expectedOptimizationEpochs* ...
    expectedNumberOfObjects*8/1024^3;

fprintf("\n");
fprintf("Production optimization database validation\n");
fprintf("-------------------------------------------\n");
fprintf("Initial candidates:        %d\n",expectedInitialCandidates);
fprintf("Retained candidates:       %d\n",numberOfCandidates);
fprintf("Initial chunk sizes:       ");
fprintf("%d ",originalChunkCounts);
fprintf("\n");
fprintf("Retained chunk sizes:      ");
fprintf("%d ",[chunkMetadata.numberOfRetainedCandidates]);
fprintf("\n");
fprintf("Optimization epochs:       %d\n",expectedOptimizationEpochs);
fprintf("RSO population:            %d\n",expectedNumberOfObjects);
fprintf("Uncompressed Jacobians:    %.2f GiB\n",uncompressedJacobianGiB);
fprintf("Chunk files on disk:       %.2f GiB\n",actualChunkBytes/1024^3);
fprintf("Core MAT-file size:        %.2f GiB\n",databaseSizeGiB);
fprintf("Max Jacobian error:        %.3e\n",maximumJacobianError);
fprintf("Information objective:     %.8f\n",informationObjective);
fprintf("Coverage objective:        %.0f\n",coverageObjective);
fprintf("Terrain chunking:          passed\n");
fprintf("Truth-visibility chunking: passed\n");
fprintf("Final visibility chunking: passed\n");
fprintf("Full 2x6 Jacobian chunks:  passed\n");
fprintf("Global/local index maps:   passed\n");
fprintf("Partial MAT-file lookup:   passed\n");
fprintf("Objective determinism:     passed\n");
fprintf("\n");
fprintf("testProductionOptimizationDatabase passed.\n");

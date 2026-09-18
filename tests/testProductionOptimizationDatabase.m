%% testProductionOptimizationDatabase
% Post-build validation of the production optimization database.
%
% Run immediately after scripts/buildProductionOptimizationDatabase.m and
% before starting the 12000-FE production campaign. This validates:
%   - full southern-hemisphere 15-km candidate grid;
%   - six equal-count ORIGINAL candidate chunks created from the start;
%   - terrain, visibility, and full 2x6 Jacobians stored by chunk;
%   - retained global candidate -> chunk/local index mapping;
%   - MATFILE partial indexing for visibility, terrain, and Jacobians;
%   - analytic Jacobian agreement;
%   - deterministic information/coverage objective evaluation.

% Do not clear the caller workspace; this test is also run by the post-build wrapper.

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

%% Core database must be lean

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

assert(numberOfCandidates >= 10 && numberOfCandidates <= expectedInitialCandidates, ...
    "Retained candidate count is invalid.");

assert(string(database.meta.version) == ...
    "lunar_surface_optimization_database_v5_chunked_candidate_data", ...
    "Production database version is not the early-chunked architecture.");

assert(string(database.meta.measurementJacobianStorage) == ...
    "chunked_full_state", ...
    "Production database does not use chunked full-state Jacobians.");

assert(string(database.meta.visibilityStorage) == ...
    "chunked_filtered_availability", ...
    "Production visibility is not stored in candidate chunks.");

assert(string(database.meta.terrainStorage) == ...
    "chunked_horizons", ...
    "Production terrain is not stored in candidate chunks.");

assert(database.meta.measurementJacobianStateColumns == 6, ...
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
assert(numel(chunks) == 6, ...
    "Production database must contain six candidate chunks.");
assert(numel(database.visibility.candidateChunks) == 6, ...
    "Visibility chunk metadata are missing.");
assert(numel(database.terrain.candidateChunks) == 6, ...
    "Terrain chunk metadata are missing.");

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

    assert(isfile(chunkFile), ...
        "Candidate chunk file was not found: %s",chunkFile);

    chunkMat = matfile(chunkFile);

    originalIndices = double(chunkMat.originalCandidateIndices(:));
    assert(numel(originalIndices) == metadata.numberOfOriginalCandidates, ...
        "Chunk %d original index count is inconsistent.",chunkIndex);
    assert(originalIndices(1) == metadata.firstOriginalCandidateIndex && ...
        originalIndices(end) == metadata.lastOriginalCandidateIndex, ...
        "Chunk %d original index bounds are inconsistent.",chunkIndex);

    reconstructedOriginalIndices = [ ...
        reconstructedOriginalIndices
        originalIndices]; %#ok<AGROW>

    terrainSize = size(chunkMat,'maximumTerrainElevationRad');
    assert(terrainSize(1) == metadata.numberOfOriginalCandidates, ...
        "Chunk %d terrain candidate dimension is inconsistent.",chunkIndex);
    assert(terrainSize(2) == numel(database.terrain.horizonAzimuthsRad), ...
        "Chunk %d terrain azimuth dimension is inconsistent.",chunkIndex);

    retainedGlobal = double(chunkMat.retainedGlobalCandidateIndices(:));
    retainedOriginal = double(chunkMat.retainedOriginalCandidateIndices(:));

    assert(numel(retainedGlobal) == metadata.numberOfRetainedCandidates, ...
        "Chunk %d retained global index count is inconsistent.",chunkIndex);
    assert(numel(retainedOriginal) == metadata.numberOfRetainedCandidates, ...
        "Chunk %d retained original index count is inconsistent.",chunkIndex);

    if metadata.numberOfRetainedCandidates > 0
        assert(all(diff(retainedGlobal) == 1), ...
            "Chunk %d retained global indices are not contiguous.",chunkIndex);

        visibilitySize = size(chunkMat,'filteredAvailability');
        assert(visibilitySize(1) == metadata.numberOfRetainedCandidates && ...
            visibilitySize(2) == expectedOptimizationEpochs && ...
            visibilitySize(3) == numberOfObjects, ...
            "Chunk %d final visibility dimensions are inconsistent.",chunkIndex);

        jacobianSize = size(chunkMat,'measurementJacobianHistories');
        assert(numel(jacobianSize) == 5 && ...
            jacobianSize(1) == 2 && ...
            jacobianSize(2) == 6 && ...
            jacobianSize(3) == metadata.numberOfRetainedCandidates && ...
            jacobianSize(4) == expectedOptimizationEpochs && ...
            jacobianSize(5) == numberOfObjects, ...
            "Chunk %d Jacobian dimensions are inconsistent.",chunkIndex);

        mappedChunk = double(database.candidates.chunkIndex(retainedGlobal));
        mappedLocal = double(database.candidates.chunkLocalIndex(retainedGlobal));
        mappedOriginalLocal = ...
            double(database.candidates.originalChunkLocalIndex(retainedGlobal));

        assert(all(mappedChunk == chunkIndex), ...
            "Global-to-chunk map is incorrect for chunk %d.",chunkIndex);
        assert(isequal(mappedLocal(:), ...
            (1:metadata.numberOfRetainedCandidates).'), ...
            "Retained local-index map is incorrect for chunk %d.",chunkIndex);

        expectedOriginalLocal = ...
            retainedOriginal-metadata.firstOriginalCandidateIndex+1;
        assert(isequal(mappedOriginalLocal(:),expectedOriginalLocal(:)), ...
            "Original local-index map is incorrect for chunk %d.",chunkIndex);
    end

    reconstructedRetainedGlobalIndices = [ ...
        reconstructedRetainedGlobalIndices
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
assert(isfile(syntheticDemFile), ...
    "Synthetic DEM was not found: %s",syntheticDemFile);

[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(syntheticDemFile),moonRadiusKm,24,48);

sampleTimes = unique(round(linspace(1,expectedOptimizationEpochs,3))).';
sampleObjects = unique(round(linspace(1,numberOfObjects,3))).';

moonAngularRate = ...
    2*pi/double(database.config.moon.siderealPeriodSeconds);
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

%% Objective smoke test across chunk boundaries

representativeNetwork = zeros(6,1);

for chunkIndex = 1:6
    chunkGlobals = find(double(database.candidates.chunkIndex) == chunkIndex);

    if isempty(chunkGlobals)
        representativeNetwork(chunkIndex) = NaN;
    else
        representativeNetwork(chunkIndex) = ...
            chunkGlobals(round((numel(chunkGlobals)+1)/2));
    end
end

representativeNetwork = representativeNetwork(isfinite(representativeNetwork));
assert(numel(representativeNetwork) >= 3, ...
    "Fewer than three retained chunks are available for the objective smoke test.");

testNetwork = representativeNetwork(1:3);

informationObjective = optimization.networkObjective( ...
    testNetwork,database,"information");
coverageObjective = optimization.networkObjective( ...
    testNetwork,database,"coverage");

assert(isfinite(informationObjective), ...
    "Chunked information objective is nonfinite.");
assert(isfinite(coverageObjective), ...
    "Chunked coverage objective is nonfinite.");

informationRepeat = optimization.networkObjective( ...
    testNetwork,database,"information");
informationTolerance = 1e-12*max(1,abs(informationObjective));

assert(abs(informationRepeat-informationObjective) <= informationTolerance, ...
    "Chunked information objective is not deterministic.");

%% Storage summary

databaseInfo = dir(databaseFile);
databaseSizeGiB = double(databaseInfo.bytes)/1024^3;

actualChunkBytes = 0;
for chunkIndex = 1:6
    chunkInfo = dir(chunks(chunkIndex).filePath);
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
fprintf("Original chunk sizes:      ");
fprintf("%d ",originalChunkCounts);
fprintf("\n");
fprintf("Retained chunk sizes:      ");
fprintf("%d ",retainedChunkCounts);
fprintf("\n");
fprintf("Tracking horizon:          %.1f hr\n",expectedFinalTimeSeconds/3600);
fprintf("Tracking cadence:          %.1f min\n",expectedTrackingStepSeconds/60);
fprintf("Optimization epochs:       %d\n",expectedOptimizationEpochs);
fprintf("RSO population:            %d\n",numberOfObjects);
fprintf("Chunked products:          terrain, visibility, full 2x6 Jacobians\n");
fprintf("Uncompressed Jacobians:    %.2f GiB\n",uncompressedJacobianGiB);
fprintf("Chunk files on disk:       %.2f GiB\n",actualChunkBytes/1024^3);
fprintf("Core MAT-file size:        %.2f GiB\n",databaseSizeGiB);
fprintf("Max Jacobian error:        %.3e\n",maximumJacobianError);
fprintf("Information objective:     %.8f\n",informationObjective);
fprintf("Coverage objective:        %.0f\n",coverageObjective);
fprintf("Early equal-count chunks:  passed\n");
fprintf("Global/local index maps:   passed\n");
fprintf("Terrain partial lookup:    passed\n");
fprintf("Visibility partial lookup: passed\n");
fprintf("Jacobian partial lookup:   passed\n");
fprintf("Analytic Jacobian check:   passed\n");
fprintf("Objective determinism:     passed\n");
fprintf("\n");
fprintf("testProductionOptimizationDatabase passed.\n");

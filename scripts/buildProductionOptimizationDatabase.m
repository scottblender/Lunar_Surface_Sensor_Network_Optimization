%% buildProductionOptimizationDatabase.m
% Build and save the production optimization database used for the
% lunar-surface sensor-network global optimization study.
%
% The production terrain input is the synthetic lunar DEM stored as a
% griddedInterpolant. The DEM loader also remains backward compatible with
% the previous numeric global raster representation.

clear;
close all;
clc;

%% ========================================================================
%  Project paths
%  ========================================================================

scriptDirectory = ...
    fileparts(mfilename("fullpath"));

projectRoot = ...
    fileparts(scriptDirectory);

sourceDirectory = ...
    fullfile(projectRoot,"src");

dataDirectory = ...
    fullfile(projectRoot,"data");

resultsDirectory = ...
    fullfile(projectRoot,"results");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

if ~isfolder(resultsDirectory)
    mkdir(resultsDirectory);
end

%% ========================================================================
%  Lunar reference constant
%  ========================================================================

moonRadiusKm = ...
    1737.4;

%% ========================================================================
%  Load production lunar DEM
%  ========================================================================

demPath = ...
    resolveProductionDemPath(dataDirectory);

[dem,demModel] = ...
    digitalElevationModel.loadTriaxialLunarDem( ...
        string(demPath), ...
        moonRadiusKm, ...
        24, ...
        48);

assert(isa(dem,"griddedInterpolant"), ...
    "Production DEM loader did not return a griddedInterpolant.");

fprintf("\n");
fprintf("Production lunar DEM loaded.\n");
fprintf("Source: %s\n",demPath);
fprintf("Representation: %s\n",demModel.workflowRepresentation);
fprintf("Grid: %d x %d\n", ...
    demModel.rawRasterSize(1), ...
    demModel.rawRasterSize(2));

if isfield(demModel,"semiAxesKm")
    fprintf("Fitted triaxial center [km]: [% .6f % .6f % .6f]\n", ...
        demModel.centerOffsetKm(1), ...
        demModel.centerOffsetKm(2), ...
        demModel.centerOffsetKm(3));
    fprintf("Fitted semi-axes [km]:       [%.6f %.6f %.6f]\n", ...
        demModel.semiAxesKm(1), ...
        demModel.semiAxesKm(2), ...
        demModel.semiAxesKm(3));
    fprintf("Residual height RMS: %.6f km\n", ...
        demModel.residualHeightRmsKm);
else
    fprintf("Elevation range: [%.6f, %.6f] km\n", ...
        demModel.rawMinimumElevationKm, ...
        demModel.rawMaximumElevationKm);
end

%% ========================================================================
%  Production study configuration
%  ========================================================================

config = struct();

%% Output

config.outputFile = ...
    fullfile( ...
        resultsDirectory, ...
        "optimization_database.mat");

config.overwriteOutput = ...
    false;

config.demSource = ...
    string(demPath);

config.demModel = ...
    demModel;

%% Study cases
% These are current study cases only; the database/objective layer supports
% other positive network sizes without rebuilding the physical database.

config.study.networkSizes = ...
    [3,5,7,10];

config.study.objectiveModes = ...
    ["information","coverage"];

%% Lunar constants

config.moon.radiusKm = ...
    moonRadiusKm;

config.moon.muKm3S2 = ...
    4902.800066;

config.moon.siderealPeriodSeconds = ...
    27.321661*86400;

config.moon.theta0Rad = ...
    0;

%% 20-object representative RSO population

config.rso.selection = ...
    "generated";

config.rso.numberOfGeneratedObjects = ...
    20;

config.rso.periapsisAltitudeLimitsKm = ...
    [50,5000];

config.rso.inclinationLimitsRad = ...
    deg2rad([0,180]);

config.rso.eccentricityLimits = ...
    [0,0.8];

%% Southern-hemisphere candidate network

config.candidates.latitudeBandRad = ...
    deg2rad([-90,0]);

config.candidates.longitudeBandRad = ...
    deg2rad([0,360]);

config.candidates.spacingKm = ...
    15;

%% Equal-count candidate chunks
% Partition the complete southern-hemisphere candidate list immediately after
% grid generation. Terrain horizons, truth visibility, final visibility, and
% full 2x6 RA/Dec Jacobians are then built and stored chunk-by-chunk. Objective
% evaluations use MATFILE partial indexing through the global -> chunk/local
% index map.

config.chunking.enabled = ...
    true;

config.chunking.numberOfChunks = ...
    6;

config.chunking.useParallel = ...
    true;

config.chunking.maximumParallelWorkers = ...
    2;

% Reuse completed candidate chunks after an interrupted/late-stage build.
% Existing chunks are validated before reuse; inconsistent/incomplete chunks
% are recomputed rather than silently accepted.
config.chunking.resumeExisting = ...
    true;

config.chunking.directoryName = ...
    "optimization_database_chunks";

%% Candidate preprocessing

config.candidateFilter.enabled = ...
    true;

% Remove only sites having no useful geometric opportunity. Do not impose
% a strong pre-optimization visibility design requirement.
config.candidateFilter.minimumGeometricEpochsForAnyObject = ...
    1;

config.candidateFilter.minimumFilteredEpochsTotal = ...
    1;

%% Terrain screening

config.terrain.maximumRangeKm = ...
    100;

config.terrain.rangeStepKm = ...
    0.5;

config.terrain.horizonAzimuthStepRad = ...
    deg2rad(0.1);

config.terrain.horizonMarginRad = ...
    0;

%% Celestial / geometric visibility

config.visibility.minimumElevationRad = ...
    deg2rad(0);

% Legacy shared value retained for backward compatibility in generic calls.
config.visibility.minimumAngularSeparationRad = ...
    deg2rad(20);

% Production study bright-body keep-out angles.
config.visibility.earthMinimumAngularSeparationRad = ...
    deg2rad(10);

config.visibility.sunMinimumAngularSeparationRad = ...
    deg2rad(20);

config.visibility.earthRadiusKm = ...
    6378.1366;

config.visibility.sunRadiusKm = ...
    695700;

%% Generic-time Earth and Sun geometry

config.ephemeris.earthMoonDistanceKm = ...
    384400;

config.ephemeris.sunMoonDistanceKm = ...
    149597870.7;

config.ephemeris.earthPhase0Rad = ...
    deg2rad(20);

config.ephemeris.sunPhase0Rad = ...
    deg2rad(145);

config.ephemeris.solarInclinationRad = ...
    deg2rad(5.145);

config.ephemeris.sunOrbitalPeriodSeconds = ...
    365.256363004*86400;

%% Tracking arc
% Three-day surveillance arc with one measurement opportunity every
% 10 minutes. The optimization database excludes the t = 0 reference epoch,
% leaving exactly 432 measurement/update epochs.

config.tracking.outputStepSeconds = ...
    10*60;

config.tracking.finalTimeSeconds = ...
    3*24*3600;

%% Angles-only sensor noise

config.measurement.rightAscensionSigmaRad = ...
    deg2rad(1/3600);

config.measurement.declinationSigmaRad = ...
    deg2rad(1/3600);

%% Fixed-P0 angles-only IOD calibration
% This reference acquisition is independent of the optimized candidate
% network. It is used once to estimate one fixed P0 that is then applied
% identically to every RSO and every network evaluation.

config.iod.referencePeriapsisAltitudeKm = ...
    50;

config.iod.referenceEccentricity = ...
    0;

config.iod.referenceInclinationRad = ...
    deg2rad(90);

config.iod.referenceRaanRad = ...
    deg2rad(37);

config.iod.referenceArgumentOfPeriapsisRad = ...
    0;

config.iod.referenceTrueAnomalyRad = ...
    0;

config.iod.referenceSensorLatitudeRad = ...
    deg2rad(-89.505332);

config.iod.referenceSensorLongitudeRad = ...
    deg2rad(102.857143);

config.iod.outputStepSeconds = ...
    10;

config.iod.desiredObservationCount = ...
    15;

config.iod.searchEndFraction = ...
    0.40;

config.iod.numberOfMonteCarloSamples = ...
    500;

config.iod.measurementNoiseSeedBase = ...
    1000;

config.iod.monteCarloSeedBase = ...
    2000;

%% EKF / covariance propagation

config.estimation.accelerationNoiseIntensity = ...
    1e-15;

config.estimation.stateScales = ...
    [ ...
    1
    1
    1
    1e-3
    1e-3
    1e-3
    ];

config.estimation.objectWeights = ...
    ones(20,1);

%% Objective

config.objective.infeasiblePenalty = ...
    1e12;

%% ========================================================================
%  Prevent accidental overwrite
%  ========================================================================

outputExistsMessage = ...
    "Optimization database already exists:\n%s\n" + ...
    "Archive, delete, or rename it before rebuilding with the new DEM.";

assert(~isfile(config.outputFile), ...
    outputExistsMessage, ...
    config.outputFile);

chunkDirectory = fullfile( ...
    resultsDirectory, ...
    string(config.chunking.directoryName));

if isfolder(chunkDirectory)
    existingChunkFiles = dir(fullfile(chunkDirectory,"*.mat"));

    if ~isempty(existingChunkFiles)
        if config.chunking.resumeExisting
            fprintf( ...
                "Found %d existing chunk files; completed stages will be validated and reused.\n", ...
                numel(existingChunkFiles));
        else
            error( ...
                ["Existing candidate chunk files were found in:\n%s\n" ...
                 "Archive or delete the old chunk directory before rebuilding."], ...
                chunkDirectory);
        end
    end
end

%% ========================================================================
%  Build database
%  ========================================================================

database = ...
    optimization.buildOptimizationDatabase( ...
        dem, ...
        config);

%% ========================================================================
%  Production timing checks
%  ========================================================================

assert(mod( ...
    config.tracking.finalTimeSeconds, ...
    config.tracking.outputStepSeconds) == 0, ...
    "Production tracking horizon must contain an integer number of updates.");

expectedOptimizationEpochs = ...
    config.tracking.finalTimeSeconds / ...
    config.tracking.outputStepSeconds;

assert(expectedOptimizationEpochs == 432, ...
    "Production study must contain exactly 432 optimization epochs.");

assert(database.meta.numberOfOptimizationEpochs == ...
    expectedOptimizationEpochs, ...
    "Saved database contains the wrong number of optimization epochs.");

assert(numel(database.tracking.times) == expectedOptimizationEpochs, ...
    "Tracking-time vector contains the wrong number of epochs.");

assert(abs( ...
    database.tracking.times(1) - ...
    config.tracking.outputStepSeconds) < 1e-9, ...
    "First optimization epoch is not one tracking cadence after t = 0.");

assert(abs( ...
    database.tracking.times(end) - ...
    config.tracking.finalTimeSeconds) < 1e-9, ...
    "Final optimization epoch does not match the three-day horizon.");

assert(all(abs( ...
    diff(database.tracking.times) - ...
    config.tracking.outputStepSeconds) < 1e-9), ...
    "Optimization tracking cadence is not uniformly 600 seconds.");

%% ========================================================================
%  Summary
%  ========================================================================

fprintf("\n");
fprintf("Production database ready.\n");
fprintf("Output:\n  %s\n",config.outputFile);
fprintf("DEM source:\n  %s\n",config.demSource);
fprintf("Earth exclusion: %.1f deg\n", ...
    rad2deg(config.visibility.earthMinimumAngularSeparationRad));
fprintf("Sun exclusion:   %.1f deg\n", ...
    rad2deg(config.visibility.sunMinimumAngularSeparationRad));

if isfield(demModel,"semiAxesKm")
    fprintf("Fitted triaxial semi-axes [km]: %.6f %.6f %.6f\n", ...
        demModel.semiAxesKm(1), ...
        demModel.semiAxesKm(2), ...
        demModel.semiAxesKm(3));
end

fprintf("Network sizes: ");
fprintf("%d ",database.study.networkSizes);
fprintf("\n");

fprintf("Objectives: ");
fprintf("%s ",database.study.objectiveModes);
fprintf("\n");

fprintf("Tracking horizon: %.1f hr\n", ...
    config.tracking.finalTimeSeconds/3600);
fprintf("Tracking cadence: %.1f min\n", ...
    config.tracking.outputStepSeconds/60);
fprintf("Optimization epochs: %d\n", ...
    database.meta.numberOfOptimizationEpochs);

if config.chunking.enabled
    fprintf("Candidate storage: %d equal-count chunks from terrain onward\n", ...
        config.chunking.numberOfChunks);
    fprintf("Jacobian storage: full 2x6 within candidate chunks\n");
    fprintf("Chunk stages parallel: %d, up to %d active workers\n", ...
        config.chunking.useParallel, ...
        config.chunking.maximumParallelWorkers);
end

fprintf("IOD cadence: %.1f s\n", ...
    database.iod.calibration.outputStepSeconds);

fprintf("IOD observations: %d/%d\n", ...
    length(database.iod.calibration.acquisitionIndices), ...
    database.iod.calibration.desiredObservationCount);

fprintf("IOD MC convergence: %d/%d\n", ...
    database.iod.calibration.diagnostics.numberOfSuccessfulSamples, ...
    database.iod.calibration.diagnostics.numberOfRequestedSamples);

%% ========================================================================
%  Local helpers
%  ========================================================================

function demPath = resolveProductionDemPath(dataDirectory)

demPath = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
if isfile(demPath)
    return
end

error( ...
    "buildProductionOptimizationDatabase:DemNotFound", ...
    "Synthetic lunar DEM was not found: %s", ...
    demPath);

end

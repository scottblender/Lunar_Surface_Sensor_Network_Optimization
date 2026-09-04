%% buildProductionOptimizationDatabase.m
% Build and save the production optimization database used for the
% lunar-surface sensor-network global optimization study.
%
% The production terrain input is Final_Lunar_DEM.mat. The raw global
% radial-height raster is characterized with a translated triaxial
% ellipsoid fit before database construction. The workflow interpolant
% remains sphere-referenced because
%
%   R_Moon + H_current = r_ellipsoid + H_residual,
%
% so the existing surface-position and terrain geometry remain physically
% identical while the triaxial reference figure is stored in the database
% configuration for provenance and later analysis.

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
%  Load and characterize final global DEM
%  ========================================================================

demPath = ...
    fullfile( ...
        dataDirectory, ...
        "Final_Lunar_DEM.mat");

assert(isfile(demPath), ...
    "Final lunar DEM was not found:\n%s",demPath);

[dem,triaxialModel] = ...
    digitalElevationModel.loadTriaxialLunarDem( ...
        string(demPath), ...
        moonRadiusKm, ...
        24, ...
        48);

fprintf("\n");
fprintf("Final lunar DEM loaded.\n");
fprintf("Raster: %d x %d\n", ...
    triaxialModel.rawRasterSize(1), ...
    triaxialModel.rawRasterSize(2));
fprintf("Resolution: %.4f deg\n", ...
    triaxialModel.latitudeSpacingDeg);
fprintf("Fitted triaxial center [km]: [% .6f % .6f % .6f]\n", ...
    triaxialModel.centerOffsetKm(1), ...
    triaxialModel.centerOffsetKm(2), ...
    triaxialModel.centerOffsetKm(3));
fprintf("Fitted semi-axes [km]:       [%.6f %.6f %.6f]\n", ...
    triaxialModel.semiAxesKm(1), ...
    triaxialModel.semiAxesKm(2), ...
    triaxialModel.semiAxesKm(3));
fprintf("Residual height RMS: %.6f km\n", ...
    triaxialModel.residualHeightRmsKm);

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

% Preserve the fitted reference figure in the saved database metadata.
config.demModel = ...
    triaxialModel;

%% Study cases
% These are current study cases only; the database/objective layer supports
% other positive network sizes without rebuilding the physical database.

config.study.networkSizes = ...
    [3,5,7];

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

%% South-polar candidate network

config.candidates.latitudeBandRad = ...
    deg2rad([-90,-75]);

config.candidates.longitudeBandRad = ...
    deg2rad([0,360]);

config.candidates.spacingKm = ...
    15;

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

config.visibility.minimumAngularSeparationRad = ...
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

config.tracking.outputStepSeconds = ...
    60;

config.tracking.finalTimeSeconds = ...
    8*3600;

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

%% ========================================================================
%  Build database
%  ========================================================================

database = ...
    optimization.buildOptimizationDatabase( ...
        dem, ...
        config);

%% ========================================================================
%  Summary
%  ========================================================================

fprintf("\n");
fprintf("Production database ready.\n");
fprintf("Output:\n  %s\n",config.outputFile);
fprintf("DEM source:\n  %s\n",config.demSource);
fprintf("\n");

fprintf("Fitted triaxial semi-axes [km]: %.6f %.6f %.6f\n", ...
    triaxialModel.semiAxesKm(1), ...
    triaxialModel.semiAxesKm(2), ...
    triaxialModel.semiAxesKm(3));

fprintf("Network sizes: ");
fprintf("%d ",database.study.networkSizes);
fprintf("\n");

fprintf("Objectives: ");
fprintf("%s ",database.study.objectiveModes);
fprintf("\n");

fprintf("IOD cadence: %.1f s\n", ...
    database.iod.calibration.outputStepSeconds);

fprintf("IOD observations: %d/%d\n", ...
    length(database.iod.calibration.acquisitionIndices), ...
    database.iod.calibration.desiredObservationCount);

fprintf("IOD MC convergence: %d/%d\n", ...
    database.iod.calibration.diagnostics.numberOfSuccessfulSamples, ...
    database.iod.calibration.diagnostics.numberOfRequestedSamples);

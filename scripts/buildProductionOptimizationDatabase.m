%% buildProductionOptimizationDatabase.m
% Build and save the production optimization database used for the
% lunar-surface sensor-network global optimization study.
%
% The current study evaluates 3-, 5-, and 7-sensor networks, but the
% network-size list is purely configuration. Change config.study.networkSizes
% to evaluate any other positive network sizes supported by the candidate
% set; no objective-function changes are required.

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
%  Load DEM
%  ========================================================================

demPath = ...
    fullfile( ...
        dataDirectory, ...
        "new_lunar_interpolant_model.mat");

assert(isfile(demPath), ...
    "DEM file was not found:\n%s",demPath);

demData = ...
    load(demPath,"F");

assert(isfield(demData,"F"), ...
    "DEM file must contain a variable named F.");

sourceDem = ...
    demData.F;

latitudeGrid = ...
    deg2rad(sourceDem.GridVectors{1}(:));

longitudeGrid = ...
    deg2rad(sourceDem.GridVectors{2}(:));

elevationGrid = ...
    sourceDem.Values;

if longitudeGrid(end) < 2*pi

    longitudeGrid = [ ...
        longitudeGrid
        2*pi
    ];

    elevationGrid = [ ...
        elevationGrid, ...
        elevationGrid(:,1)
    ];
end

dem = ...
    griddedInterpolant( ...
        {latitudeGrid,longitudeGrid}, ...
        elevationGrid, ...
        "linear", ...
        "nearest");

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

%% Study cases
% Change only this vector to evaluate different network sizes later.

config.study.networkSizes = ...
    [3,5,7];

config.study.objectiveModes = ...
    ["information","coverage"];

%% Lunar constants

config.moon.radiusKm = ...
    1737.4;

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

config.candidateFilter.minimumGeometricEpochsForAnyObject = ...
    41;

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

% Use a finer cadence than the 60-s optimization arc so the short
% low-lunar-orbit acquisition pass contains the full requested sample set.
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

% Equal RSO weights.
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
    "Delete or rename it before rebuilding.";

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
fprintf("\n");

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

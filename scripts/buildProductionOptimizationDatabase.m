%% buildProductionOptimizationDatabase.m
% Build and save the production optimization database used for the
% lunar-surface sensor-network global optimization study.

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

%% Angles-only IOD

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

assert(~isfile(config.outputFile), ...
    [ ...
    "Optimization database already exists:\n%s\n" ...
    "Delete or rename it before rebuilding." ...
    ], ...
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
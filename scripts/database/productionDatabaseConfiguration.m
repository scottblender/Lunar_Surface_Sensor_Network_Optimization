function config = productionDatabaseConfiguration(demPath,demModel,resultsDirectory)
% PRODUCTIONDATABASECONFIGURATION - Shared production physics and database defaults.
% Paths and DEM metadata are supplied by the caller; no data are loaded here.

moonRadiusKm = 1737.4;

%% Production study configuration
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
% Network sizes are study settings; the physical database is reusable.

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
% Partition candidates before building terrain, visibility, and Jacobian chunks.

config.chunking.enabled = ...
    true;

config.chunking.numberOfChunks = ...
    6;

config.chunking.useParallel = ...
    true;

config.chunking.maximumParallelWorkers = ...
    2;

% Validate completed chunks before reuse; rebuild incomplete or inconsistent chunks.
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
% Use 432 updates over three days at 10-minute spacing, excluding t = 0.

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
% Calibrate one independent IOD prior and reuse its P0 for all networks and RSOs.

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

end

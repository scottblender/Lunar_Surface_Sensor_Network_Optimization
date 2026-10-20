function tests = testDemCompatibility
% TESTDEMCOMPATIBILITY - Verify full and reduced DEMs throughout the observation workflow.
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

function testFullResolutionDem(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");

%% Load new DEM
moonRadiusKm = 1737.4;
newDemPath = fullfile( dataDirectory, "Full_Resolution_DEM.mat");
assert(isfile(newDemPath), [ "Full_Resolution_DEM.mat was not found. Copy the new DEM to:\n%s" ], ...
    newDemPath);
fileVariables = whos("-file",newDemPath);
variableNames = string({fileVariables.name});
assert(any(variableNames == "DEM"), ...
    "Full_Resolution_DEM.mat must contain a numeric variable named DEM.");
rawData = load(newDemPath,"DEM");
rawDem = double(rawData.DEM);
[numberOfLatitudes,numberOfLongitudes] = size(rawDem);
assert(numberOfLongitudes == 2*numberOfLatitudes, "The new DEM is not a global 2:1 raster.");
assert(all(isfinite(rawDem),"all"), "The new DEM contains nonfinite elevations.");
latitudeSpacingDeg = 180/numberOfLatitudes;
longitudeSpacingDeg = 360/numberOfLongitudes;
assert(abs(latitudeSpacingDeg-longitudeSpacingDeg) < 1e-12, ...
    "The new DEM does not have equal angular sampling.");

%% Build workflow interpolant and fit reference ellipsoid
[dem,triaxialModel] = digitalElevationModel.loadTriaxialLunarDem( string(newDemPath), moonRadiusKm, ...
        24, 48);
assert(isa(dem,"griddedInterpolant"), "The DEM loader did not return a griddedInterpolant.");

%% Raster and orientation checks
assert(isequal( triaxialModel.rawRasterSize, [numberOfLatitudes,numberOfLongitudes]), ...
    "Stored raster metadata is inconsistent.");
assert(abs(triaxialModel.latitudeSpacingDeg-0.0625) < 1e-12, ...
    "Unexpected latitude resolution for Full_Resolution_DEM.mat.");
assert(abs(triaxialModel.longitudeSpacingDeg-0.0625) < 1e-12, ...
    "Unexpected longitude resolution for Full_Resolution_DEM.mat.");
assert(triaxialModel.rowOrder == "north_to_south", "The expected DEM row orientation changed.");

% The global minimum should lie in the southern far-side basin region.
% This is a useful orientation sanity check for this particular global DEM.
assert(triaxialModel.rawMinimumLatitudeDeg < -50, "DEM row orientation appears to be reversed.");
assert(triaxialModel.rawMinimumLongitudeDeg > 150 && triaxialModel.rawMinimumLongitudeDeg < 230, ...
    "DEM longitude orientation appears inconsistent with the expected map.");

%% Triaxial-fit checks
centerOffsetKm = triaxialModel.centerOffsetKm;
semiAxesKm = triaxialModel.semiAxesKm;
assert(all(isfinite(centerOffsetKm)) && all(isfinite(semiAxesKm)), ...
    "The triaxial fit contains nonfinite parameters.");
assert(all(abs(centerOffsetKm) < 5), "The fitted ellipsoid center offset is unexpectedly large.");
assert(all(semiAxesKm > 1730) && all(semiAxesKm < 1745), ...
    "The fitted lunar semi-axes are outside a physically plausible range.");
assert(triaxialModel.axisSpreadKm > 0.5, [ ...
    "The uploaded DEM does not contain a measurable triaxial figure. " ...
    "It may already be an ellipsoid-referenced residual DEM." ]);
assert(triaxialModel.axisSpreadKm < 10, "The fitted triaxial axis spread is implausibly large.");
assert(triaxialModel.residualHeightRmsKm < triaxialModel.rawHeightRmsKm, ...
    "Removing the fitted ellipsoid did not reduce global height RMS.");
assert(triaxialModel.maximumReconstructionErrorKm < 1e-10, ...
    "Ellipsoid + residual does not reconstruct the source DEM.");

%% Interpolant coverage and periodicity
latitudeGrid = dem.GridVectors{1}(:);
longitudeGrid = dem.GridVectors{2}(:);
assert(abs(latitudeGrid(1)+pi/2) < 1e-12 && abs(latitudeGrid(end)-pi/2) < 1e-12, ...
    "Workflow DEM does not include both poles.");
assert(abs(longitudeGrid(1)) < 1e-12 && abs(longitudeGrid(end)-2*pi) < 1e-12, ...
    "Workflow DEM does not include the periodic 0/360 seam.");
sampleLatitudes = deg2rad([ -89.505332
    -87.0
    -82.0
    -75.5
    ]);
sampleLongitudes = deg2rad([ 102.857143
    0
    180
    359.5
    ]);
sampleElevations = dem(sampleLatitudes,sampleLongitudes);
assert(all(isfinite(sampleElevations)), "The DEM returned nonfinite south-polar elevations.");

% Use column-vector query points so griddedInterpolant receives its native
% NDGRID-format pairwise queries without emitting a MESHGRID warning.
seamLatitudes = deg2rad([-89,-85,-80,-76]).';
seamZero = dem(seamLatitudes,zeros(size(seamLatitudes)));
seamTwoPi = dem(seamLatitudes,2*pi*ones(size(seamLatitudes)));
assert(max(abs(seamZero-seamTwoPi)) < 1e-12, "The DEM longitude seam is not periodic.");

%% Explicit ellipsoid/residual reconstruction at workflow sample points
ellipsoidRadiusKm = digitalElevationModel.triaxialEllipsoidRadius( sampleLatitudes, ...
        sampleLongitudes, triaxialModel.centerOffsetKm, triaxialModel.semiAxesKm);
ellipsoidHeightKm = ellipsoidRadiusKm - moonRadiusKm;
residualHeightKm = sampleElevations - ellipsoidHeightKm;
surfaceRadiusFromCurrentDemKm = moonRadiusKm + sampleElevations;
surfaceRadiusFromTriaxialDecompositionKm = ellipsoidRadiusKm + residualHeightKm;
assert(max(abs( surfaceRadiusFromCurrentDemKm - surfaceRadiusFromTriaxialDecompositionKm)) < 1e-10, ...
    "Triaxial residual decomposition changed the physical lunar radius.");

%% Topographic-frame compatibility
sensorLatitude = sampleLatitudes(1);
sensorLongitude = sampleLongitudes(1);
sensorRotatingState = referenceFrames.topographic( zeros(6,1), sensorLatitude, sensorLongitude, dem, ...
        moonRadiusKm, "toRotating");
expectedSensorRadiusKm = moonRadiusKm + dem(sensorLatitude,sensorLongitude);
assert(abs( norm(sensorRotatingState(1:3))- expectedSensorRadiusKm) < 1e-10, ...
    "Topographic sensor radius is inconsistent with the new DEM.");
[localState,localMeasurement] = referenceFrames.topographic( sensorRotatingState, sensorLatitude, ...
        sensorLongitude, dem, moonRadiusKm, "fromRotating");
assert(norm(localState) < 1e-10, "Topographic round-trip failed at the new DEM surface.");
assert(abs(localMeasurement(3)) < 1e-10, "Surface sensor did not return zero local range.");

%% Terrain-horizon compatibility
candidateLatitudes = sampleLatitudes;
candidateLongitudes = sampleLongitudes;
[horizonAzimuths,maximumTerrainElevation,maximumFeatureRange, ...
    sensorElevations,maximumFeatureElevations] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( candidateLatitudes, ...
        candidateLongitudes, dem, 100, 5, deg2rad(10), moonRadiusKm);
assert(all(isfinite(maximumTerrainElevation),"all"), ...
    "Terrain horizon contains nonfinite angles with the new DEM.");
assert(all(isfinite(maximumFeatureRange),"all"), "Terrain horizon contains nonfinite feature ranges.");
assert(all(isfinite(sensorElevations)), "Terrain horizon returned nonfinite sensor elevations.");
assert(all(isfinite(maximumFeatureElevations),"all"), ...
    "Terrain horizon returned nonfinite feature elevations.");
assert(max(abs( maximumTerrainElevation(:,1)- maximumTerrainElevation(:,end))) < 1e-12, ...
    "Terrain horizon is not periodic in azimuth.");
assert(abs(horizonAzimuths(1)) < 1e-12 && abs(horizonAzimuths(end)-2*pi) < 1e-12, ...
    "Terrain horizon azimuth grid is not periodic.");

%% RA/Dec model and Jacobian compatibility
time = 0;
theta0 = 0;
angularRate = 2*pi/(27.321661*86400);
sensorMciState = referenceFrames.moonRotating( sensorRotatingState, time, theta0, angularRate, ...
        "toInertial");
targetState = [ sensorMciState(1:3) + [120;80;150]
    0
    0
    0
];
measurement = measurements.surfaceRaDecMeasurement( targetState, time, sensorLatitude, ...
        sensorLongitude, dem, moonRadiusKm, theta0, angularRate);
measurementJacobian = measurements.surfaceRaDecJacobian( targetState, time, sensorLatitude, ...
        sensorLongitude, dem, moonRadiusKm, theta0, angularRate);
assert(all(isfinite(measurement)), "RA/Dec measurement is nonfinite with the new DEM.");
assert(all(isfinite(measurementJacobian),"all"), "RA/Dec Jacobian is nonfinite with the new DEM.");
end

function testReducedDem(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");

%% Resolve and load synthetic DEM
moonRadiusKm = 1737.4;
moonMuKm3S2 = 4902.800066;
moonAngularRate = 2*pi/(27.321661*86400);
theta0Rad = 0;
demPath = resolveSyntheticDemPath(dataDirectory);
[dem,demModel] = digitalElevationModel.loadTriaxialLunarDem( string(demPath),moonRadiusKm,24,48);
assert(isa(dem,"griddedInterpolant"), "Synthetic DEM loader did not return a griddedInterpolant.");
assert(numel(dem.GridVectors) == 2, "Synthetic DEM must be two-dimensional.");
assert(all(isfinite(dem.Values),"all"), "Synthetic DEM contains nonfinite elevations.");
latitudeGrid = dem.GridVectors{1}(:);
longitudeGrid = dem.GridVectors{2}(:);
assert(abs(latitudeGrid(1)+pi/2) < 1e-10 && abs(latitudeGrid(end)-pi/2) < 1e-10, ...
    "Synthetic DEM does not cover both lunar poles.");
assert(abs(longitudeGrid(1)) < 1e-10 && abs(longitudeGrid(end)-2*pi) < 1e-10, ...
    "Synthetic DEM does not contain an exact 0/360-degree seam.");
assert(all(diff(latitudeGrid) > 0), "Synthetic DEM latitude grid is not strictly increasing.");
assert(all(diff(longitudeGrid) > 0), "Synthetic DEM longitude grid is not strictly increasing.");

%% Representative south-polar candidate locations
candidateLatitudes = deg2rad([ -89.5
    -85.0
    -80.0
    -75.5]);
candidateLongitudes = deg2rad([ 15
    105
    205
    305]);
sampleElevationsKm = dem(candidateLatitudes,candidateLongitudes);
assert(all(isfinite(sampleElevationsKm)), "Synthetic DEM returned nonfinite south-polar elevations.");

%% Topographic-frame compatibility
sensorLatitude = candidateLatitudes(1);
sensorLongitude = candidateLongitudes(1);
sensorRotatingState = referenceFrames.topographic( zeros(6,1), sensorLatitude, sensorLongitude, dem, ...
        moonRadiusKm, "toRotating");
expectedSensorRadiusKm = moonRadiusKm + dem(sensorLatitude,sensorLongitude);
assert(abs(norm(sensorRotatingState(1:3))-expectedSensorRadiusKm) < 1e-9, ...
    "Topographic surface position is inconsistent with the synthetic DEM.");
[localState,~] = referenceFrames.topographic( sensorRotatingState, sensorLatitude, sensorLongitude, ...
        dem, moonRadiusKm, "fromRotating");
assert(norm(localState) < 1e-9, "Topographic round-trip failed with the synthetic DEM.");

%% Terrain-horizon compatibility
[horizonAzimuths,maximumTerrainElevation] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( candidateLatitudes, ...
        candidateLongitudes, dem, 20, 5, deg2rad(30), moonRadiusKm);
assert(all(isfinite(maximumTerrainElevation),"all"), ...
    "Terrain horizon contains nonfinite values with the synthetic DEM.");
assert(size(maximumTerrainElevation,1) == numel(candidateLatitudes), ...
    "Terrain-horizon sensor dimension is inconsistent.");

%% Representative target trajectory
initialRadiusKm = moonRadiusKm + 300;
initialState = [ initialRadiusKm
    0
    0
    0
    0
    sqrt(moonMuKm3S2/initialRadiusKm)];
trackingTimes = (600:600:3600).';
[~,propagatedStates] = orbitDynamics.propagateLunarOrbit( initialState, [0;trackingTimes], ...
        moonMu=moonMuKm3S2);
targetStateHistories = reshape( propagatedStates(2:end,:).', 6,numel(trackingTimes),1);

%% RA/Dec measurement and Jacobian compatibility
measurement = measurements.surfaceRaDecMeasurement( targetStateHistories(:,1,1), trackingTimes(1), ...
        sensorLatitude, sensorLongitude, dem, moonRadiusKm, theta0Rad, moonAngularRate);
measurementJacobian = measurements.surfaceRaDecJacobian( targetStateHistories(:,1,1), ...
        trackingTimes(1), sensorLatitude, sensorLongitude, dem, moonRadiusKm, theta0Rad, ...
        moonAngularRate);
assert(all(isfinite(measurement)), "RA/Dec measurement is nonfinite with the synthetic DEM.");
assert(all(isfinite(measurementJacobian),"all"), ...
    "RA/Dec Jacobian is nonfinite with the synthetic DEM.");

%% Optimization tracking-data precompute
[referenceStateHistory,stateTransitionHistory,processNoiseHistory, measurementJacobianHistory] = ...
    optimization.precomputeTrackingData( 0, trackingTimes, initialState, candidateLatitudes, ...
        candidateLongitudes, dem, 0, 1e-15, moonMuKm3S2, moonRadiusKm, theta0Rad, moonAngularRate);
assert(all(isfinite(referenceStateHistory),"all"), "Tracking reference states are nonfinite.");
assert(all(isfinite(stateTransitionHistory),"all"), "Tracking STM history is nonfinite.");
assert(all(isfinite(processNoiseHistory),"all"), "Tracking process-noise history is nonfinite.");
assert(all(isfinite(measurementJacobianHistory),"all"), ...
    "Tracking measurement-Jacobian history is nonfinite.");

%% Filtered visibility and independent exclusion angles
numberOfTimes = numel(trackingTimes);
earthPositionsMci = repmat([384400;0;0],1,numberOfTimes);
sunPositionsMci = repmat([0;149597870.7;0],1,numberOfTimes);
sunMinimumAngularSeparationRad = deg2rad(20);
earthMinimumAngularSeparationRad = deg2rad(10);
[filteredAvailability,visibilityDiagnostics] = optimization.buildFilteredVisibilityDatabase( ...
        trackingTimes, targetStateHistories, candidateLatitudes, candidateLongitudes, dem, ...
        horizonAzimuths, maximumTerrainElevation, earthPositionsMci, sunPositionsMci, 0, 0, ...
        6378.1366, 695700, sunMinimumAngularSeparationRad, moonRadiusKm, theta0Rad, moonAngularRate, ...
        earthMinimumAngularSeparationRad);
assert( size(filteredAvailability,1) == numel(candidateLatitudes) && ...
    size(filteredAvailability,2) == numberOfTimes && size(filteredAvailability,3) == 1, ...
    "Filtered visibility dimensions are inconsistent.");
assert(abs( visibilityDiagnostics.configuredEarthMinimumAngularSeparation - ...
    earthMinimumAngularSeparationRad) < 1e-12, "Earth exclusion angle was not propagated correctly.");
assert(abs( visibilityDiagnostics.configuredSunMinimumAngularSeparation - ...
    sunMinimumAngularSeparationRad) < 1e-12, "Sun exclusion angle was not propagated correctly.");
end

function demPath = resolveSyntheticDemPath(dataDirectory)
candidateNames = [ "Synthetic:LunarDEM.mat"
    "Synthetic_LunarDEM.mat"
    "Synthetic_Lunar_DEM.mat"
    ];
for candidateIndex = 1:numel(candidateNames)
    candidatePath = fullfile(dataDirectory,candidateNames(candidateIndex));
    if isfile(candidatePath)
        demPath = candidatePath;
        return
    end
end
error( "testSyntheticLunarDemCompatibility:DemNotFound", [ ...
    "Synthetic lunar DEM was not found in %s. Expected one of:\n" + "  Synthetic:LunarDEM.mat\n" + ...
    "  Synthetic_LunarDEM.mat\n" + "  Synthetic_Lunar_DEM.mat" ], dataDirectory);
end

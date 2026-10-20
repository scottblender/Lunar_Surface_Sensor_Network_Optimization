function tests = testTerrainIntegration
% TESTTERRAININTEGRATION - Verify multi-target screening, ray clearance, and network estimation.
% Requires a local DEM. Set LUNAR_TEST_DEM_FILE to override the default input.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root); setupProject;
file = string(getenv("LUNAR_TEST_DEM_FILE"));
if strlength(file)==0
    file = fullfile(root,"data","Synthetic_Lunar_DEM.mat");
end
testCase.assertTrue(isfile(file),"Set LUNAR_TEST_DEM_FILE to a local lunar DEM.");
[testCase.TestData.dem,~] = digitalElevationModel.loadTriaxialLunarDem(file);
end

function setup(testCase)
previous = rng;
testCase.addTeardown(@()rng(previous));
rng(4,"twister");
end

function testFilteredVisibility(testCase)
dem = testCase.TestData.dem;
longitudeGrid = dem.GridVectors{2}(:);

%% Constants
moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2
earthRadius = 6378.1366;              % km
sunRadius = 695700;                   % km
earthMoonDistance = 384400;           % km
sunMoonDistance = 149597870.7;        % km
moonSiderealPeriod = 27.321661*86400;
moonAngularRate = 2*pi/moonSiderealPeriod;
earthDirectionRate = 2*pi/moonSiderealPeriod;
sunDirectionRate = 2*pi/(365.256363004*86400);
theta0 = 0;
instrumentMinimumElevation = deg2rad(0);
horizonMargin = deg2rad(0);

% One center-referenced keep-out/minimum separation is applied to both
% Earth and Sun. This is a test value, not an instrument requirement.
minimumAngularSeparation = deg2rad(20);

%% Candidate sensor set: 24 locations across the south-polar band
candidateLatitudeDegrees = [ -89.5
    -85.0
    -80.0
    -75.5
];
candidateLongitudeDegrees = (0:60:300).';
[longitudeMesh,latitudeMesh] = meshgrid( candidateLongitudeDegrees, candidateLatitudeDegrees);
candidateLatitudes = deg2rad(latitudeMesh(:));
candidateLongitudes = deg2rad(longitudeMesh(:));
numberOfSensors = length(candidateLatitudes);
assert(numberOfSensors == 24, "The test should contain 24 candidate sensors.");

%% Terrain horizon database
maximumTerrainRange = 100;            % km
terrainRangeStep = 0.5;               % km
horizonAzimuthStep = deg2rad(2);      % rad
[horizonAzimuths,maximumTerrainElevation] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( candidateLatitudes, ...
        candidateLongitudes, dem, maximumTerrainRange, terrainRangeStep, horizonAzimuthStep, ...
        moonRadius);

%% Multi-RSO truth set
rsoNames = [
    "LRO-like 50 km polar"
    "Chandrayaan-1-like 100 km polar"
    "200 km, 60 deg inclined"
];
numberOfObjects = length(rsoNames);
truthInitialStates = zeros(6,numberOfObjects);
truthInitialStates(:,1) = circularOrbitState( moonRadius + 50,deg2rad(90),deg2rad(37),0,moonMu);
truthInitialStates(:,2) = circularOrbitState( ...
    moonRadius + 100,deg2rad(90),deg2rad(120),deg2rad(35),moonMu);
truthInitialStates(:,3) = circularOrbitState( ...
    moonRadius + 200,deg2rad(60),deg2rad(205.2),deg2rad(-90),moonMu);
outputStep = 60;                      % s
finalTime = 8*3600;                   % s
times = (0:outputStep:finalTime).';
numberOfTimes = length(times);
targetStateHistories = zeros(6,numberOfTimes,numberOfObjects);
for objectIndex = 1:numberOfObjects
    [propagatedTimes,propagatedStates] = orbitDynamics.propagateLunarOrbit( ...
            truthInitialStates(:,objectIndex), times, moonMu=moonMu);
    assert(max(abs(propagatedTimes - times)) < 1e-9, ...
        "The time grid changed for object %d.",objectIndex);
    targetStateHistories(:,:,objectIndex) = propagatedStates.';
end

%% Generic-time Earth and Sun histories in MCI
% Use repeatable Earth/Sun phases; mission analysis needs dated ephemerides.
earthPhase0 = deg2rad(20);
sunPhase0 = deg2rad(145);
solarInclination = deg2rad(5.145);
earthPhase = earthPhase0 + earthDirectionRate*times.';
earthPositionsMci = earthMoonDistance*[ cos(earthPhase)
    sin(earthPhase)
    zeros(1,numberOfTimes)
];
sunPhase = sunPhase0 + sunDirectionRate*times.';
sunPlanarPositions = sunMoonDistance*[ cos(sunPhase)
    sin(sunPhase)
    zeros(1,numberOfTimes)
];
solarInclinationRotation = [ 1,0,0
    0,cos(solarInclination),-sin(solarInclination)
    0,sin(solarInclination), cos(solarInclination)
];
sunPositionsMci = solarInclinationRotation*sunPlanarPositions;

%% Build fully filtered database
[filteredAvailability,diagnostics] = optimization.buildFilteredVisibilityDatabase( times, ...
        targetStateHistories, candidateLatitudes, candidateLongitudes, dem, horizonAzimuths, ...
        maximumTerrainElevation, earthPositionsMci, sunPositionsMci, instrumentMinimumElevation, ...
        horizonMargin, earthRadius, sunRadius, minimumAngularSeparation, moonRadius, theta0, ...
        moonAngularRate);
assert(isequal(filteredAvailability,diagnostics.accepted), ...
    "The returned database does not match diagnostics.accepted.");
assert(all( filteredAvailability <= diagnostics.terrainAvailability, "all"), ...
    "The fully filtered gate exceeds terrain visibility.");
assert(all( diagnostics.earthMinimumSeparation >= minimumAngularSeparation | ...
    isinf(diagnostics.earthMinimumSeparation), "all"), ...
    "Earth required separation fell below the configured minimum.");
assert(all( diagnostics.sunMinimumSeparation >= minimumAngularSeparation | ...
    isinf(diagnostics.sunMinimumSeparation), "all"), ...
    "Sun required separation fell below the configured minimum.");

%% Count mutually exclusive rejection categories
geometricCounts = zeros(numberOfObjects,1);
terrainRejectedCounts = zeros(numberOfObjects,1);
celestialRejectedCounts = zeros(numberOfObjects,1);
acceptedCounts = zeros(numberOfObjects,1);
earthBlockedRawCounts = zeros(numberOfObjects,1);
sunBlockedRawCounts = zeros(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    geometricCounts(objectIndex) = sum( diagnostics.geometricAvailability(:,:,objectIndex),"all");
    terrainRejectedCounts(objectIndex) = sum( diagnostics.terrainRejected(:,:,objectIndex),"all");
    celestialRejectedCounts(objectIndex) = sum( diagnostics.celestialRejected(:,:,objectIndex),"all");
    acceptedCounts(objectIndex) = sum( diagnostics.accepted(:,:,objectIndex),"all");
    terrainGate = diagnostics.terrainAvailability(:,:,objectIndex);
    earthBlockedRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.earthBlocked(:,:,objectIndex),"all");
    sunBlockedRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.sunBlocked(:,:,objectIndex),"all");
end
reconstructedCounts = terrainRejectedCounts + celestialRejectedCounts + acceptedCounts;
assert(all(reconstructedCounts == geometricCounts), ...
    "The mutually exclusive rejection counts do not reconcile.");
assert(all(acceptedCounts > 0), "At least one RSO has no fully accepted observations.");

%% Verify zero-angle degeneration to physical occultation
sampleObserver = [moonRadius;0;0];
sampleTarget = [moonRadius + 100;0;0];
sampleEarth = [earthMoonDistance;0;0];
sampleSun = [-sunMoonDistance;0;0];
[visibleZeroAngle,earthBlockedZeroAngle,sunBlockedZeroAngle] = constraints.celestialVisibility( ...
        sampleObserver, sampleTarget, sampleEarth, sampleSun, earthRadius, sunRadius, 0);
assert(visibleZeroAngle, "A target in front of both bodies should remain visible at zero separation.");
assert(~earthBlockedZeroAngle && ~sunBlockedZeroAngle, ...
    "Zero minimum separation should reduce to physical occultation only.");
end

function testConservativeRayClearance(testCase)
dem = testCase.TestData.dem;
longitudeGrid = dem.GridVectors{2}(:);

%% Lunar constants
moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2
moonSiderealPeriod = 27.321661 * 86400;                % s
moonAngularRate = 2*pi / moonSiderealPeriod;        % rad/s
theta0 = 0;                           % rad


%% Construct representative sensor sample

% Six latitude rings with four longitude samples per ring.
% Longitude offsets prevent all rings from sharing the same meridians.
sensorLatitudeLevels = [
    -89.5
    -87.0
    -84.0
    -81.0
    -78.0
    -75.5
];
baseLongitudes = [
    0
    90
    180
    270
];
numberOfLatitudeLevels = numel(sensorLatitudeLevels);
numberOfLongitudesPerLevel = numel(baseLongitudes);
numberOfSensors = numberOfLatitudeLevels * numberOfLongitudesPerLevel;
candidateLatitudes = zeros(numberOfSensors,1);
candidateLongitudes = zeros(numberOfSensors,1);
sensorIndex = 0;
for latitudeIndex = 1:numberOfLatitudeLevels
    longitudeOffset = 15 * (latitudeIndex - 1);
    for longitudeIndex = 1:numberOfLongitudesPerLevel
        sensorIndex = sensorIndex + 1;
        candidateLatitudes(sensorIndex) = deg2rad( sensorLatitudeLevels(latitudeIndex));
        candidateLongitudes(sensorIndex) = deg2rad( mod( baseLongitudes(longitudeIndex) + ...
                    longitudeOffset, 360));
    end
end
fprintf( "Representative surface sensors: %d\n", numberOfSensors);

%% Build terrain-horizon database
maximumTerrainRange = 100;            % km

% The previous single-sensor test used 0.1 km. A 0.5 km step is used here
% because this test evaluates multiple sensors and RSOs.
terrainRangeStep = 0.5;               % km
horizonAzimuthStep = deg2rad(1);      % rad
terrainTimer = tic;
[ horizonAzimuths, maximumTerrainElevation, ~, sensorElevations, ~ ...
] = digitalElevationModel.buildMaximumTerrainHorizonDatabase( candidateLatitudes, ...
    candidateLongitudes, dem, maximumTerrainRange, terrainRangeStep, horizonAzimuthStep, moonRadius);
terrainBuildTime = toc(terrainTimer);
assert(all(isfinite(maximumTerrainElevation), "all"), ...
    "The terrain-horizon database contains nonfinite values.");
assert(all(isfinite(sensorElevations)), "The sensor elevations contain nonfinite values.");
fprintf( "Terrain database build time: %.2f seconds\n", terrainBuildTime);

%% Define representative RSO set
objectNames = [
    "LRO-like 50 km polar"
    "Chandrayaan-1-like 100 km polar"
    "200 km, 60 deg inclined"
];
orbitAltitudes = [
    50
    100
    200
];
orbitInclinations = deg2rad([
    90
    90
    60
]);
orbitAscendingNodes = deg2rad([
    37
    120
    250
]);
numberOfObjects = numel(orbitAltitudes);

%% Common propagation times
observationArc = 6 * 3600;            % s
outputStep = 30;                      % s
requestedTimes = (0:outputStep:observationArc).';
numberOfTimes = numel(requestedTimes);
rsoStateHistories = zeros( 6, numberOfTimes, numberOfObjects);
rotationZ = @(angle) [
     cos(angle), -sin(angle), 0
     sin(angle),  cos(angle), 0
              0,           0, 1
];
rotationX = @(angle) [
    1,          0,           0
    0, cos(angle), -sin(angle)
    0, sin(angle),  cos(angle)
];

%% Propagate RSO set
for objectIndex = 1:numberOfObjects
    orbitRadius = moonRadius + orbitAltitudes(objectIndex);
    circularVelocity = sqrt(moonMu / orbitRadius);
    perifocalPosition = [
        orbitRadius
        0
        0
    ];
    perifocalVelocity = [
        0
        circularVelocity
        0
    ];
    perifocalToMoonInertial = rotationZ(orbitAscendingNodes(objectIndex)) * ...
        rotationX(orbitInclinations(objectIndex));
    initialState = [
        perifocalToMoonInertial * perifocalPosition
        perifocalToMoonInertial * perifocalVelocity
    ];
    [propagatedTimes, propagatedStates] = orbitDynamics.propagateLunarOrbit( initialState, ...
            requestedTimes, moonMu = moonMu);
    assert( max(abs(propagatedTimes - requestedTimes)) < 1e-10, ...
        "The propagated time grid is incorrect.");
    if size(propagatedStates,2) == 6
        rsoStateHistories(:,:,objectIndex) = propagatedStates.';
    else
        rsoStateHistories(:,:,objectIndex) = propagatedStates;
    end
end
times = requestedTimes;

%% Evaluate precomputed terrain-horizon gate
instrumentMinimumElevation = deg2rad(0);
horizonMargin = deg2rad(0.1);
[ databaseAvailability, targetAzimuths, targetElevations, targetRanges, databaseLimitingElevations ...
] = optimization.buildTerrainAwareLosDatabase( times, rsoStateHistories, candidateLatitudes, ...
    candidateLongitudes, dem, horizonAzimuths, maximumTerrainElevation, instrumentMinimumElevation, ...
    horizonMargin, moonRadius, theta0, moonAngularRate);
geometricAvailability = targetElevations >= instrumentMinimumElevation;
assert( ~any( databaseAvailability & ~geometricAvailability, "all"), ...
    "The terrain database created a geometrically invalid measurement.");

%% Direct range-aware terrain sampling
terrainSearchRanges = (terrainRangeStep: terrainRangeStep: maximumTerrainRange).';
directAvailability = false( numberOfSensors, numberOfTimes, numberOfObjects);
directLimitingElevations = nan( numberOfSensors, numberOfTimes, numberOfObjects);
rawGeometryMismatchCount = 0;
clearanceTolerance = 1e-10;           % km
angleTolerance = 1e-12;               % rad
directTimer = tic;
for sensorIndex = 1:numberOfSensors
    sensorLatitude = candidateLatitudes(sensorIndex);
    sensorLongitude = candidateLongitudes(sensorIndex);
    sensorRadius = moonRadius + sensorElevations(sensorIndex);
    sinSensorLatitude = sin(sensorLatitude);
    cosSensorLatitude = cos(sensorLatitude);
    for objectIndex = 1:numberOfObjects
        for timeIndex = 1:numberOfTimes
            if ~geometricAvailability( sensorIndex, timeIndex, objectIndex)
                directAvailability( sensorIndex, timeIndex, objectIndex) = false;
                continue;
            end
            targetAzimuth = mod( targetAzimuths( sensorIndex, timeIndex, objectIndex), 2*pi);
            targetElevation = targetElevations( sensorIndex, timeIndex, objectIndex);
            targetSlantRange = targetRanges( sensorIndex, timeIndex, objectIndex);
            %% Target ground distance
            targetHorizontalDistance = targetSlantRange * cos(targetElevation);
            targetRadialCoordinate = sensorRadius + targetSlantRange * sin(targetElevation);
            targetCentralAngle = atan2( targetHorizontalDistance, targetRadialCoordinate);
            targetSurfaceDistance = moonRadius * targetCentralAngle;
            directMaximumRange = min( maximumTerrainRange, targetSurfaceDistance);
            sampledRanges = terrainSearchRanges( terrainSearchRanges <= directMaximumRange + 1e-12);
            if isempty(sampledRanges)
                directMaximumTerrainAngle = -pi/2;
                rawRayIsClear = true;
            else
                centralAngles = sampledRanges / moonRadius;
                %% Terrain coordinates along the target azimuth
                sinTerrainLatitudes = sinSensorLatitude .* cos(centralAngles) + cosSensorLatitude .* ...
                        sin(centralAngles) .* cos(targetAzimuth);
                sinTerrainLatitudes = max( -1, min(1, sinTerrainLatitudes));
                terrainLatitudes = asin(sinTerrainLatitudes);
                terrainLongitudes = sensorLongitude + atan2( sin(targetAzimuth) .* ...
                            sin(centralAngles) .* cosSensorLatitude, cos(centralAngles) - ...
                            sinSensorLatitude .* sinTerrainLatitudes);
                terrainLongitudesForDem = wrapLongitudeForDem( terrainLongitudes, dem.GridVectors{2});
                terrainElevations = dem( terrainLatitudes, terrainLongitudesForDem);
                terrainRadii = moonRadius + terrainElevations;
                %% Apparent terrain elevation
                terrainHorizontalDistances = terrainRadii .* sin(centralAngles);
                terrainVerticalDistances = terrainRadii .* cos(centralAngles) - sensorRadius;
                terrainApparentAngles = atan2( terrainVerticalDistances, terrainHorizontalDistances);
                directMaximumTerrainAngle = max(terrainApparentAngles);
                %% Direct ray clearance
                rayRadii = sensorRadius * cos(targetElevation) ./ cos( targetElevation + centralAngles);
                rayClearances = rayRadii - terrainRadii;
                minimumRayClearance = min(rayClearances);
                rawRayIsClear = minimumRayClearance >= -clearanceTolerance;
            end
            %% Verify direct ray and angle formulations
            rawAngleIsClear = targetElevation >= directMaximumTerrainAngle - angleTolerance;
            if rawRayIsClear ~= rawAngleIsClear
                rawGeometryMismatchCount = rawGeometryMismatchCount + 1;
            end
            %% Apply instrument minimum and horizon margin
            directLimitingElevation = max( instrumentMinimumElevation, directMaximumTerrainAngle + ...
                horizonMargin);
            directLimitingElevations( sensorIndex, timeIndex, objectIndex) = directLimitingElevation;
            directAvailability( sensorIndex, timeIndex, objectIndex) = targetElevation >= ...
                directLimitingElevation;
        end
    end
end
directEvaluationTime = toc(directTimer);
assert( rawGeometryMismatchCount == 0, ["The direct ray-radius test and direct apparent-angle test " ...
     "do not agree."]);
fprintf( "Direct ray evaluation time: %.2f seconds\n", directEvaluationTime);

%% Compare database and direct gates
falseClearances = databaseAvailability & ~directAvailability;
conservativeRejections = ~databaseAvailability & directAvailability & geometricAvailability;
gateAgreement = databaseAvailability == directAvailability;
geometricCounts = zeros(numberOfObjects,1);
databaseCounts = zeros(numberOfObjects,1);
directCounts = zeros(numberOfObjects,1);
visibleAgreementCounts = zeros(numberOfObjects,1);
conservativeCounts = zeros(numberOfObjects,1);
falseClearanceCounts = zeros(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    geometricCounts(objectIndex) = sum( geometricAvailability(:,:,objectIndex), "all");
    databaseCounts(objectIndex) = sum( databaseAvailability(:,:,objectIndex), "all");
    directCounts(objectIndex) = sum( directAvailability(:,:,objectIndex), "all");
    visibleAgreementCounts(objectIndex) = sum( gateAgreement(:,:,objectIndex) & ...
        geometricAvailability(:,:,objectIndex), "all");
    conservativeCounts(objectIndex) = sum( conservativeRejections(:,:,objectIndex), "all");
    falseClearanceCounts(objectIndex) = sum( falseClearances(:,:,objectIndex), "all");
end

%% Assertions
assert(all(geometricCounts > 0), "At least one test RSO has no geometric visibility.");
assert( sum(falseClearanceCounts) == 0, ["The precomputed horizon database accepted at least one " ...
     "measurement that direct terrain sampling found obstructed."]);
end

function testTerrainAwareObjectives(testCase)
dem = testCase.TestData.dem;
longitudeGrid = dem.GridVectors{2}(:);

%% Lunar constants
moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2
moonSiderealPeriod = 27.321661 * 86400;                % s
moonAngularRate = 2*pi / moonSiderealPeriod;        % rad/s
theta0 = 0;                           % rad

%% Measurement and filter settings
minimumElevation = deg2rad(0);
horizonMargin = deg2rad(0.1);
rightAscensionSigma = deg2rad(1/3600);                  % 1 arcsecond
declinationSigma = deg2rad(1/3600);                  % 1 arcsecond
measurementCovariance = diag([
    rightAscensionSigma^2
    declinationSigma^2
]);
accelerationNoiseIntensity = 1e-15;                            % km^2/s^3
stateScales = [
    1
    1
    1
    1e-3
    1e-3
    1e-3
];

%% Representative candidate sensor set

% This is the same 24-sensor sample used in the multi-RSO direct
% ray-clearance test.
sensorLatitudeLevels = [
    -89.5
    -87.0
    -84.0
    -81.0
    -78.0
    -75.5
];
baseLongitudes = [
    0
    90
    180
    270
];
numberOfLatitudeLevels = length(sensorLatitudeLevels);
numberOfLongitudesPerLevel = length(baseLongitudes);
numberOfCandidates = numberOfLatitudeLevels * numberOfLongitudesPerLevel;
candidateLatitudes = zeros(numberOfCandidates,1);
candidateLongitudes = zeros(numberOfCandidates,1);
candidateIndex = 0;
for latitudeIndex = 1:numberOfLatitudeLevels
    longitudeOffset = 15 * (latitudeIndex - 1);
    for longitudeIndex = 1:numberOfLongitudesPerLevel
        candidateIndex = candidateIndex + 1;
        candidateLatitudes(candidateIndex) = deg2rad( sensorLatitudeLevels(latitudeIndex));
        candidateLongitudes(candidateIndex) = deg2rad( mod( baseLongitudes(longitudeIndex) + ...
                    longitudeOffset, 360));
    end
end
fprintf( "Candidate surface sensors: %d\n", numberOfCandidates);

%% Build static terrain-horizon database
maximumTerrainRange = 100;            % km
terrainRangeStep = 0.5;               % km
horizonAzimuthStep = deg2rad(1);      % rad
terrainTimer = tic;
[ horizonAzimuths, maximumTerrainElevation, maximumFeatureRange, sensorElevations, ...
    maximumFeatureElevations ] = digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
    candidateLatitudes, candidateLongitudes, dem, maximumTerrainRange, terrainRangeStep, ...
    horizonAzimuthStep, moonRadius);
terrainBuildTime = toc(terrainTimer);
assert(all(isfinite(maximumTerrainElevation), "all"), ...
    "The terrain-horizon database contains nonfinite values.");
assert(all(isfinite(maximumFeatureRange), "all"), ...
    "The terrain feature ranges contain nonfinite values.");
assert(all(isfinite(sensorElevations)), "The sensor elevations contain nonfinite values.");
assert(all(isfinite(maximumFeatureElevations), "all"), ...
    "The terrain feature elevations contain nonfinite values.");
fprintf( "Terrain database build time: %.2f seconds\n", terrainBuildTime);

%% Define RSO set
objectNames = [
    "LRO-like 50 km polar"
    "Chandrayaan-1-like 100 km polar"
    "200 km, 60 deg inclined"
];
orbitAltitudes = [
    50
    100
    200
];
orbitInclinations = deg2rad([
    90
    90
    60
]);
orbitAscendingNodes = deg2rad([
    37
    120
    250
]);
numberOfObjects = length(orbitAltitudes);

%% Construct initial RSO states
initialStates = zeros(6, numberOfObjects);
rotationZ = @(angle) [
     cos(angle), -sin(angle), 0
     sin(angle),  cos(angle), 0
              0,           0, 1
];
rotationX = @(angle) [
    1,          0,           0
    0, cos(angle), -sin(angle)
    0, sin(angle),  cos(angle)
];
for objectIndex = 1:numberOfObjects
    orbitRadius = moonRadius + orbitAltitudes(objectIndex);
    circularVelocity = sqrt(moonMu / orbitRadius);
    perifocalToMoonInertial = rotationZ( orbitAscendingNodes(objectIndex)) * rotationX( ...
            orbitInclinations(objectIndex));
    initialStates(:,objectIndex) = [
        perifocalToMoonInertial * [orbitRadius; 0; 0]
        perifocalToMoonInertial * [0; circularVelocity; 0]
    ];
end

%% Observation arc
initialTime = 0;                      % s
observationArc = 6 * 3600;            % s
outputStep = 30;                      % s
observationTimes = (outputStep:outputStep:observationArc).';
numberOfTimes = length(observationTimes);

%% Allocate tracking database
referenceStateHistories = zeros( 6, numberOfTimes, numberOfObjects);
stateTransitionHistories = zeros( 6, 6, numberOfTimes, numberOfObjects);
processNoiseHistories = zeros( 6, 6, numberOfTimes, numberOfObjects);
measurementJacobianHistories = zeros( 2, 6, numberOfCandidates, numberOfTimes, numberOfObjects);
geometricAvailability = false( numberOfCandidates, numberOfTimes, numberOfObjects);
precomputedElevations = zeros( numberOfCandidates, numberOfTimes, numberOfObjects);

%% Precompute dynamics and measurement Jacobians
precomputeTimer = tic;
for objectIndex = 1:numberOfObjects
    [ referenceStateHistory, stateTransitionHistory, processNoiseHistory, ...
        measurementJacobianHistory, objectGeometricAvailability, objectTopographicElevation ...
    ] = optimization.precomputeTrackingData( initialTime, observationTimes, ...
        initialStates(:,objectIndex), candidateLatitudes, candidateLongitudes, dem, ...
        minimumElevation, accelerationNoiseIntensity, moonMu, moonRadius, theta0, moonAngularRate);
    referenceStateHistories(:,:,objectIndex) = referenceStateHistory;
    stateTransitionHistories(:,:,:,objectIndex) = stateTransitionHistory;
    processNoiseHistories(:,:,:,objectIndex) = processNoiseHistory;
    measurementJacobianHistories(:,:,:,:,objectIndex) = measurementJacobianHistory;
    geometricAvailability(:,:,objectIndex) = objectGeometricAvailability;
    precomputedElevations(:,:,objectIndex) = objectTopographicElevation;
end
precomputeTime = toc(precomputeTimer);
fprintf( "Tracking database build time: %.2f seconds\n", precomputeTime);

%% Apply terrain-aware LOS filtering
[ terrainAvailability, targetAzimuths, terrainTargetElevations, targetRanges, ...
    terrainLimitingElevations ] = optimization.buildTerrainAwareLosDatabase( observationTimes, ...
    referenceStateHistories, candidateLatitudes, candidateLongitudes, dem, horizonAzimuths, ...
    maximumTerrainElevation, minimumElevation, horizonMargin, moonRadius, theta0, moonAngularRate);
assert(all(isfinite(targetAzimuths), "all"), "The target azimuths contain nonfinite values.");
assert(all(isfinite(targetRanges), "all"), "The target ranges contain nonfinite values.");
assert(all(isfinite(terrainLimitingElevations), "all"), ...
    "The terrain limiting elevations contain nonfinite values.");

%% Verify precomputeTrackingData consistency
elevationDifference = max( abs( precomputedElevations - terrainTargetElevations), [], "all");
assert(elevationDifference < 1e-9, "The two topographic elevation calculations are inconsistent.");
assert( ~any( terrainAvailability & ~geometricAvailability, "all"), ...
    "Terrain filtering created a geometrically invalid measurement.");
terrainRejectedMeasurements = geometricAvailability & ~terrainAvailability;

%% Fixed representative initial covariance

% This is held fixed across every candidate-network evaluation, matching
% the production representative-IOD prior policy.
initialPositionSigma = 2;             % km
initialVelocitySigma = 2e-3;          % km/s
fixedInitialCovariance = diag([
    initialPositionSigma^2
    initialPositionSigma^2
    initialPositionSigma^2
    initialVelocitySigma^2
    initialVelocitySigma^2
    initialVelocitySigma^2
]);
initialCovariances = repmat( fixedInitialCovariance, 1, 1, numberOfObjects);
objectWeights = ones(numberOfObjects,1);

%% Identify terrain-sensitive sensor
terrainLossCounts = reshape( sum( terrainRejectedMeasurements, [2, 3]), numberOfCandidates, 1);
[maximumTerrainLoss, terrainSensitiveSensor] = max(terrainLossCounts);
assert(maximumTerrainLoss > 0, "None of the candidate sensors lose measurements to terrain.");

%% Select complementary sensor using terrain-aware coverage
pairCoverageScores = -inf(numberOfCandidates,1);
for candidateIndex = 1:numberOfCandidates
    if candidateIndex == terrainSensitiveSensor
        continue;
    end
    trialSelection = false(numberOfCandidates,1);
    trialSelection(terrainSensitiveSensor) = true;
    trialSelection(candidateIndex) = true;
    [trialCoverageObjective, ~] = optimization.coverageObjective( trialSelection, ...
            terrainAvailability, objectWeights);
    pairCoverageScores(candidateIndex) = -trialCoverageObjective;
end
[~, complementarySensor] = max(pairCoverageScores);
assert(complementarySensor ~= terrainSensitiveSensor, "The complementary sensor selection is invalid.");
fprintf("\nSelected test sensors\n");
fprintf( "  Terrain-sensitive sensor: %d, %.3f deg lat, %.3f deg lon\n", terrainSensitiveSensor, ...
    rad2deg(candidateLatitudes(terrainSensitiveSensor)), ...
    rad2deg(candidateLongitudes(terrainSensitiveSensor)));
fprintf( "  Terrain-rejected opportunities: %d\n", maximumTerrainLoss);
fprintf( "  Complementary sensor:     %d, %.3f deg lat, %.3f deg lon\n", complementarySensor, ...
    rad2deg(candidateLatitudes(complementarySensor)), ...
    rad2deg(candidateLongitudes(complementarySensor)));

%% Candidate networks
networkNames = [
    "No sensors"
    "Terrain-sensitive sensor"
    "Complementary sensor"
    "Two-sensor network"
];
networkSelections = false( numberOfCandidates, 4);
networkSelections( terrainSensitiveSensor, 2) = true;
networkSelections( complementarySensor, 3) = true;
networkSelections( [terrainSensitiveSensor, complementarySensor], 4) = true;
numberOfNetworks = size(networkSelections,2);

%% Allocate objective results
geometricInformationScores = zeros(numberOfNetworks,1);
terrainInformationScores = zeros(numberOfNetworks,1);
geometricCoverageScores = zeros(numberOfNetworks,1);
terrainCoverageScores = zeros(numberOfNetworks,1);
geometricInformationByObject = zeros(numberOfNetworks, numberOfObjects);
terrainInformationByObject = zeros(numberOfNetworks, numberOfObjects);
geometricCoverageByObject = zeros(numberOfNetworks, numberOfObjects);
terrainCoverageByObject = zeros(numberOfNetworks, numberOfObjects);

%% Evaluate geometric and terrain-aware objectives
for networkIndex = 1:numberOfNetworks
    selectedSensors = networkSelections(:,networkIndex);
    [geometricInformationObjective, geometricObjectScores] = optimization.informationObjective( ...
            selectedSensors, initialCovariances, stateTransitionHistories, processNoiseHistories, ...
            measurementJacobianHistories, geometricAvailability, measurementCovariance, stateScales, ...
            objectWeights);
    [terrainInformationObjective, terrainObjectScores] = optimization.informationObjective( ...
            selectedSensors, initialCovariances, stateTransitionHistories, processNoiseHistories, ...
            measurementJacobianHistories, terrainAvailability, measurementCovariance, stateScales, ...
            objectWeights);
    geometricInformationScores(networkIndex) = -geometricInformationObjective;
    terrainInformationScores(networkIndex) = -terrainInformationObjective;
    geometricInformationByObject(networkIndex,:) = geometricObjectScores.';
    terrainInformationByObject(networkIndex,:) = terrainObjectScores.';
    [geometricCoverageObjective, geometricObjectCoverage] = optimization.coverageObjective( ...
            selectedSensors, geometricAvailability, objectWeights);
    [terrainCoverageObjective, terrainObjectCoverage] = optimization.coverageObjective( ...
            selectedSensors, terrainAvailability, objectWeights);
    geometricCoverageScores(networkIndex) = -geometricCoverageObjective;
    terrainCoverageScores(networkIndex) = -terrainCoverageObjective;
    geometricCoverageByObject(networkIndex,:) = geometricObjectCoverage.';
    terrainCoverageByObject(networkIndex,:) = terrainObjectCoverage.';
end

%% Validate terrain-aware objective behavior
comparisonTolerance = 1e-8;
assert(all( terrainCoverageByObject <= geometricCoverageByObject, "all"), ...
    "Terrain filtering increased coverage.");
assert(all( terrainInformationByObject <= geometricInformationByObject + comparisonTolerance, ...
    "all"), "Terrain filtering increased information.");
assert(all( geometricCoverageByObject(1,:) == 0), "No-sensor geometric coverage should be zero.");
assert(all( terrainCoverageByObject(1,:) == 0), "No-sensor terrain coverage should be zero.");
assert( abs( geometricInformationScores(1) - terrainInformationScores(1)) < comparisonTolerance, ...
    "Terrain changed the no-sensor information score.");
assert( any( terrainCoverageByObject(2,:) < geometricCoverageByObject(2,:)), ...
    "The terrain-sensitive sensor did not lose network coverage.");
assert(all( terrainCoverageByObject(4,:) >= terrainCoverageByObject(2,:)), ...
    "Adding the complementary sensor reduced coverage.");
assert(all( terrainCoverageByObject(4,:) >= terrainCoverageByObject(3,:)), ...
    "The two-sensor network underperformed the complementary sensor.");
assert( terrainInformationScores(4) >= max(terrainInformationScores([2, 3])) - comparisonTolerance, ...
    "Adding the complementary sensor reduced information.");

%% Verify pair covariance histories
for objectIndex = 1:numberOfObjects
    objectStateTransitions = reshape( stateTransitionHistories(:,:,:,objectIndex), 6, 6, numberOfTimes);
    objectProcessNoise = reshape( processNoiseHistories(:,:,:,objectIndex), 6, 6, numberOfTimes);
    objectJacobians = reshape( measurementJacobianHistories( :,:,:,:,objectIndex), 2, 6, ...
        numberOfCandidates, numberOfTimes);
    objectTerrainAvailability = reshape( terrainAvailability(:,:,objectIndex), numberOfCandidates, ...
        numberOfTimes);
    [covarianceHistory, ~] = estimation.propagateNetworkCovariance( fixedInitialCovariance, ...
            objectStateTransitions, objectProcessNoise, objectJacobians, objectTerrainAvailability, ...
            networkSelections(:,4), measurementCovariance, stateScales);
    for timeIndex = 1:numberOfTimes
        covariance = covarianceHistory(:,:,timeIndex);
        symmetryError = norm(covariance - covariance.', "fro");
        assert(symmetryError < 1e-10, "Covariance lost symmetry.");
        [~, positiveDefiniteFlag] = chol(covariance, "lower");
        assert(positiveDefiniteFlag == 0, "Covariance is not positive definite.");
    end
end
end

function testNetworkEstimation(testCase)
dem = testCase.TestData.dem;
longitudeGrid = dem.GridVectors{2}(:);

%% Constants and estimation settings
moonRadius = 1737.4;                 % km
moonMu = 4902.800066;                % km^3/s^2
moonAngularRate = 2*pi/(27.321661*86400);
theta0 = 0;
minimumElevation = deg2rad(0);
horizonMargin = deg2rad(0);
rightAscensionSigma = deg2rad(1/3600);
declinationSigma = deg2rad(1/3600);
measurementCovariance = diag([ rightAscensionSigma^2
    declinationSigma^2
]);
measurementNoiseFactor = chol(measurementCovariance,"lower");
accelerationNoiseIntensity = 1e-15; % km^2/s^3
stateScales = [1;1;1;1e-3;1e-3;1e-3];

%% Candidate surface sensors
% Use a small varied sensor set to keep this regression test inexpensive.
candidateNames = [
    "Candidate 1"
    "Candidate 2"
    "Candidate 3"
    "Candidate 4"
];
candidateLatitudes = deg2rad([ -84.000000
    -89.505332
    -76.149000
    -76.000000
]);
candidateLongitudes = deg2rad([ 37.000000
    102.857143
    115.200000
    300.000000
]);
numberOfCandidates = length(candidateLatitudes);
measurementCovariances = repmat( measurementCovariance,1,1,numberOfCandidates);

%% Build the terrain database once for the candidate sensors
maximumTerrainRange = 100;           % km
terrainRangeStep = 0.5;              % km
horizonAzimuthStep = deg2rad(1);     % rad
[horizonAzimuths, maximumTerrainElevation, maximumFeatureRange, sensorElevations, ...
    maximumFeatureElevations] = digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        candidateLatitudes, candidateLongitudes, dem, maximumTerrainRange, terrainRangeStep, ...
        horizonAzimuthStep, moonRadius);
assert(all(isfinite(maximumTerrainElevation),"all"), ...
    "The terrain-horizon database contains nonfinite angles.");

%% Define the RSO set
rsoNames = [
    "LRO-like 50 km polar"
    "Chandrayaan-1-like 100 km polar"
    "200 km, 60 deg inclined"
];
numberOfObjects = length(rsoNames);
truthInitialStates = zeros(6,numberOfObjects);
truthInitialStates(:,1) = circularOrbitState( moonRadius + 50,deg2rad(90),deg2rad(37),0,moonMu);
truthInitialStates(:,2) = circularOrbitState( ...
    moonRadius + 100,deg2rad(90),deg2rad(120),deg2rad(35),moonMu);

% This orientation places a low southern pass near the south-polar
% candidate longitudes early in the test arc.
truthInitialStates(:,3) = circularOrbitState( ...
    moonRadius + 200,deg2rad(60),deg2rad(205.2),deg2rad(-90),moonMu);
objectWeights = ones(numberOfObjects,1);

%% Propagate all truth trajectories on the same time grid
outputStep = 30;                     % s
finalTime = 8*3600;                  % s
times = (0:outputStep:finalTime).';
numberOfTimes = length(times);
truthStateHistories = zeros(6,numberOfTimes,numberOfObjects);
for objectIndex = 1:numberOfObjects
    [propagatedTimes,propagatedStates] = orbitDynamics.propagateLunarOrbit( ...
            truthInitialStates(:,objectIndex), times, moonMu=moonMu);
    assert(max(abs(propagatedTimes - times)) < 1e-9, ...
        "The propagated time grid changed for object %d.",objectIndex);
    truthStateHistories(:,:,objectIndex) = propagatedStates.';
end

%% Terrain-aware truth visibility for all sensors and RSOs
[truthTerrainAvailability, truthAzimuths, truthElevations, truthRanges, truthLimitingElevations] = ...
    optimization.buildTerrainAwareLosDatabase( times, truthStateHistories, candidateLatitudes, ...
        candidateLongitudes, dem, horizonAzimuths, maximumTerrainElevation, minimumElevation, ...
        horizonMargin, moonRadius, theta0, moonAngularRate);
truthGeometricAvailability = truthElevations >= minimumElevation;
assert(all( truthTerrainAvailability <= truthGeometricAvailability, "all"), ...
    "Terrain-aware LOS cannot exceed geometric LOS.");
assert(all(any(truthTerrainAvailability,[1,2]),"all"), ...
    "At least one RSO has no terrain-approved observations.");

%% One representative terrain-gated IOD for each RSO
% Set a fixed prior for each object using its terrain-visible IOD sensor.
desiredIodObservationCount = 15;
numberOfMonteCarloSamples = 50;
iodSearchEndTime = 0.40*finalTime;
iodStates = zeros(6,numberOfObjects);
iodCovariances = zeros(6,6,numberOfObjects);
iodReferenceTimes = zeros(numberOfObjects,1);
iodSensorIndices = zeros(numberOfObjects,1);
iodObservationCounts = zeros(numberOfObjects,1);
iodDiagnostics = cell(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    objectAvailability = reshape( truthTerrainAvailability(:,:,objectIndex), ...
        numberOfCandidates,numberOfTimes);
    [iodSensorIndices(objectIndex),acquisitionIndices] = selectRepresentativeIodPass( ...
            objectAvailability, times, iodSearchEndTime, desiredIodObservationCount);
    iodObservationCounts(objectIndex) = length(acquisitionIndices);
    sensorIndex = iodSensorIndices(objectIndex);
    [observerPositionsMci,rightAscension,declination] = simulateSingleSensorMeasurements( times, ...
            truthStateHistories(:,:,objectIndex), sensorIndex, candidateLatitudes, ...
            candidateLongitudes, dem, objectAvailability(sensorIndex,:).', measurementNoiseFactor, ...
            moonRadius, theta0, moonAngularRate);
    [iodState,iodCovariance,iodReferenceTime,objectIodDiagnostics] = iod.anglesOnlyIod( times, ...
            rightAscension, declination, observerPositionsMci, acquisitionIndices, ...
            measurementCovariance, numberOfMonteCarloSamples, 100 + objectIndex, moonMu);
    iodStates(:,objectIndex) = iodState;
    iodCovariances(:,:,objectIndex) = iodCovariance;
    iodReferenceTimes(objectIndex) = iodReferenceTime;
    iodDiagnostics{objectIndex} = objectIodDiagnostics;
    iodCovariances(:,:,objectIndex) = 0.5*( iodCovariances(:,:,objectIndex) + ...
        iodCovariances(:,:,objectIndex).');
    [~,positiveDefiniteFlag] = chol( iodCovariances(:,:,objectIndex),"lower");
    assert(positiveDefiniteFlag == 0, "IOD covariance is not positive definite for object %d.", ...
        objectIndex);
end

%% Move all fixed IOD priors to one common optimization epoch
% Propagate all IOD priors to the latest reference epoch before network evaluation.
commonReferenceTime = max(iodReferenceTimes);
fixedInitialStates = zeros(6,numberOfObjects);
fixedInitialCovariances = zeros(6,6,numberOfObjects);
for objectIndex = 1:numberOfObjects
    [commonEpochState,commonEpochCovariance] = propagatePriorToTime( iodReferenceTimes(objectIndex), ...
            commonReferenceTime, iodStates(:,objectIndex), iodCovariances(:,:,objectIndex), ...
            accelerationNoiseIntensity, moonMu);
    fixedInitialStates(:,objectIndex) = commonEpochState;
    fixedInitialCovariances(:,:,objectIndex) = commonEpochCovariance;
end
optimizationIndices = find(times > commonReferenceTime);
optimizationTimes = times(optimizationIndices);
numberOfOptimizationTimes = length(optimizationTimes);
assert(numberOfOptimizationTimes > 0, "No optimization arc remains after the IOD stage.");
truthOptimizationHistories = truthStateHistories(:,optimizationIndices,:);

%% Precompute candidate-dependent tracking data for every RSO
referenceStateHistories = zeros(6,numberOfOptimizationTimes,numberOfObjects);
stateTransitionHistories = zeros(6,6,numberOfOptimizationTimes,numberOfObjects);
processNoiseHistories = zeros(6,6,numberOfOptimizationTimes,numberOfObjects);
measurementJacobianHistories = zeros(2,6,numberOfCandidates, numberOfOptimizationTimes,numberOfObjects);
geometricAvailabilityDatabase = false(numberOfCandidates, numberOfOptimizationTimes,numberOfObjects);
for objectIndex = 1:numberOfObjects
    [objectReferenceStates, objectStateTransitions, objectProcessNoise, objectMeasurementJacobians, ...
        objectGeometricAvailability] = optimization.precomputeTrackingData( commonReferenceTime, ...
            optimizationTimes, fixedInitialStates(:,objectIndex), candidateLatitudes, ...
            candidateLongitudes, dem, minimumElevation, accelerationNoiseIntensity, moonMu, ...
            moonRadius, theta0, moonAngularRate);
    referenceStateHistories(:,:,objectIndex) = objectReferenceStates;
    stateTransitionHistories(:,:,:,objectIndex) = objectStateTransitions;
    processNoiseHistories(:,:,:,objectIndex) = objectProcessNoise;
    measurementJacobianHistories(:,:,:,:,objectIndex) = objectMeasurementJacobians;
    geometricAvailabilityDatabase(:,:,objectIndex) = objectGeometricAvailability;
end

%% Apply the reusable terrain horizon to each nominal RSO trajectory
[terrainAvailabilityDatabase, nominalAzimuths, nominalElevations, nominalRanges, ...
    nominalLimitingElevations] = optimization.buildTerrainAwareLosDatabase( optimizationTimes, ...
        referenceStateHistories, candidateLatitudes, candidateLongitudes, dem, horizonAzimuths, ...
        maximumTerrainElevation, minimumElevation, horizonMargin, moonRadius, theta0, moonAngularRate);
assert(all( terrainAvailabilityDatabase <= geometricAvailabilityDatabase, "all"), ...
    "Terrain-aware availability exceeds geometric availability.");

%% Build the candidate networks: none, singles, and every two-sensor pair
sensorPairs = nchoosek(1:numberOfCandidates,2);
numberOfNetworks = 1 + numberOfCandidates + size(sensorPairs,1);
networkSelections = false(numberOfCandidates,numberOfNetworks);
networkNames = strings(numberOfNetworks,1);
networkNames(1) = "No sensors";
networkIndex = 1;
for sensorIndex = 1:numberOfCandidates
    networkIndex = networkIndex + 1;
    networkSelections(sensorIndex,networkIndex) = true;
    networkNames(networkIndex) = candidateNames(sensorIndex);
end
pairNetworkIndices = zeros(size(sensorPairs,1),1);
for pairIndex = 1:size(sensorPairs,1)
    networkIndex = networkIndex + 1;
    pairNetworkIndices(pairIndex) = networkIndex;
    sensorOne = sensorPairs(pairIndex,1);
    sensorTwo = sensorPairs(pairIndex,2);
    networkSelections([sensorOne,sensorTwo],networkIndex) = true;
    networkNames(networkIndex) = sprintf( "Candidates %d + %d",sensorOne,sensorTwo);
end


%% Evaluate terrain-aware coverage and information objectives
informationScores = zeros(numberOfNetworks,1);
coverageScores = zeros(numberOfNetworks,1);
informationByObject = zeros(numberOfNetworks,numberOfObjects);
coverageByObject = zeros(numberOfNetworks,numberOfObjects);
for networkIndex = 1:numberOfNetworks
    selectedSensors = networkSelections(:,networkIndex);
    [informationObjective,objectInformation] = optimization.informationObjective( selectedSensors, ...
            fixedInitialCovariances, stateTransitionHistories, processNoiseHistories, ...
            measurementJacobianHistories, terrainAvailabilityDatabase, measurementCovariances, ...
            stateScales, objectWeights);
    [coverageObjective,objectCoverage] = optimization.coverageObjective( selectedSensors, ...
            terrainAvailabilityDatabase, objectWeights);
    informationScores(networkIndex) = -informationObjective;
    coverageScores(networkIndex) = -coverageObjective;
    informationByObject(networkIndex,:) = objectInformation.';
    coverageByObject(networkIndex,:) = objectCoverage.';
end
assert(coverageScores(1) == 0, "The no-sensor coverage score must be zero.");
assert(all(coverageByObject(1,:) == 0), "The no-sensor network covered an RSO.");

%% Select the best pair for each separate objective
minimumFinalUpdatesPerObject = 3;
feasiblePairMask = all( coverageByObject(pairNetworkIndices,:) >= minimumFinalUpdatesPerObject, 2);
assert(any(feasiblePairMask), "No two-sensor network observes every RSO at least %d times.", ...
    minimumFinalUpdatesPerObject);
feasiblePairNetworkIndices = pairNetworkIndices(feasiblePairMask);
[~,informationPairLocation] = max( informationScores(feasiblePairNetworkIndices));
bestInformationNetworkIndex = feasiblePairNetworkIndices(informationPairLocation);
[~,coveragePairLocation] = max( coverageScores(feasiblePairNetworkIndices));
bestCoverageNetworkIndex = feasiblePairNetworkIndices(coveragePairLocation);

% Run the final EKFs for the information-optimal network. Change this one
% line to bestCoverageNetworkIndex to test the coverage-optimal network.
finalNetworkIndex = bestInformationNetworkIndex;
finalSensorSelection = networkSelections(:,finalNetworkIndex);
finalSensorIndices = find(finalSensorSelection);

%% Build truth measurements and run one final EKF per RSO
[truthOptimizationAvailability,~,~,~,~] = optimization.buildTerrainAwareLosDatabase( ...
        optimizationTimes, truthOptimizationHistories, candidateLatitudes, candidateLongitudes, dem, ...
        horizonAzimuths, maximumTerrainElevation, minimumElevation, horizonMargin, moonRadius, ...
        theta0, moonAngularRate);
positionErrorNorms = zeros(numberOfObjects,numberOfOptimizationTimes);
velocityErrorNorms = zeros(numberOfObjects,numberOfOptimizationTimes);
positionThreeSigmaNorms = zeros(numberOfObjects,numberOfOptimizationTimes);
velocityThreeSigmaNorms = zeros(numberOfObjects,numberOfOptimizationTimes);
finalStateHistories = cell(numberOfObjects,1);
finalCovarianceHistories = cell(numberOfObjects,1);
finalInnovationHistories = cell(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    objectTruthHistory = reshape( truthOptimizationHistories(:,:,objectIndex), ...
        6,numberOfOptimizationTimes);
    objectTruthAvailability = reshape( truthOptimizationAvailability(:,:,objectIndex), ...
        numberOfCandidates,numberOfOptimizationTimes);
    [observationTimes, rightAscension, declination, sensorLatitudes, sensorLongitudes, ...
        measurementAvailable] = simulateSelectedNetwork( optimizationTimes, objectTruthHistory, ...
            finalSensorIndices, candidateLatitudes, candidateLongitudes, dem, ...
            objectTruthAvailability, measurementNoiseFactor, moonRadius, theta0, moonAngularRate);
    [objectFinalStates, objectFinalCovariances, objectFinalInnovations] = ...
        estimation.lunarSurfaceEkf( commonReferenceTime, observationTimes, rightAscension, ...
            declination, sensorLatitudes, sensorLongitudes, dem, measurementAvailable, ...
            fixedInitialStates(:,objectIndex), fixedInitialCovariances(:,:,objectIndex), ...
            measurementCovariance, accelerationNoiseIntensity, moonMu, moonRadius, theta0, ...
            moonAngularRate);
    finalStateHistories{objectIndex} = objectFinalStates;
    finalCovarianceHistories{objectIndex} = objectFinalCovariances;
    finalInnovationHistories{objectIndex} = objectFinalInnovations;
    assert(any(all(isfinite( finalInnovationHistories{objectIndex}),1)), ...
        "The final EKF performed no updates for object %d.",objectIndex);
    numberOfSelectedSensors = length(finalSensorIndices);
    posteriorIndices = numberOfSelectedSensors : numberOfSelectedSensors : length(observationTimes);
    posteriorStates = finalStateHistories{objectIndex}(:,posteriorIndices);
    posteriorCovariances = finalCovarianceHistories{objectIndex}(:,:,posteriorIndices);
    stateError = posteriorStates - objectTruthHistory;
    positionErrorNorms(objectIndex,:) = vecnorm(stateError(1:3,:),2,1);
    velocityErrorNorms(objectIndex,:) = vecnorm(stateError(4:6,:),2,1);
    for timeIndex = 1:numberOfOptimizationTimes
        covariance = posteriorCovariances(:,:,timeIndex);
        covariance = 0.5*(covariance + covariance.');
        positionThreeSigmaNorms(objectIndex,timeIndex) = 3*sqrt(trace(covariance(1:3,1:3)));
        velocityThreeSigmaNorms(objectIndex,timeIndex) = 3*sqrt(trace(covariance(4:6,4:6)));
    end
end
end

function state = circularOrbitState(radius,inclination,raan,anomaly,mu)
state = orbitDynamics.keplerianToState(radius,0,inclination,raan,0,anomaly,mu);
end

function wrappedLongitudes = wrapLongitudeForDem( longitudes, demLongitudeGrid)
% Wrap longitude to match a 0-to-2*pi or -pi-to-pi DEM.
demLongitudeGrid = demLongitudeGrid(:);
if demLongitudeGrid(1) >= -1e-10 && demLongitudeGrid(end) > pi
    wrappedLongitudes = mod(longitudes, 2*pi);
else
    wrappedLongitudes = mod(longitudes + pi, 2*pi) - pi;
end
end

function [sensorIndex,acquisitionIndices] = selectRepresentativeIodPass( ...
        availability,times,searchEndTime,desiredCount)
numberOfSensors = size(availability,1);
bestRun = zeros(0,1);
sensorIndex = NaN;
for candidateIndex = 1:numberOfSensors
    eligible = availability(candidateIndex,:) & (times.' <= searchEndTime);
    changes = diff([false,eligible,false]);
    runStarts = find(changes == 1);
    runEnds = find(changes == -1) - 1;
    for runIndex = 1:length(runStarts)
        currentRun = (runStarts(runIndex):runEnds(runIndex)).';
        if length(currentRun) > length(bestRun)
            bestRun = currentRun;
            sensorIndex = candidateIndex;
        end
    end
end
assert(length(bestRun) >= 3, "No candidate has three terrain-approved IOD observations.");
numberToUse = min(desiredCount,length(bestRun));
selectionLocations = unique(round(linspace( 1,length(bestRun),numberToUse)));
acquisitionIndices = bestRun(selectionLocations);
acquisitionIndices = acquisitionIndices(:);
end

function [observerPositionsMci,rightAscension,declination] = simulateSingleSensorMeasurements( ...
        times,truthStateHistory,sensorIndex, candidateLatitudes,candidateLongitudes,dem, ...
        measurementAvailable,measurementNoiseFactor, moonRadius,theta0,angularRate)
numberOfTimes = length(times);
sensorLatitude = candidateLatitudes(sensorIndex);
sensorLongitude = mod(candidateLongitudes(sensorIndex),2*pi);
observerPositionsMci = zeros(numberOfTimes,3);
rightAscension = NaN(numberOfTimes,1);
declination = NaN(numberOfTimes,1);
sensorMoonRotatingState = referenceFrames.topographic( zeros(6,1), sensorLatitude, sensorLongitude, ...
    dem, moonRadius, "toRotating");
for timeIndex = 1:numberOfTimes
    observationTime = times(timeIndex);
    sensorMciState = referenceFrames.moonRotating( sensorMoonRotatingState, observationTime, theta0, ...
        angularRate, "toInertial");
    observerPositionsMci(timeIndex,:) = sensorMciState(1:3).';
    if ~measurementAvailable(timeIndex)
        continue
    end
    idealMeasurement = measurements.surfaceRaDecMeasurement( truthStateHistory(:,timeIndex), ...
        observationTime, sensorLatitude, sensorLongitude, dem, moonRadius, theta0, angularRate);
    noisyMeasurement = idealMeasurement + measurementNoiseFactor*randn(2,1);
    rightAscension(timeIndex) = wrapAngle(noisyMeasurement(1));
    declination(timeIndex) = noisyMeasurement(2);
end
end

function [propagatedState,propagatedCovariance] = propagatePriorToTime( ...
        initialTime,finalTime,initialState,initialCovariance, accelerationNoiseIntensity,moonMu)
if abs(finalTime - initialTime) < 1e-12
    propagatedState = initialState;
    propagatedCovariance = initialCovariance;
    return
end
augmentedInitialState = [initialState;reshape(eye(6),36,1)];
odeOptions = odeset("RelTol",1e-11,"AbsTol",1e-12);
[~,augmentedHistory] = ode45( @(time,augmentedState) orbitDynamics.lunarStateAndStmDynamics( ...
            time,augmentedState,moonMu), [initialTime,finalTime], augmentedInitialState, odeOptions);
augmentedFinalState = augmentedHistory(end,:).';
propagatedState = augmentedFinalState(1:6);
stateTransitionMatrix = reshape(augmentedFinalState(7:end),6,6);
processNoise = estimation.isotropicProcessNoise( finalTime - initialTime, accelerationNoiseIntensity);
propagatedCovariance = stateTransitionMatrix*initialCovariance* stateTransitionMatrix.' + processNoise;
propagatedCovariance = 0.5*( propagatedCovariance + propagatedCovariance.');
end

function [observationTimes,rightAscension,declination, ...
    sensorLatitudes,sensorLongitudes,measurementAvailable] = simulateSelectedNetwork( ...
        times,truthStateHistory,selectedSensorIndices, candidateLatitudes,candidateLongitudes,dem, ...
        terrainAvailability,measurementNoiseFactor, moonRadius,theta0,angularRate)
numberOfTimes = length(times);
numberOfSelectedSensors = length(selectedSensorIndices);
numberOfObservations = numberOfTimes*numberOfSelectedSensors;
observationTimes = zeros(numberOfObservations,1);
rightAscension = NaN(numberOfObservations,1);
declination = NaN(numberOfObservations,1);
sensorLatitudes = zeros(numberOfObservations,1);
sensorLongitudes = zeros(numberOfObservations,1);
measurementAvailable = false(numberOfObservations,1);
observationIndex = 0;
for timeIndex = 1:numberOfTimes
    for selectedIndex = 1:numberOfSelectedSensors
        observationIndex = observationIndex + 1;
        sensorIndex = selectedSensorIndices(selectedIndex);
        sensorLatitude = candidateLatitudes(sensorIndex);
        sensorLongitude = mod(candidateLongitudes(sensorIndex),2*pi);
        observationTimes(observationIndex) = times(timeIndex);
        sensorLatitudes(observationIndex) = sensorLatitude;
        sensorLongitudes(observationIndex) = sensorLongitude;
        measurementAvailable(observationIndex) = terrainAvailability(sensorIndex,timeIndex);
        if ~measurementAvailable(observationIndex)
            continue
        end
        idealMeasurement = measurements.surfaceRaDecMeasurement( truthStateHistory(:,timeIndex), ...
            times(timeIndex), sensorLatitude, sensorLongitude, dem, moonRadius, theta0, angularRate);
        noisyMeasurement = idealMeasurement + measurementNoiseFactor*randn(2,1);
        rightAscension(observationIndex) = wrapAngle(noisyMeasurement(1));
        declination(observationIndex) = noisyMeasurement(2);
    end
end
end

function wrappedAngle = wrapAngle(angle)
wrappedAngle = atan2(sin(angle),cos(angle));
end

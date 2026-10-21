function tests = testScientificModels
% TESTSCIENTIFICMODELS - Verify celestial/terrain gates, covariance objectives, and orbit tracking.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupProject;
end

function setup(testCase)
previous = rng;
testCase.addTeardown(@()rng(previous));
end

function testCelestialScreening(~)

%% Simple normalized geometry
% Use normalized geometry with analytically checkable results.
observerPosition = [0;0;0];
earthPosition = [100;0;0];
earthRadius = 10;

% Place the second body well away from the test LOS so Earth tests isolate
% the Earth gate. The same geometry is later swapped to test the Sun gate.
sunPosition = [0;-1000;0];
sunRadius = 10;
angularTolerance = 1e-11;

%% 1. Target in front of body: zero separation reduces to occultation only
% A target in front of Earth remains clear even at zero center separation.
targetPosition = [50;0;0];
[visibleZero,earthBlockedZero,sunBlockedZero, earthSeparationZero,~,earthRequiredZero,~] = ...
    constraints.celestialVisibility( observerPosition, targetPosition, earthPosition, sunPosition, ...
        earthRadius, sunRadius, 0);
assert(visibleZero, "Zero configured separation falsely rejected a target in front of the body.");
assert(~earthBlockedZero && ~sunBlockedZero, ...
    "A target in front of both bodies should not be physically occulted.");
assert(abs(earthSeparationZero) < angularTolerance, ...
    "The expected zero Earth center separation was not recovered.");
assert(abs(earthRequiredZero) < angularTolerance, ...
    "Zero configured separation should require zero angle when occultation is impossible.");

%% 2. Configured minimum separation can reject an unoccluded LOS
minimumAngularSeparation = deg2rad(5);
[visibleKeepOut,earthBlockedKeepOut,~,~,~,earthRequiredKeepOut,~] = constraints.celestialVisibility( ...
        observerPosition, targetPosition, earthPosition, sunPosition, earthRadius, sunRadius, ...
        minimumAngularSeparation);
assert(~visibleKeepOut && earthBlockedKeepOut, ...
    "Configured minimum separation did not reject an otherwise unoccluded LOS.");
assert(abs(earthRequiredKeepOut-minimumAngularSeparation) < angularTolerance, ...
    "Configured minimum separation was not used as the active threshold.");

%% 3. Zero configured separation reproduces physical occultation
% A target behind the body must fail both angular and segment/sphere tests.
targetPosition = [200;0;0];
[~,legacyEarthOccluded] = constraints.sphericalBodyOcclusion( observerPosition, targetPosition, ...
        earthPosition, earthRadius, 0);
[visibleOcculted,earthBlockedOcculted] = constraints.celestialVisibility( observerPosition, ...
        targetPosition, earthPosition, sunPosition, earthRadius, sunRadius, 0);
assert(legacyEarthOccluded, ...
    "Reference sphere/segment calculation did not detect the known occultation.");
assert(~visibleOcculted && earthBlockedOcculted, ...
    "Zero configured separation did not reproduce a known physical occultation.");

%% 4. Physical occultation dominates a smaller configured separation
% For a distant target, the occultation half-angle is asin(R/d).
earthOccultationAngle = asin(earthRadius/norm(earthPosition-observerPosition));
minimumAngularSeparation = deg2rad(2);
targetRange = 200;
blockedAngle = earthOccultationAngle - deg2rad(0.05);
clearAngle = earthOccultationAngle + deg2rad(0.05);
blockedTarget = targetRange*[cos(blockedAngle);sin(blockedAngle);0];
clearTarget = targetRange*[cos(clearAngle);sin(clearAngle);0];
[~,earthBlockedPhysical,~,~,~,earthRequiredPhysical] = constraints.celestialVisibility( ...
        observerPosition, blockedTarget, earthPosition, sunPosition, earthRadius, sunRadius, ...
        minimumAngularSeparation);
[visiblePhysicalClear,earthBlockedPhysicalClear] = constraints.celestialVisibility( ...
        observerPosition, clearTarget, earthPosition, sunPosition, earthRadius, sunRadius, ...
        minimumAngularSeparation);
assert(earthBlockedPhysical, ...
    "Physical occultation did not dominate the smaller configured separation.");
assert(abs(earthRequiredPhysical-earthOccultationAngle) < angularTolerance, ...
    "The physical occultation angle was not selected as the active threshold.");
assert(visiblePhysicalClear && ~earthBlockedPhysicalClear, ...
    "LOS just outside the physical occultation cone should be visible when above the configured separation.");

%% 5. Configured separation dominates the physical occultation angle
minimumAngularSeparation = deg2rad(20);
insideConfiguredAngle = deg2rad(10);
outsideConfiguredAngle = minimumAngularSeparation + deg2rad(0.05);
insideConfiguredTarget = targetRange*[cos(insideConfiguredAngle);sin(insideConfiguredAngle);0];
outsideConfiguredTarget = targetRange*[cos(outsideConfiguredAngle);sin(outsideConfiguredAngle);0];
[~,earthBlockedConfigured,~,earthSeparationConfigured,~, earthRequiredConfigured] = ...
    constraints.celestialVisibility( observerPosition, insideConfiguredTarget, earthPosition, ...
        sunPosition, earthRadius, sunRadius, minimumAngularSeparation);
[visibleOutsideConfigured,earthBlockedOutsideConfigured] = constraints.celestialVisibility( ...
        observerPosition, outsideConfiguredTarget, earthPosition, sunPosition, earthRadius, ...
        sunRadius, minimumAngularSeparation);
assert(earthSeparationConfigured > earthOccultationAngle, ...
    "Configured-separation test target should already clear physical occultation.");
assert(earthBlockedConfigured, ...
    "Configured minimum separation failed to reject a physically clear LOS.");
assert(abs(earthRequiredConfigured-minimumAngularSeparation) < angularTolerance, ...
    "Configured minimum separation was not selected as the active threshold.");
assert(visibleOutsideConfigured && ~earthBlockedOutsideConfigured, ...
    "LOS above the configured minimum separation should be visible.");

%% 6. Equality at the configured minimum separation is allowed
% Use pi/3 so the constructed direction has a simple cosine of 1/2.
boundarySeparation = pi/3;
boundaryTarget = targetRange*[cos(boundarySeparation);sin(boundarySeparation);0];
[visibleBoundary,earthBlockedBoundary,~,earthSeparationBoundary,~, earthRequiredBoundary] = ...
    constraints.celestialVisibility( observerPosition, boundaryTarget, earthPosition, sunPosition, ...
        earthRadius, sunRadius, boundarySeparation);
assert(abs(earthSeparationBoundary-boundarySeparation) < angularTolerance, ...
    "Boundary target did not reproduce the configured separation angle.");
assert(abs(earthRequiredBoundary-boundarySeparation) < angularTolerance, ...
    "Configured boundary was not the active minimum separation.");
assert(visibleBoundary && ~earthBlockedBoundary, ...
    "Equality at the configured minimum angular separation should be allowed.");

%% 7. Sun uses the same rule
% Apply the same zero-angle occultation check to the Sun.
earthPositionFar = [0;-1000;0];
sunPositionNear = [100;0;0];
targetPosition = [200;0;0];
[visibleSunOcculted,earthBlockedSunCase,sunBlockedSunCase] = constraints.celestialVisibility( ...
        observerPosition, targetPosition, earthPositionFar, sunPositionNear, earthRadius, sunRadius, 0);
assert(~visibleSunOcculted, "Known Sun occultation should reject the LOS.");
assert(~earthBlockedSunCase && sunBlockedSunCase, ...
    "Earth and Sun body-specific blocked masks are inconsistent.");

%% 8. Random zero-angle comparison against segment/sphere occultation
% At zero keep-out angle, compare against independent segment/sphere occultation.
rng(17,"twister");
numberOfRandomCases = 5000;
numberAcceptedCases = 0;
numberMismatches = 0;
while numberAcceptedCases < numberOfRandomCases
    randomDirection = randn(3,1);
    randomDirection = randomDirection/norm(randomDirection);
    randomRange = 20 + 280*rand;
    randomTarget = randomRange*randomDirection;
    % Skip targets inside the occulting body, since the intended RSO use
    % case places the target outside Earth and Sun.
    if norm(randomTarget-earthPosition) <= earthRadius
        continue;
    end
    numberAcceptedCases = numberAcceptedCases + 1;
    [~,legacyOccluded] = constraints.sphericalBodyOcclusion( observerPosition, randomTarget, ...
            earthPosition, earthRadius, 0);
    [~,earthBlocked] = constraints.celestialVisibility( observerPosition, randomTarget, ...
            earthPosition, sunPosition, earthRadius, sunRadius, 0);
    if earthBlocked ~= legacyOccluded
        numberMismatches = numberMismatches + 1;
    end
end
assert(numberMismatches == 0, ...
    "Zero-angle angular screening disagreed with physical occultation in %d of %d random cases.", ...
    numberMismatches,numberOfRandomCases);

%% 9. Monotonicity with increasing minimum angular separation
% Increasing keep-out angles must not clear a blocked line of sight.
rng(23,"twister");
minimumSeparationSweep = deg2rad([0,2,5,10,20]);
numberOfMonotonicityCases = 1000;
numberAcceptedMonotonicityCases = 0;
monotonicityFailures = 0;
while numberAcceptedMonotonicityCases < numberOfMonotonicityCases
    randomDirection = randn(3,1);
    randomDirection = randomDirection/norm(randomDirection);
    randomRange = 20 + 280*rand;
    randomTarget = randomRange*randomDirection;
    if norm(randomTarget-earthPosition) <= earthRadius
        continue;
    end
    numberAcceptedMonotonicityCases = numberAcceptedMonotonicityCases + 1;
    blockedHistory = false(size(minimumSeparationSweep));
    requiredHistory = zeros(size(minimumSeparationSweep));
    for angleIndex = 1:length(minimumSeparationSweep)
        [~,blockedHistory(angleIndex),~,~,~,requiredHistory(angleIndex)] = ...
            constraints.celestialVisibility( observerPosition, randomTarget, earthPosition, ...
                sunPosition, earthRadius, sunRadius, minimumSeparationSweep(angleIndex));
    end
    blockedIsMonotone = all(diff(double(blockedHistory)) >= 0);
    requiredIsMonotone = all(diff(requiredHistory) >= -angularTolerance);
    if ~blockedIsMonotone || ~requiredIsMonotone
        monotonicityFailures = monotonicityFailures + 1;
    end
end
assert(monotonicityFailures == 0, ...
    "Increasing minimum angular separation produced %d monotonicity failures.", monotonicityFailures);
end

function testTerrainHorizons(~)

%% Test constants
moonRadius = 1737.4;                  % km
maximumTerrainRange = 50;             % km
terrainRangeStep = 0.5;               % km
horizonAzimuthStep = deg2rad(5);      % rad
sensorLatitude = 0;                   % rad
sensorLongitude = pi;                 % rad
candidateLatitudes = sensorLatitude;
candidateLongitudes = sensorLongitude;

%% Construct synthetic DEM grid

% Match equatorial longitude spacing to terrainRangeStep/moonRadius.
angularGridStep = terrainRangeStep / moonRadius;
numberOfGridSteps = ceil(maximumTerrainRange / terrainRangeStep) + 2;
latitudeGrid = (-numberOfGridSteps:numberOfGridSteps).' * angularGridStep;
longitudeGrid = sensorLongitude + (-numberOfGridSteps:numberOfGridSteps).' * angularGridStep;
numberOfLatitudes = numel(latitudeGrid);
numberOfLongitudes = numel(longitudeGrid);

%% Test 1: Constant-elevation spherical surface
flatElevationGrid = zeros( numberOfLatitudes, numberOfLongitudes);
flatDem = griddedInterpolant( {latitudeGrid, longitudeGrid}, flatElevationGrid, "linear", "nearest");
[ flatHorizonAzimuths, flatMaximumTerrainAngles, flatMaximumFeatureRanges, flatSensorElevations, ...
    flatMaximumFeatureElevations ] = digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
    candidateLatitudes, candidateLongitudes, flatDem, maximumTerrainRange, terrainRangeStep, ...
    horizonAzimuthStep, moonRadius);

%% Analytic result for a flat spherical surface

% For equal radii, the horizon angle is -delta/2.
firstCentralAngle = terrainRangeStep / moonRadius;
expectedFlatHorizonAngle = atan2( moonRadius*cos(firstCentralAngle) - moonRadius, ...
    moonRadius*sin(firstCentralAngle));
equivalentFlatHorizonAngle = -firstCentralAngle/2;
angleTolerance = 1e-10;               % rad
rangeTolerance = 1e-10;               % km
elevationTolerance = 1e-10;           % km
assert( abs( expectedFlatHorizonAngle - equivalentFlatHorizonAngle) < angleTolerance, ...
    "The two analytic flat-surface equations do not agree.");
assert( all( abs( flatMaximumTerrainAngles - expectedFlatHorizonAngle) < angleTolerance, "all"), ...
    "The flat-surface terrain horizon angle is incorrect.");
assert( all( abs( flatMaximumFeatureRanges - terrainRangeStep) < rangeTolerance, "all"), ...
    "The flat-surface maximum should occur at the closest range.");
assert( all( abs(flatMaximumFeatureElevations) < elevationTolerance, "all"), ...
    "The flat-surface feature elevation should be zero.");
assert( abs(flatSensorElevations) < elevationTolerance, ...
    "The flat-surface sensor elevation should be zero.");
assert( abs( flatMaximumTerrainAngles(1) - flatMaximumTerrainAngles(end)) < angleTolerance, ...
    "The flat horizon is not periodic at zero and 2*pi.");

%% Test 2: Known synthetic terrain wall
ridgeRange = 20;                      % km
ridgeHeight = 0.2;                    % km
ridgeStartLongitude = sensorLongitude + ridgeRange / moonRadius;
ridgeElevationGrid = zeros( numberOfLatitudes, numberOfLongitudes);

% Construct a north-south wall east of the sensor. The wall begins
% exactly 20 km east and remains at a constant 0.2 km elevation.
ridgeLongitudeMask = longitudeGrid >= ridgeStartLongitude - 1e-12;
ridgeElevationGrid(:, ridgeLongitudeMask) = ridgeHeight;
ridgeDem = griddedInterpolant( {latitudeGrid, longitudeGrid}, ridgeElevationGrid, "linear", "nearest");
[ ridgeHorizonAzimuths, ridgeMaximumTerrainAngles, ridgeMaximumFeatureRanges, ridgeSensorElevations, ...
    ridgeMaximumFeatureElevations ] = digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
    candidateLatitudes, candidateLongitudes, ridgeDem, maximumTerrainRange, terrainRangeStep, ...
    horizonAzimuthStep, moonRadius);

%% Find eastward azimuth
eastAzimuth = deg2rad(90);
[ eastAzimuthDifference, eastAzimuthIndex ] = min(abs(ridgeHorizonAzimuths - eastAzimuth));
assert( eastAzimuthDifference < angleTolerance, ...
    "The horizon azimuth grid does not contain 90 degrees.");
computedRidgeAngle = ridgeMaximumTerrainAngles(eastAzimuthIndex);
computedRidgeRange = ridgeMaximumFeatureRanges(eastAzimuthIndex);
computedRidgeElevation = ridgeMaximumFeatureElevations(eastAzimuthIndex);

%% Analytic ridge result
ridgeCentralAngle = ridgeRange / moonRadius;
expectedRidgeAngle = atan2( (moonRadius + ridgeHeight)*cos(ridgeCentralAngle) - moonRadius, ...
    (moonRadius + ridgeHeight)*sin(ridgeCentralAngle));
assert( abs( computedRidgeAngle - expectedRidgeAngle) < angleTolerance, ...
    "The synthetic-ridge apparent elevation angle is incorrect.");
assert( abs( computedRidgeRange - ridgeRange) < rangeTolerance, ...
    "The synthetic-ridge range is incorrect.");
assert( abs( computedRidgeElevation - ridgeHeight) < elevationTolerance, ...
    "The synthetic-ridge DEM elevation is incorrect.");
assert( abs(ridgeSensorElevations) < elevationTolerance, ...
    "The synthetic-ridge sensor elevation should be zero.");
assert( computedRidgeAngle > expectedFlatHorizonAngle, ...
    "The ridge horizon should exceed the flat-surface horizon.");
assert( abs( ridgeMaximumTerrainAngles(1) - ridgeMaximumTerrainAngles(end)) < angleTolerance, ...
    "The ridge horizon is not periodic at zero and 2*pi.");

%% Verify westward direction remains flat
westAzimuth = deg2rad(270);
[ westAzimuthDifference, westAzimuthIndex ] = min(abs(ridgeHorizonAzimuths - westAzimuth));
assert( westAzimuthDifference < angleTolerance, ...
    "The horizon azimuth grid does not contain 270 degrees.");
computedWestHorizonAngle = ridgeMaximumTerrainAngles(westAzimuthIndex);
assert( abs( computedWestHorizonAngle - expectedFlatHorizonAngle) < angleTolerance, ...
    "The terrain west of the sensor should remain flat.");
end

function testCovarianceAndObjectives(~)

%% Synthetic tracking database
numberOfTimes = 60;
numberOfSensors = 3;
timeStep = 60;                        % s
initialPositionSigma = 2;             % km
initialVelocitySigma = 2e-3;          % km/s
initialCovariance = diag([
    initialPositionSigma^2
    initialPositionSigma^2
    initialPositionSigma^2
    initialVelocitySigma^2
    initialVelocitySigma^2
    initialVelocitySigma^2
]);
accelerationNoiseIntensity = 1e-14;   % km^2/s^3
stateTransitionMatrix = [
    eye(3), timeStep*eye(3)
    zeros(3), eye(3)
];
processNoise = estimation.isotropicProcessNoise( timeStep, accelerationNoiseIntensity);
stateTransitionHistory = repmat( stateTransitionMatrix, 1,1,numberOfTimes);
processNoiseHistory = repmat( processNoise, 1,1,numberOfTimes);

%% Synthetic RA/Dec-like Jacobians
measurementJacobianHistory = zeros(2,6,numberOfSensors,numberOfTimes);
sensorOneJacobian = [
    1e-3,0,0,0,0,0
    0,1e-3,0,0,0,0
];
sensorTwoJacobian = [
    0,1e-3,0,0,0,0
    0,0,1e-3,0,0,0
];
for timeIndex = 1:numberOfTimes
    measurementJacobianHistory( :,:,1,timeIndex) = sensorOneJacobian;
    measurementJacobianHistory( :,:,2,timeIndex) = sensorTwoJacobian;
    % Sensor three has valid geometry but is always blocked by LOS.
    measurementJacobianHistory( :,:,3,timeIndex) = sensorOneJacobian;
end

%% Availability histories
measurementAvailable = false(numberOfSensors,numberOfTimes);

% Sensor one is always available.
measurementAvailable(1,:) = true;

% Sensor two is available at alternating epochs.
measurementAvailable(2,1:2:end) = true;

% Sensor three is never available.
measurementAvailable(3,:) = false;

%% Measurement covariance
angleSigma = 5e-5;                    % rad
singleMeasurementCovariance = diag([
    angleSigma^2
    angleSigma^2
]);
measurementCovariances = repmat( singleMeasurementCovariance, 1,1,numberOfSensors);
stateScales = [
    1
    1
    1
    1e-3
    1e-3
    1e-3
];

%% Candidate networks
noSensors = [
    0
    0
    0
];
sensorOneOnly = [
    1
    0
    0
];
sensorTwoOnly = [
    0
    1
    0
];
bothUsefulSensors = [
    1
    1
    0
];
blockedSensorOnly = [
    0
    0
    1
];

%% Propagate candidate covariances
[covarianceNone,dOptimalityNone] = estimation.propagateNetworkCovariance( initialCovariance, ...
        stateTransitionHistory, processNoiseHistory, measurementJacobianHistory, ...
        measurementAvailable, noSensors, measurementCovariances, stateScales);
[covarianceOne,dOptimalityOne] = estimation.propagateNetworkCovariance( initialCovariance, ...
        stateTransitionHistory, processNoiseHistory, measurementJacobianHistory, ...
        measurementAvailable, sensorOneOnly, measurementCovariances, stateScales);
[covarianceTwo,dOptimalityTwo] = estimation.propagateNetworkCovariance( initialCovariance, ...
        stateTransitionHistory, processNoiseHistory, measurementJacobianHistory, ...
        measurementAvailable, sensorTwoOnly, measurementCovariances, stateScales);
[covarianceBoth,dOptimalityBoth] = estimation.propagateNetworkCovariance( initialCovariance, ...
        stateTransitionHistory, processNoiseHistory, measurementJacobianHistory, ...
        measurementAvailable, bothUsefulSensors, measurementCovariances, stateScales);
[covarianceBlocked,dOptimalityBlocked] = estimation.propagateNetworkCovariance( initialCovariance, ...
        stateTransitionHistory, processNoiseHistory, measurementJacobianHistory, ...
        measurementAvailable, blockedSensorOnly, measurementCovariances, stateScales);

%% Validate covariance behavior
scoreNone = mean(dOptimalityNone);
scoreOne = mean(dOptimalityOne);
scoreTwo = mean(dOptimalityTwo);
scoreBoth = mean(dOptimalityBoth);
scoreBlocked = mean(dOptimalityBlocked);
assert(scoreOne > scoreNone, "A useful sensor did not improve information.");
assert(scoreTwo > scoreNone, "The second useful sensor did not improve information.");
assert(scoreBoth >= max(scoreOne,scoreTwo), ...
    "Two useful sensors performed worse than one useful sensor.");
assert(abs(scoreBlocked - scoreNone) < 1e-10, "A sensor without LOS changed the information score.");
blockedDifference = norm( covarianceBlocked(:) - covarianceNone(:));
assert(blockedDifference < 1e-10, "A sensor without LOS changed the covariance history.");
for timeIndex = 1:numberOfTimes
    covariance = covarianceBoth(:,:,timeIndex);
    symmetryError = norm(covariance - covariance',"fro");
    assert(symmetryError < 1e-10, "Covariance lost symmetry at index %d.", timeIndex);
    [~,positiveDefiniteFlag] = chol(covariance,"lower");
    assert(positiveDefiniteFlag == 0, "Covariance is not positive definite at index %d.", timeIndex);
end

%% Test information objective
initialCovariances = reshape( initialCovariance, 6,6,1);
stateTransitionHistories = reshape( stateTransitionHistory, 6,6,numberOfTimes,1);
processNoiseHistories = reshape( processNoiseHistory, 6,6,numberOfTimes,1);
measurementJacobianHistories = reshape( measurementJacobianHistory, ...
    2,6,numberOfSensors,numberOfTimes,1);
measurementAvailability = reshape( measurementAvailable, numberOfSensors,numberOfTimes,1);
objectWeights = 1;
[objectiveNone,~] = optimization.informationObjective( noSensors, initialCovariances, ...
        stateTransitionHistories, processNoiseHistories, measurementJacobianHistories, ...
        measurementAvailability, measurementCovariances, stateScales, objectWeights);
[objectiveOne,~] = optimization.informationObjective( sensorOneOnly, initialCovariances, ...
        stateTransitionHistories, processNoiseHistories, measurementJacobianHistories, ...
        measurementAvailability, measurementCovariances, stateScales, objectWeights);
[objectiveBoth,~] = optimization.informationObjective( bothUsefulSensors, initialCovariances, ...
        stateTransitionHistories, processNoiseHistories, measurementJacobianHistories, ...
        measurementAvailability, measurementCovariances, stateScales, objectWeights);
assert(objectiveOne < objectiveNone, "The information objective did not prefer a useful sensor.");
assert(objectiveBoth <= objectiveOne, "The information objective did not prefer two useful sensors.");

%% Test coverage objective
[coverageObjectiveNone,coverageNone] = optimization.coverageObjective( noSensors, ...
        measurementAvailability, objectWeights);
[coverageObjectiveOne,coverageOne] = optimization.coverageObjective( sensorOneOnly, ...
        measurementAvailability, objectWeights);
[coverageObjectiveBoth,coverageBoth] = optimization.coverageObjective( bothUsefulSensors, ...
        measurementAvailability, objectWeights);
[coverageObjectiveBlocked,coverageBlocked] = optimization.coverageObjective( blockedSensorOnly, ...
        measurementAvailability, objectWeights);
assert(coverageNone == 0, "No-sensor coverage should be zero.");
assert(coverageBlocked == 0, "A blocked sensor should provide no coverage.");
assert(coverageOne == numberOfTimes, "The always-visible sensor should cover every epoch.");
assert(coverageBoth >= coverageOne, "Adding a sensor reduced coverage.");
assert(coverageObjectiveOne < coverageObjectiveNone, ...
    "The coverage objective did not prefer a useful sensor.");
assert(coverageObjectiveBoth <= coverageObjectiveOne, ...
    "Adding a sensor worsened the coverage objective.");
assert(coverageObjectiveBlocked == coverageObjectiveNone, ...
    "A blocked sensor changed the coverage objective.");
end

function testTrackingPropagation(~)

%% Constants and production time grid
moonRadiusKm = 1737.4;
moonMuKm3S2 = 4902.800066;
trackingStepSeconds = 10*60;
finalTimeSeconds = 3*24*3600;
observationTimes = (trackingStepSeconds:trackingStepSeconds:finalTimeSeconds).';
assert(numel(observationTimes) == 432, ...
    "Three-day production grid must contain 432 optimization epochs.");

%% Representative circular lunar orbit
orbitRadiusKm = moonRadiusKm + 100;
circularSpeedKmS = sqrt(moonMuKm3S2/orbitRadiusKm);
initialState = [ orbitRadiusKm
    0
    0
    0
    circularSpeedKmS
    0
    ];

%% Minimal synthetic DEM and one representative sensor
latitudeGrid = deg2rad([-90,0,90]);
longitudeGrid = deg2rad([0,180,360]);
zeroElevationKm = zeros(3,3);
dem = griddedInterpolant( {latitudeGrid,longitudeGrid}, zeroElevationKm, "linear", "nearest");
candidateLatitudes = deg2rad(-85);
candidateLongitudes = deg2rad(45);

%% Canonical truth propagation
truthTimes = [ 0
    observationTimes
    ];
[propagatedTruthTimes,truthStates] = orbitDynamics.propagateLunarOrbit( initialState, truthTimes, ...
        moonMu=moonMuKm3S2);
assert(max(abs(propagatedTruthTimes-truthTimes)) < 1e-9, "Canonical truth time grid changed.");
truthObservationStates = truthStates(2:end,:).';

%% Tracking / STM precompute
[referenceStates, stateTransitionHistory, processNoiseHistory, measurementJacobianHistory] = ...
    optimization.precomputeTrackingData( 0, observationTimes, initialState, candidateLatitudes, ...
        candidateLongitudes, dem, 0, 1e-15, moonMuKm3S2, moonRadiusKm, 0, 2*pi/(27.321661*86400));

%% Regression checks
maximumReferenceTruthError = max(abs(referenceStates-truthObservationStates),[],"all");
assert(maximumReferenceTruthError < 1e-12, ...
    "Three-day nominal tracking states do not reproduce canonical truth.");
assert(isequal(size(referenceStates),[6,432]), "Reference-state history has unexpected dimensions.");
assert(isequal(size(stateTransitionHistory),[6,6,432]), "STM history has unexpected dimensions.");
assert(isequal(size(processNoiseHistory),[6,6,432]), ...
    "Process-noise history has unexpected dimensions.");
assert(isequal(size(measurementJacobianHistory),[2,6,1,432]), ...
    "Measurement-Jacobian history has unexpected dimensions.");
assert(all(isfinite(referenceStates),"all"), "Reference-state history contains nonfinite values.");
assert(all(isfinite(stateTransitionHistory),"all"), "STM history contains nonfinite values.");
assert(all(isfinite(processNoiseHistory),"all"), "Process-noise history contains nonfinite values.");
assert(all(isfinite(measurementJacobianHistory),"all"), ...
    "Measurement-Jacobian history contains nonfinite values.");
end

function testRsoCatalogsAndPropagation(~)

%% Generation settings
selection = "both";
numberOfGeneratedObjects = 10;
periapsisAltitudeLimitsKm = [50,5000];
inclinationLimitsRad = deg2rad([0,180]);
eccentricityLimits = [0,0.8];
moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2

%% Build selected RSO set
[initialStatesMoonInertial,rsoCatalog] = rsoGeneration.buildRsoSet( selection, ...
        numberOfGeneratedObjects, periapsisAltitudeLimitsKm, inclinationLimitsRad, ...
        eccentricityLimits, moonRadius, moonMu);
numberOfObjects = height(rsoCatalog);

%% Validate wrapper selection
switch selection
    case "operational"
        expectedNumberOfObjects = 4;
    case "generated"
        expectedNumberOfObjects = numberOfGeneratedObjects;
    case "both"
        expectedNumberOfObjects = 4 + numberOfGeneratedObjects;
    otherwise
        error("Unexpected RSO selection.");
end
assert(numberOfObjects == expectedNumberOfObjects, ...
    "The wrapper returned an unexpected number of RSOs.");
assert(size(initialStatesMoonInertial,1) == 6, "The state matrix must have six rows.");
assert(size(initialStatesMoonInertial,2) == numberOfObjects, ...
    "The state matrix and catalog have inconsistent object counts.");
assert(all(isfinite(initialStatesMoonInertial),"all"), ...
    "The generated state matrix contains nonfinite values.");
assert(~any(rsoCatalog.Name == "CAPSTONE"), ...
    "CAPSTONE should be excluded from the current two-body set.");
assert(~any(rsoCatalog.RequiresMultiBodyDynamics), "The current catalog contains a multi-body object.");

%% Recover elements from every initial state
recoveredSemiMajorAxis = zeros(numberOfObjects,1);
recoveredEccentricity = zeros(numberOfObjects,1);
recoveredInclination = zeros(numberOfObjects,1);
recoveredPeriapsisAltitude = zeros(numberOfObjects,1);
recoveredApoapsisAltitude = zeros(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    [recoveredSemiMajorAxis(objectIndex), recoveredEccentricity(objectIndex), ...
        recoveredInclination(objectIndex), recoveredPeriapsisAltitude(objectIndex), ...
        recoveredApoapsisAltitude(objectIndex)] = stateToOrbitGeometry( ...
            initialStatesMoonInertial(:,objectIndex), moonRadius, moonMu);
end
elementTolerance = 1e-7;
angleTolerance = 1e-10;
assert(all(abs( recoveredSemiMajorAxis - rsoCatalog.SemiMajorAxisKm) < elementTolerance), ...
    "A recovered semi-major axis is inconsistent.");
assert(all(abs( recoveredEccentricity - rsoCatalog.Eccentricity) < angleTolerance), ...
    "A recovered eccentricity is inconsistent.");
assert(all(abs( recoveredInclination - rsoCatalog.InclinationRad) < angleTolerance), ...
    "A recovered inclination is inconsistent.");
assert(all(abs( recoveredPeriapsisAltitude - rsoCatalog.PeriapsisAltitudeKm) < elementTolerance), ...
    "A recovered periapsis altitude is inconsistent.");
assert(all(abs( recoveredApoapsisAltitude - rsoCatalog.ApoapsisAltitudeKm) < elementTolerance), ...
    "A recovered apoapsis altitude is inconsistent.");

%% Validate equally spaced generated elements
generatedMask = rsoCatalog.SourceType == "Generated";
if sum(generatedMask) > 2
    assertEvenSpacing( rsoCatalog.PeriapsisAltitudeKm(generatedMask), "generated periapsis altitude");
    assertEvenSpacing( rsoCatalog.InclinationRad(generatedMask), "generated inclination");
    assertEvenSpacing( rsoCatalog.Eccentricity(generatedMask), "generated eccentricity");
end

%% Propagate each object for one period
samplesPerOrbit = 500;
for objectIndex = 1:numberOfObjects
    orbitPeriod = rsoCatalog.PeriodSeconds(objectIndex);
    propagationTimes = linspace( 0, orbitPeriod, samplesPerOrbit + 1).';
    [~,propagatedStates] = orbitDynamics.propagateLunarOrbit( ...
            initialStatesMoonInertial(:,objectIndex), propagationTimes, moonMu=moonMu);
    assert(all(isfinite(propagatedStates),"all"), "Propagation failed for %s.", ...
        char(rsoCatalog.Name(objectIndex)));
    positionHistory = propagatedStates(:,1:3);
    minimumRadius = min( vecnorm(positionHistory,2,2));
    assert(minimumRadius > moonRadius, "%s intersects the lunar reference sphere.", ...
        char(rsoCatalog.Name(objectIndex)));
    closureError = norm( propagatedStates(end,:).' - initialStatesMoonInertial(:,objectIndex));
    assert(closureError < 1e-4, "%s did not close after one two-body period.", ...
        char(rsoCatalog.Name(objectIndex)));
end
end

function [semiMajorAxis,eccentricity,inclination, periapsisAltitude,apoapsisAltitude] = ...
    stateToOrbitGeometry(state,moonRadius,moonMu)
position = state(1:3);
velocity = state(4:6);
radius = norm(position);
speedSquared = dot(velocity,velocity);
specificEnergy = 0.5*speedSquared - moonMu/radius;
assert(specificEnergy < 0, "The generated state is not a bound orbit.");
semiMajorAxis = -moonMu/(2*specificEnergy);
angularMomentum = cross(position,velocity);
angularMomentumMagnitude = norm(angularMomentum);
eccentricityVector = cross(velocity,angularMomentum)/moonMu - position/radius;
eccentricity = norm(eccentricityVector);
inclination = acos(max(-1,min(1, angularMomentum(3)/angularMomentumMagnitude)));
periapsisAltitude = semiMajorAxis*(1 - eccentricity) - moonRadius;
apoapsisAltitude = semiMajorAxis*(1 + eccentricity) - moonRadius;
end

function assertEvenSpacing(values,description)
sortedValues = sort(values);
spacing = diff(sortedValues);
spacingTolerance = 1e-10*max(1,max(abs(sortedValues)));
assert(max(abs(spacing - spacing(1))) < spacingTolerance, "%s levels are not evenly spaced.", ...
    description);
end

function testDemNativeCoverageAndCellEdgePadding(testCase)
folder = string(tempname); mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
file = fullfile(folder,"cell_global.mat");
saveSyntheticDem(file,-85:10:85,5:10:355);
[dem,model] = digitalElevationModel.loadTriaxialLunarDem(file);
verifyEqual(testCase,model.nativeGrid.sampleLatitudeBoundsRad,deg2rad([-85 85]),'AbsTol',1e-12);
verifyEqual(testCase,model.nativeGrid.latitudeCoverageRad,[-pi/2 pi/2],'AbsTol',1e-12);
verifyEqual(testCase,model.rawRasterSize,[18 36]);
verifyEqual(testCase,model.latitudeSpacingDeg,10,'AbsTol',1e-10);
verifyEqual(testCase,dem.GridVectors{1}([1 end]),[-pi/2;pi/2],'AbsTol',1e-12);
report = digitalElevationModel.checkDemCompatibility(model,deg2rad([-89;0;89]), ...
    deg2rad([359;180;1]),struct("candidateSpacingKm",500));
verifyTrue(testCase,report.passed);
verifyEqual(testCase,report.nativeNorthSouthSpacingMeters,1737.4*1000*deg2rad(10),'RelTol',1e-12);
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,0,struct()), ...
    'checkDemCompatibility:ResolutionTooCoarse');
end

function testRegionalDemCannotAcquireMissingLatitudeCoverage(testCase)
folder = string(tempname); mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
file = fullfile(folder,"south.mat");
saveSyntheticDem(file,-90:5:-70,0:10:360);
[dem,model] = digitalElevationModel.loadTriaxialLunarDem(file);
verifyEqual(testCase,model.nativeGrid.latitudeCoverageRad,deg2rad([-90 -70]),'AbsTol',1e-12);
verifyEqual(testCase,dem.GridVectors{1}(end),deg2rad(-70),'AbsTol',1e-12);
verifyTrue(testCase,isnan(dem(0,0))); % No nearest extrapolation into the northern domain.
settings = struct("candidateSpacingKm",500);
report = digitalElevationModel.checkDemCompatibility(model,deg2rad(-80),0,settings);
verifyTrue(testCase,report.passed);
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,0,settings), ...
    'checkDemCompatibility:LatitudeCoverage');
% Candidate is in bounds but its terrain neighborhood crosses the source boundary.
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,deg2rad(-72),0,settings), ...
    'checkDemCompatibility:LatitudeCoverage');
end

function testDemLongitudeSeamAndTerrainMargin(testCase)
% A two-column regional patch must not be classified as full longitude.
grid = digitalElevationModel.describeDemGrid(deg2rad([-20;20]),deg2rad([0;90]));
verifyFalse(testCase,grid.fullLongitude);
folder = string(tempname); mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
file = fullfile(folder,"seam.mat");
saveSyntheticDem(file,-20:5:20,-10:1:10);
[~,model] = digitalElevationModel.loadTriaxialLunarDem(file);
verifyFalse(testCase,model.nativeGrid.fullLongitude);
verifyEqual(testCase,model.nativeGrid.longitudeSpanRad,deg2rad(20),'AbsTol',1e-12);
settings = struct("candidateSpacingKm",500);
report = digitalElevationModel.checkDemCompatibility(model,0,deg2rad(359),settings);
verifyTrue(testCase,report.passed);
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,deg2rad(15),settings), ...
    'checkDemCompatibility:LongitudeCoverage');
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,deg2rad(8),settings), ...
    'checkDemCompatibility:LongitudeCoverage');
file = fullfile(folder,"polar_patch.mat");
saveSyntheticDem(file,-90:1:-80,10:1:30);
[~,model] = digitalElevationModel.loadTriaxialLunarDem(file);
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,deg2rad(-89),deg2rad(20),settings), ...
    'checkDemCompatibility:LongitudeCoverage');
end

function testDemResolutionUsesNativeGapsAndLatitude(testCase)
% Irregular native latitude gaps cannot be hidden by a small median spacing.
model.nativeGrid = digitalElevationModel.describeDemGrid( ...
    deg2rad([-10;-9.99;-9.98;10]),deg2rad((0:1:360).'));
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,0, ...
    struct("candidateSpacingKm",15)), 'checkDemCompatibility:ResolutionTooCoarse');
% The CLPS default is a 25 m limit, independent of a 100 m radius.
model.nativeGrid = digitalElevationModel.describeDemGrid( ...
    deg2rad((-90:1:90).'),deg2rad((0:1:360).'));
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,deg2rad(-80),0, ...
    struct("candidateSpacingKm",0.025)), 'checkDemCompatibility:ResolutionTooCoarse');
% A synthetic fine polar patch passes and reports physical longitudinal convergence.
model.nativeGrid = digitalElevationModel.describeDemGrid( ...
    deg2rad((-86:0.0005:-84).'),deg2rad((15:0.0005:25).'));
report = digitalElevationModel.checkDemCompatibility(model,deg2rad(-85),deg2rad(20), ...
    struct("candidateSpacingKm",0.025,"terrainRangeKm",1));
verifyTrue(testCase,report.passed);
verifyLessThan(testCase,report.nativeMaximumEastWestSpacingMeters,report.nativeNorthSouthSpacingMeters);
verifyFalse(testCase,report.flatnessCertified);
end

function testDemPreflightCreatesNoDatabaseOrChunks(testCase)
folder = string(tempname); mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
file = fullfile(folder,"south.mat");
saveSyntheticDem(file,-90:5:-65,0:10:360);
outputRoot = fullfile(folder,"output");
options = struct("demFile",file,"outputRoot",outputRoot, ...
    "spacingKm",500,"preflightOnly",true);
buildDomainDatabase("south75",options);
verifyFalse(testCase,isfolder(outputRoot));
verifyError(testCase,@()buildDomainDatabase("global",options), ...
    'checkDemCompatibility:LatitudeCoverage');
verifyFalse(testCase,isfolder(outputRoot));
% The real build path must reject incompatible input before creating any request/chunk files.
options.preflightOnly = false;
verifyError(testCase,@()buildDomainDatabase("global",options), ...
    'checkDemCompatibility:LatitudeCoverage');
verifyFalse(testCase,isfolder(outputRoot));
end

function saveSyntheticDem(file,latitudeDeg,longitudeDeg)
DEM = griddedInterpolant({deg2rad(latitudeDeg(:)),deg2rad(longitudeDeg(:))}, ...
    zeros(numel(latitudeDeg),numel(longitudeDeg)),"linear","nearest");
save(file,"DEM","-v7.3");
end

function testDemOptionalToleranceFromLauncherJson(testCase)
model.nativeGrid = digitalElevationModel.describeDemGrid( ...
    deg2rad((-90:1:90).'),deg2rad((0:1:360).'));
requests = {jsondecode('{"candidateSpacingKm":500}'), ...
    jsondecode('{"candidateSpacingKm":500,"maximumDemSpacingMeters":null}'), ...
    jsondecode('{"candidateSpacingKm":500,"maximumDemSpacingMeters":[]}'), ...
    struct("candidateSpacingKm",500,"maximumDemSpacingMeters",struct())};
for k = 1:numel(requests)
    report = digitalElevationModel.checkDemCompatibility(model,0,0,requests{k});
    verifyEqual(testCase,report.maximumAllowedSpacingMeters,500000);
end
explicit = jsondecode('{"candidateSpacingKm":500,"maximumDemSpacingMeters":40000}');
report = digitalElevationModel.checkDemCompatibility(model,0,0,explicit);
verifyEqual(testCase,report.maximumAllowedSpacingMeters,40000);
explicit.maximumDemSpacingMeters = 1000;
verifyError(testCase,@()digitalElevationModel.checkDemCompatibility(model,0,0,explicit), ...
    'checkDemCompatibility:ResolutionTooCoarse');
end

function testSelectedJacobiansMatchScalarModel(testCase)
dem = griddedInterpolant({[-pi/2;0;pi/2],[0;pi;2*pi]},zeros(3));
db.config.moon = struct("radiusKm",1737.4,"theta0Rad",0.4,"siderealPeriodSeconds",27.321661*86400);
db.candidates.latitudesRad = deg2rad([-85;20]);
db.candidates.longitudesRad = deg2rad([359;45]);
db.candidates.sensorElevationsKm = [0;0];
db.tracking.times = [600;1200;3600];
db.tracking.referenceStateHistories = repmat([2000;300;600;0;1;0],1,3,2);
db.meta.numberOfObjects = 2; db.meta.numberOfCandidates = 2;
db.meta.measurementJacobianStorage = "on_demand";
actual = optimization.loadChunkedCandidateData(db,[2;1],"measurementJacobianHistories");
expected = zeros(2,6,2,3,2);
for object = 1:2
    for t = 1:3
        for sensor = 1:2
            id = 3-sensor;
            expected(:,:,sensor,t,object) = measurements.surfaceRaDecJacobian( ...
                db.tracking.referenceStateHistories(:,t,object),db.tracking.times(t), ...
                db.candidates.latitudesRad(id),db.candidates.longitudesRad(id),dem,1737.4,0.4, ...
                2*pi/db.config.moon.siderealPeriodSeconds);
        end
    end
end
verifyEqual(testCase,actual,expected(:,1:3,:,:,:),'AbsTol',1e-15);
prior = repmat(eye(6),1,1,2); phi = repmat(eye(6),1,1,3,2); q = zeros(6,6,3,2);
mask = true(2,3,2);
a = optimization.informationObjective(true(2,1),prior,phi,q,actual,mask,eye(2),ones(6,1),ones(2,1));
b = optimization.informationObjective(true(2,1),prior,phi,q,expected,mask,eye(2),ones(6,1),ones(2,1));
verifyEqual(testCase,a,b,'AbsTol',1e-12);
end

function testLocalFlatnessResolvedAndUnresolved(testCase)
lat = deg2rad((-.001:.00001:.001).'); lon = deg2rad((10-.001:.00001:10+.001).');
model.nativeGrid = digitalElevationModel.describeDemGrid(lat,lon);
% A plane with 3 degree north/south slope, in radial-height km.
h = repmat(1737.4*tan(deg2rad(3))*lat,1,numel(lon));
dem = griddedInterpolant({lat,lon},h,"linear","none");
report = digitalElevationModel.evaluateLocalFlatness(dem,model,0,deg2rad(10));
verifyEqual(testCase,report.status,"pass");
verifyEqual(testCase,report.slopeDeg,3,'AbsTol',1e-5);
report = digitalElevationModel.evaluateLocalFlatness(dem,model,0,deg2rad(10),struct("maximumSlopeDeg",2));
verifyEqual(testCase,report.status,"fail");
model.nativeGrid = digitalElevationModel.describeDemGrid(deg2rad((-90:1:90).'),deg2rad((0:1:360).'));
report = digitalElevationModel.evaluateLocalFlatness(dem,model,0,deg2rad(10));
verifyEqual(testCase,report.status,"unresolved");
verifyTrue(testCase,isnan(report.slopeDeg));
end

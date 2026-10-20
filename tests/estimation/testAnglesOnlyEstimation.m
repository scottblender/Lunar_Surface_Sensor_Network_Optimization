function tests = testAnglesOnlyEstimation
% TESTANGLESONLYESTIMATION - Verify angles-only IOD, finite-difference Jacobians, and EKF updates.
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

function testIodAndEkf(testCase)
projectRoot = testCase.TestData.root;
dataDirectory = fullfile(projectRoot,"data");
resultsDirectory = fullfile(projectRoot,"results");
rng(4,"twister");
file = string(getenv("LUNAR_TEST_DEM_FILE"));
if strlength(file)==0, file=fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat"); end
[dem,~] = digitalElevationModel.loadTriaxialLunarDem(file);

%% Lunar constants
moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2
moonSiderealPeriod = 27.321661*86400;                  % s
moonAngularRate = 2*pi/moonSiderealPeriod;          % rad/s
theta0 = 0;                           % rad

%% LRO-like truth orbit
orbitAltitude = 50;                   % km
orbitRadius = moonRadius + orbitAltitude;
orbitInclination = deg2rad(90);       % rad
sensorLatitude = deg2rad(-84);        % rad
sensorLongitude = deg2rad(37);        % rad
rightAscensionAscendingNode = sensorLongitude;
rotationZ = [
     cos(rightAscensionAscendingNode), -sin(rightAscensionAscendingNode), 0
     sin(rightAscensionAscendingNode), cos(rightAscensionAscendingNode), 0
     0,0,1
];
rotationX = [
    1,0,0
    0,cos(orbitInclination),-sin(orbitInclination)
    0,sin(orbitInclination), cos(orbitInclination)
];
perifocalToMci = rotationZ*rotationX;
circularSpeed = sqrt(moonMu/orbitRadius);
truthInitialPosition = perifocalToMci*[orbitRadius;0;0];
truthInitialVelocity = perifocalToMci*[0;circularSpeed;0];
truthInitialState = [
    truthInitialPosition
    truthInitialVelocity
];
orbitPeriod = 2*pi*sqrt(orbitRadius^3/moonMu);
numberOfPeriods = 3;
outputStep = 20;                      % s
finalTime = numberOfPeriods*orbitPeriod;
timeSpan = (0:outputStep:finalTime).';
if timeSpan(end) < finalTime
    timeSpan(end+1,1) = finalTime;
end

%% Propagate truth in MCI
[times,statesMoonInertial] = orbitDynamics.propagateLunarOrbit( truthInitialState, timeSpan, ...
        moonMu=moonMu);
numberOfObservations = length(times);

% Use a 6xN state-history convention.
truthStateHistory = statesMoonInertial.';

%% Sensor state in the Moon-rotating frame

% A zero topographic state corresponds to the sensor origin. The
% topographic conversion uses the DEM elevation at the sensor location.
sensorStateTopographic = zeros(6,1);
sensorStateMoonRotating = referenceFrames.topographic( sensorStateTopographic, sensorLatitude, ...
        sensorLongitude, dem, moonRadius, "toRotating");

%% Sensor position and geometric availability
observerPositionsMci = zeros(numberOfObservations,3);
measurementAvailable = false(numberOfObservations,1);
topographicElevation = zeros(numberOfObservations,1);
minimumSensorElevation = deg2rad(0);
for observationIndex = 1:numberOfObservations
    observationTime = times(observationIndex);
    truthStateMci = truthStateHistory(:,observationIndex);
    truthStateMoonRotating = referenceFrames.moonRotating( truthStateMci, observationTime, theta0, ...
            moonAngularRate, "fromInertial");
    sensorStateMci = referenceFrames.moonRotating( sensorStateMoonRotating, observationTime, theta0, ...
            moonAngularRate, "toInertial");
    observerPositionsMci(observationIndex,:) = sensorStateMci(1:3).';
    [~,topographicMeasurement] = referenceFrames.topographic( truthStateMoonRotating, ...
            sensorLatitude, sensorLongitude, dem, moonRadius, "fromRotating");
    topographicElevation(observationIndex) = topographicMeasurement(2);
    measurementAvailable(observationIndex) = topographicElevation(observationIndex) >= ...
        minimumSensorElevation;
end
numberOfAvailableMeasurements = sum(measurementAvailable);
assert(numberOfAvailableMeasurements >= 3, "Fewer than three measurements are available.");

%% Measurement noise
rightAscensionSigma = deg2rad(1/3600);                  % 1 arcsecond
declinationSigma = deg2rad(1/3600);                  % 1 arcsecond
measurementCovariance = diag([
    rightAscensionSigma^2
    declinationSigma^2
]);
measurementNoiseFactor = chol(measurementCovariance,"lower");

%% Generate noisy RA/Dec measurements
rightAscension = NaN(numberOfObservations,1);
declination = NaN(numberOfObservations,1);
for observationIndex = 1:numberOfObservations
    if ~measurementAvailable(observationIndex)
        continue
    end
    idealMeasurement = measurements.surfaceRaDecMeasurement( truthStateHistory(:,observationIndex), ...
            times(observationIndex), sensorLatitude, sensorLongitude, dem, moonRadius, theta0, ...
            moonAngularRate);
    measurementNoise = measurementNoiseFactor*randn(2,1);
    noisyMeasurement = idealMeasurement + measurementNoise;
    noisyMeasurement(1) = wrapAngle(noisyMeasurement(1));
    rightAscension(observationIndex) = noisyMeasurement(1);
    declination(observationIndex) = noisyMeasurement(2);
end

%% Verify the surface RA/Dec Jacobian
firstAvailableIndex = find(measurementAvailable,1,"first");
jacobianTestState = truthStateHistory(:,firstAvailableIndex);
jacobianTestTime = times(firstAvailableIndex);
analyticalJacobian = measurements.surfaceRaDecJacobian( jacobianTestState, jacobianTestTime, ...
        sensorLatitude, sensorLongitude, dem, moonRadius, theta0, moonAngularRate);
finiteDifferenceJacobian = finiteDifferenceSurfaceRaDecJacobian( jacobianTestState, ...
        jacobianTestTime, sensorLatitude, sensorLongitude, dem, moonRadius, theta0, moonAngularRate);
jacobianRelativeError = norm( analyticalJacobian - finiteDifferenceJacobian, "fro") / ...
    max(norm(finiteDifferenceJacobian,"fro"),eps);
assert(jacobianRelativeError < 1e-5, "RA/Dec Jacobian relative error is %.3e.", jacobianRelativeError);

%% Select the first continuous LOS pass for IOD
availableIndices = find(measurementAvailable);
firstGapLocation = find(diff(availableIndices) > 1,1,"first");
if isempty(firstGapLocation)
    firstPassIndices = availableIndices;
else
    firstPassIndices = availableIndices(1:firstGapLocation);
end
assert(length(firstPassIndices) >= 3, "The first LOS pass has fewer than three observations.");

% Spread the IOD measurements across the complete first pass.
desiredIodObservationCount = 15;
numberOfIodObservations = min( desiredIodObservationCount, length(firstPassIndices));
selectionLocations = unique(round(linspace( 1, length(firstPassIndices), numberOfIodObservations)));
acquisitionIndices = firstPassIndices(selectionLocations);
acquisitionIndices = acquisitionIndices(:);
assert(length(acquisitionIndices) >= 3, "IOD requires at least three acquisition observations.");

%% Run angles-only IOD and determine P0 by Monte Carlo

% Use a smaller value while debugging. Increase this to 500 or more for
% production covariance estimation.
numberOfMonteCarloSamples = 100;
iodRandomSeed = 21;
[initialStateEstimate,initialCovariance, iodReferenceTime,iodDiagnostics] = iod.anglesOnlyIod( ...
        times, rightAscension, declination, observerPositionsMci, acquisitionIndices, ...
        measurementCovariance, numberOfMonteCarloSamples, iodRandomSeed, moonMu);
initialCovariance = 0.5*(initialCovariance + initialCovariance');
iodReferenceIndex = acquisitionIndices(end);
assert(abs(times(iodReferenceIndex) - iodReferenceTime) < 1e-9, ...
    "IOD reference epoch does not match the acquisition endpoint.");
[~,initialCovarianceFlag] = chol(initialCovariance,"lower");
assert(initialCovarianceFlag == 0, "The Monte Carlo IOD covariance is not positive definite.");

%% Run the EKF after the IOD acquisition arc

% Measurements used by IOD are not used again by the EKF.
ekfIndices = find(times > iodReferenceTime);
assert(~isempty(ekfIndices), "No propagation time remains after the IOD arc.");
ekfTimes = times(ekfIndices);
ekfRightAscension = rightAscension(ekfIndices);
ekfDeclination = declination(ekfIndices);
ekfMeasurementAvailable = measurementAvailable(ekfIndices);
ekfSensorLatitudes = repmat(sensorLatitude,length(ekfIndices),1);
ekfSensorLongitudes = repmat(sensorLongitude,length(ekfIndices),1);

% Continuous white-acceleration process-noise intensity.
accelerationNoiseIntensity = 1e-15;   % km^2/s^3
[stateEstimateHistory,covarianceHistory, innovationHistory,measurementInformationHistory] = ...
    estimation.lunarSurfaceEkf( iodReferenceTime, ekfTimes, ekfRightAscension, ekfDeclination, ...
        ekfSensorLatitudes, ekfSensorLongitudes, dem, ekfMeasurementAvailable, initialStateEstimate, ...
        initialCovariance, measurementCovariance, accelerationNoiseIntensity, moonMu, moonRadius, ...
        theta0, moonAngularRate);

%% Include the IOD result as the first filter point
filterTimes = [
    iodReferenceTime
    ekfTimes
];
filterTruthIndices = [
    iodReferenceIndex
    ekfIndices
];
filterTruthStateHistory = truthStateHistory(:,filterTruthIndices);
stateEstimateHistory = [
    initialStateEstimate, stateEstimateHistory
];
covarianceHistory = cat( 3, initialCovariance, covarianceHistory);
innovationHistory = [
    NaN(2,1), innovationHistory
];
numberOfFilterPoints = length(filterTimes);

%% Estimation errors
stateError = stateEstimateHistory - filterTruthStateHistory;
positionErrorNorm = vecnorm(stateError(1:3,:),2,1);
velocityErrorNorm = vecnorm(stateError(4:6,:),2,1);
positionThreeSigmaNorm = zeros(numberOfFilterPoints,1);
velocityThreeSigmaNorm = zeros(numberOfFilterPoints,1);
dOptimalityHistory = zeros(numberOfFilterPoints,1);

% Nondimensionalization scales used only for log-determinant evaluation.
stateScales = [
    1
    1
    1
    1e-3
    1e-3
    1e-3
];
normalizationMatrix = diag(1./stateScales);
for timeIndex = 1:numberOfFilterPoints
    covariance = covarianceHistory(:,:,timeIndex);
    covariance = 0.5*(covariance + covariance');
    positionThreeSigmaNorm(timeIndex) = 3*sqrt(trace(covariance(1:3,1:3)));
    velocityThreeSigmaNorm(timeIndex) = 3*sqrt(trace(covariance(4:6,4:6)));
    normalizedCovariance = normalizationMatrix * covariance * normalizationMatrix';
    normalizedCovariance = 0.5*(normalizedCovariance + normalizedCovariance');
    [covarianceFactor,cholFlag] = chol(normalizedCovariance,"lower");
    assert(cholFlag == 0, "Covariance is not positive definite at index %d.", timeIndex);
    logDetCovariance = 2*sum(log(diag(covarianceFactor)));
    % log(det(information)) = -log(det(covariance)).
    dOptimalityHistory(timeIndex) = -logDetCovariance;
end

%% Validate results
assert(all(isfinite(stateEstimateHistory),"all"), "State history contains nonfinite values.");
assert(all(isfinite(covarianceHistory),"all"), "Covariance history contains nonfinite values.");
for timeIndex = 1:numberOfFilterPoints
    covariance = covarianceHistory(:,:,timeIndex);
    covarianceSymmetryError = norm(covariance - covariance',"fro");
    assert(covarianceSymmetryError < 1e-8, "Covariance lost symmetry at index %d.", timeIndex);
end
availableInnovationIndices = all(isfinite(innovationHistory),1);
assert(any(availableInnovationIndices), "The EKF performed no measurement updates after IOD.");
initialTruthState = truthStateHistory(:,iodReferenceIndex);
initialPositionError = norm( initialStateEstimate(1:3) - initialTruthState(1:3));
initialVelocityError = norm( initialStateEstimate(4:6) - initialTruthState(4:6));
finalPositionError = positionErrorNorm(end);
finalVelocityError = velocityErrorNorm(end);
fprintf("IOD observations: %d\n", length(acquisitionIndices));
fprintf("IOD Monte Carlo success: %d of %d samples\n", iodDiagnostics.numberOfSuccessfulSamples, ...
    iodDiagnostics.numberOfRequestedSamples);
fprintf("IOD reference time: %.6f hr\n", iodReferenceTime/3600);
fprintf("Measurement Jacobian relative error: %.3e\n", jacobianRelativeError);
fprintf("IOD position error: %.6f km\n", initialPositionError);
fprintf("IOD velocity error: %.6e km/s\n", initialVelocityError);
fprintf("Final EKF position error: %.6f km\n", finalPositionError);
fprintf("Final EKF velocity error: %.6e km/s\n", finalVelocityError);
end

function wrappedAngle = wrapAngle(angle)
wrappedAngle = atan2( sin(angle), cos(angle));
end

function finiteDifferenceJacobian = finiteDifferenceSurfaceRaDecJacobian( state, time, latitude, ...
        longitude, dem, moonRadius, theta0, angularRate)
numberOfStates = length(state);
finiteDifferenceJacobian = zeros(2,numberOfStates);
perturbationSizes = [
    1e-3
    1e-3
    1e-3
    1e-6
    1e-6
    1e-6
];
for stateIndex = 1:numberOfStates
    statePerturbation = zeros(numberOfStates,1);
    statePerturbation(stateIndex) = perturbationSizes(stateIndex);
    measurementPlus = measurements.surfaceRaDecMeasurement( state + statePerturbation, time, ...
            latitude, longitude, dem, moonRadius, theta0, angularRate);
    measurementMinus = measurements.surfaceRaDecMeasurement( state - statePerturbation, time, ...
            latitude, longitude, dem, moonRadius, theta0, angularRate);
    measurementDifference = measurementPlus - measurementMinus;
    measurementDifference(1) = wrapAngle(measurementDifference(1));
    finiteDifferenceJacobian(:,stateIndex) = measurementDifference / (2*perturbationSizes(stateIndex));
end
end

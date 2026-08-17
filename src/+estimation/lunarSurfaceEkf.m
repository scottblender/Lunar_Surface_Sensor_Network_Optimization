function [stateHistory, covarianceHistory, innovationHistory, measurementInformationHistory] = lunarAnglesOnlyEkf(initialTime, observationTimes, rightAscension, declination, observerPositionsMci, measurementAvailable, initialState, initialCovariance, measurementCovariance, accelerationNoiseIntensity, moonMu)
% LUNARANGLESONLYEKF Run an RA/Dec EKF in the MCI frame.
%
% Inputs:
%   initialTime                - Epoch associated with x0 and P0, s
%   observationTimes           - Nx1 scheduled observation times, s
%   rightAscension             - Nx1 right ascension measurements, rad
%   declination                - Nx1 declination measurements, rad
%   observerPositionsMci       - Nx3 observer positions in MCI, km
%   measurementAvailable       - Nx1 LOS availability gate
%   initialState               - 6x1 initial MCI state
%   initialCovariance          - 6x6 initial covariance, P0
%   measurementCovariance      - 2x2 RA/Dec covariance, rad^2
%   accelerationNoiseIntensity - Acceleration noise PSD, km^2/s^3
%   moonMu                     - Lunar gravitational parameter, km^3/s^2
%
% Outputs:
%   stateHistory                 - 6xN posterior state history
%   covarianceHistory            - 6x6xN posterior covariance history
%   innovationHistory            - 2xN innovation history
%   measurementInformationHistory- 6x6xN H'*R^(-1)*H history

arguments
    initialTime (1,1) double
    observationTimes (:,1) double
    rightAscension (:,1) double
    declination (:,1) double
    observerPositionsMci (:,3) double
    measurementAvailable (:,1) logical
    initialState (6,1) double
    initialCovariance (6,6) double
    measurementCovariance (2,2) double
    accelerationNoiseIntensity (1,1) double {mustBeNonnegative}
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

numberOfObservations = length(observationTimes);

if length(rightAscension) ~= numberOfObservations || ...
        length(declination) ~= numberOfObservations || ...
        size(observerPositionsMci,1) ~= numberOfObservations || ...
        length(measurementAvailable) ~= numberOfObservations

    error("lunarAnglesOnlyEkf:InvalidDimensions", ...
        "All observation arrays must contain the same number of rows.");
end

if any(diff(observationTimes) < 0)
    error("lunarAnglesOnlyEkf:InvalidTimes", ...
        "observationTimes must be nondecreasing.");
end

if ~isempty(observationTimes) && ...
        observationTimes(1) < initialTime

    error("lunarAnglesOnlyEkf:InvalidInitialTime", ...
        "An observation occurs before initialTime.");
end

chol(measurementCovariance,"lower");

stateHistory = zeros(6,numberOfObservations);
covarianceHistory = zeros(6,6,numberOfObservations);
innovationHistory = NaN(2,numberOfObservations);
measurementInformationHistory = ...
    zeros(6,6,numberOfObservations);

currentTime = initialTime;
currentState = initialState;
currentCovariance = initialCovariance;

identityMatrix = eye(6);

odeOptions = odeset( ...
    "RelTol",1e-11, ...
    "AbsTol",1e-12);

for observationIndex = 1:numberOfObservations

    observationTime = observationTimes(observationIndex);
    deltaTime = observationTime - currentTime;

    %% EKF prediction

    if deltaTime > 0

        augmentedInitialState = [ ...
            currentState;
            reshape(identityMatrix,36,1)];

        [~,augmentedHistory] = ode45( ...
            @(time,augmentedState) ...
                orbitDynamics.lunarStateAndStmDynamics( ...
                    time,augmentedState,moonMu), ...
            [currentTime,observationTime], ...
            augmentedInitialState, ...
            odeOptions);

        augmentedFinalState = augmentedHistory(end,:).';

        predictedState = augmentedFinalState(1:6);

        stateTransitionMatrix = reshape( ...
            augmentedFinalState(7:end),6,6);

        processNoise = estimation.isotropicProcessNoise( ...
            deltaTime,accelerationNoiseIntensity);

        predictedCovariance = ...
            stateTransitionMatrix * currentCovariance * ...
            stateTransitionMatrix' + processNoise;
    else
        predictedState = currentState;
        predictedCovariance = currentCovariance;
    end

    predictedCovariance = ...
        0.5*(predictedCovariance + predictedCovariance');

    %% LOS-gated measurement update

    if measurementAvailable(observationIndex)

        if ~isfinite(rightAscension(observationIndex)) || ...
                ~isfinite(declination(observationIndex))

            error("lunarAnglesOnlyEkf:MissingMeasurement", ...
                "An available observation has nonfinite RA or Dec.");
        end

        observerPosition = ...
            observerPositionsMci(observationIndex,:).';

        predictedMeasurement = ...
            measurements.raDecMeasurement( ...
                predictedState,observerPosition);

        measurementJacobian = ...
            measurements.raDecMeasurementJacobian( ...
                predictedState,observerPosition);

        measuredAngles = [ ...
            rightAscension(observationIndex);
            declination(observationIndex)];

        innovation = measuredAngles - predictedMeasurement;

        innovation(1) = atan2( ...
            sin(innovation(1)), ...
            cos(innovation(1)));

        innovationCovariance = ...
            measurementJacobian * predictedCovariance * ...
            measurementJacobian' + measurementCovariance;

        kalmanGain = ...
            (predictedCovariance * measurementJacobian') / ...
            innovationCovariance;

        updatedState = ...
            predictedState + kalmanGain*innovation;

        covarianceFactor = ...
            identityMatrix - kalmanGain*measurementJacobian;

        updatedCovariance = ...
            covarianceFactor * predictedCovariance * ...
            covarianceFactor' + ...
            kalmanGain * measurementCovariance * kalmanGain';

        measurementInformation = ...
            measurementJacobian' * ...
            (measurementCovariance \ measurementJacobian);

        innovationHistory(:,observationIndex) = innovation;

        measurementInformationHistory(:,:,observationIndex) = ...
            measurementInformation;
    else
        updatedState = predictedState;
        updatedCovariance = predictedCovariance;
    end

    updatedCovariance = ...
        0.5*(updatedCovariance + updatedCovariance');

    stateHistory(:,observationIndex) = updatedState;
    covarianceHistory(:,:,observationIndex) = updatedCovariance;

    currentTime = observationTime;
    currentState = updatedState;
    currentCovariance = updatedCovariance;
end

end
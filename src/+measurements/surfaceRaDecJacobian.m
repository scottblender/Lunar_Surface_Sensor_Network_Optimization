function measurementJacobian = surfaceRaDecJacobian( ...
    state, time, latitude, longitude, dem, ...
    moonRadius, theta0, angularRate)
% SURFACERADECJACOBIAN Jacobian of topocentric RA/Dec.
%
% Inputs:
%   state       - 6x1 target state in MCI, km and km/s
%   time        - Time from the simulation start, s
%   latitude    - Sensor latitude, rad
%   longitude   - East-positive sensor longitude, rad
%   dem         - Processed lunar griddedInterpolant
%   moonRadius  - Lunar reference radius, km
%   theta0      - Moon rotation angle at time = 0, rad
%   angularRate - Lunar rotation rate, rad/s
%
% Output:
%   measurementJacobian - 2x6 Jacobian d[RA;Dec]/dstate

arguments
    state (6,1) double
    time (1,1) double
    latitude (1,1) double
    longitude (1,1) double
    dem (1,1) griddedInterpolant
    moonRadius (1,1) double {mustBePositive} = 1737.4
    theta0 (1,1) double = 0
    angularRate (1,1) double = 2*pi/(27.321661*86400)
end

%% Sensor state in the Moon-rotating frame

sensorTopographicState = zeros(6,1);

sensorMoonRotatingState = referenceFrames.topographic( ...
    sensorTopographicState, latitude, longitude, ...
    dem, moonRadius, "toRotating");

%% Sensor state in the Moon-centered inertial frame

sensorMciState = referenceFrames.moonRotating( ...
    sensorMoonRotatingState, time, theta0, ...
    angularRate, "toInertial");

%% Topocentric line of sight in MCI

targetPosition = state(1:3);
sensorPosition = sensorMciState(1:3);

relativePosition = targetPosition - sensorPosition;

xPosition = relativePosition(1);
yPosition = relativePosition(2);
zPosition = relativePosition(3);

horizontalRange = hypot(xPosition, yPosition);
slantRange = norm(relativePosition);

if slantRange == 0
    error("The target position cannot equal the sensor position.");
end

if horizontalRange == 0
    error("Right ascension is undefined at declination +/- pi/2.");
end

horizontalRangeSquared = horizontalRange^2;
slantRangeSquared = slantRange^2;

%% RA/Dec derivatives with respect to MCI position

rightAscensionPositionJacobian = [
    -yPosition/horizontalRangeSquared, ...
     xPosition/horizontalRangeSquared, ...
     0
];

declinationPositionJacobian = [
    -xPosition*zPosition / ...
        (slantRangeSquared*horizontalRange), ...
    -yPosition*zPosition / ...
        (slantRangeSquared*horizontalRange), ...
     horizontalRange/slantRangeSquared
];

% Instantaneous angle measurements have no direct velocity dependence.
measurementJacobian = [
    rightAscensionPositionJacobian, zeros(1,3)
    declinationPositionJacobian,    zeros(1,3)
];

end
function measurement = surfaceRaDecMeasurement( ...
    state, time, latitude, longitude, dem, ...
    moonRadius, theta0, angularRate)
% SURFACERADECMEASUREMENT Topocentric RA/Dec measurement.
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
%   measurement - [right ascension; declination], rad
%
% Angle conventions:
%   Right ascension - Measured from the MCI +X axis toward +Y,
%                     returned in [0, 2*pi)
%   Declination     - Measured from the MCI XY plane toward +Z,
%                     returned in [-pi/2, pi/2]

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

%% Right ascension and declination

rightAscension = mod( ...
    atan2(yPosition, xPosition), ...
    2*pi);

declination = atan2( ...
    zPosition, horizontalRange);

measurement = [
    rightAscension
    declination
];

end
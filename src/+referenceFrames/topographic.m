function [stateOut, measurement] = topographic( ...
    stateIn, latitude, longitude, dem, moonRadius, direction)
%TOPOGRAPHIC Convert between Moon rotating and local ENU coordinates.
%
% Local axes:
%   +X: East
%   +Y: North
%   +Z: Up
%
% DEM requirement:
%   elevation = dem(latitude, longitude)
%
%   latitude and longitude must be in radians.
%   elevation and moonRadius must be in kilometers.
%
% Inputs:
%   stateIn    - 6x1 input state, km and km/s
%   latitude   - Sensor latitude, rad
%   longitude  - East-positive sensor longitude, rad
%   dem        - Processed griddedInterpolant
%   moonRadius - Lunar reference radius, km
%   direction  - "fromRotating" or "toRotating"
%
% Outputs:
%   stateOut    - 6x1 transformed state
%   measurement - [azimuth; elevation; range; rangeRate]
%
% A sensor fixed to the lunar surface has zero velocity in the
% Moon-rotating frame.

surfaceElevation = dem(latitude, longitude);
sensorRadius = moonRadius + surfaceElevation;

% Local Up axis expressed in Moon-rotating coordinates.
up = [
    cos(latitude)*cos(longitude)
    cos(latitude)*sin(longitude)
    sin(latitude)
];

% Local East axis expressed in Moon-rotating coordinates.
east = [
    -sin(longitude)
     cos(longitude)
     0
];

% Local North axis expressed in Moon-rotating coordinates.
north = [
    -sin(latitude)*cos(longitude)
    -sin(latitude)*sin(longitude)
     cos(latitude)
];

sensorPosition = sensorRadius * up;

% Direction-cosine matrix from Moon rotating to ENU.
rotatingToTopographic = [
    east.'
    north.'
    up.'
];

positionIn = stateIn(1:3);
velocityIn = stateIn(4:6);

switch direction

    case "fromRotating"

        relativePosition = ...
            positionIn - sensorPosition;

        positionOut = ...
            rotatingToTopographic * relativePosition;

        velocityOut = ...
            rotatingToTopographic * velocityIn;

        eastPosition = positionOut(1);
        northPosition = positionOut(2);
        upPosition = positionOut(3);

        range = norm(positionOut);

        azimuth = mod( ...
            atan2(eastPosition, northPosition), ...
            2*pi);

        elevation = atan2( ...
            upPosition, ...
            hypot(eastPosition, northPosition));

        if range > 0
            rangeRate = ...
                dot(positionOut, velocityOut) / range;
        else
            rangeRate = 0;
        end

        measurement = [
            azimuth
            elevation
            range
            rangeRate
        ];

    case "toRotating"

        topographicToRotating = ...
            rotatingToTopographic.';

        positionOut = ...
            sensorPosition ...
            + topographicToRotating * positionIn;

        velocityOut = ...
            topographicToRotating * velocityIn;

        measurement = [];

    otherwise

        error("Direction must be ""fromRotating"" or ""toRotating"".");
end

stateOut = [
    positionOut
    velocityOut
];
end
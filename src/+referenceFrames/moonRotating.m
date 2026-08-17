function stateOut = moonRotating( ...
    stateIn, time, theta0, angularRate, direction)
%MOONROTATING Convert between Moon inertial and Moon rotating frames.
%
% Axes:
%   Origin: Moon center
%   +Z:     Lunar rotation axis
%   +X:     Rotates with the Moon; zero longitude
%   +Y:     Completes the right-handed frame
%
% Rotation model:
%   theta(t) = theta0 + angularRate*time
%
% Inputs:
%   stateIn     - 6x1 input state, km and km/s
%   time        - Time from the simulation start, s
%   theta0      - Rotation angle at time = 0, rad
%   angularRate - Lunar rotation rate, rad/s
%   direction   - "fromInertial" or "toInertial"
%
% Output:
%   stateOut - 6x1 transformed state

theta = theta0 + angularRate*time;

cosineTheta = cos(theta);
sineTheta = sin(theta);

% Direction-cosine matrix from MCI to Moon rotating.
inertialToRotating = [
     cosineTheta,  sineTheta, 0
    -sineTheta,    cosineTheta, 0
     0,            0,           1
];

omega = [0; 0; angularRate];

positionIn = stateIn(1:3);
velocityIn = stateIn(4:6);

switch direction

    case "fromInertial"

        positionOut = ...
            inertialToRotating * positionIn;

        velocityOut = ...
            inertialToRotating * velocityIn ...
            - cross(omega, positionOut);

    case "toInertial"

        rotatingToInertial = inertialToRotating.';

        positionOut = ...
            rotatingToInertial * positionIn;

        velocityOut = rotatingToInertial * ( ...
            velocityIn + cross(omega, positionIn));

    otherwise

        error("Direction must be ""fromInertial"" or ""toInertial"".");
end

stateOut = [
    positionOut
    velocityOut
];
end
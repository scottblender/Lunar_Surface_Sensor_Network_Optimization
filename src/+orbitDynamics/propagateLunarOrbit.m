function [times, statesMoonInertial] = propagateLunarOrbit( ...
    initialStateMoonInertial, timeSpan, options)
% Inputs:
%   initialStateMoonInertial - 6x1 state, km and km/s
%   timeSpan                 - integration times, seconds
%
% Name-value option:
%   moonMu                   - km^3/s^2
%
% Outputs:
%   times                    - Nx1 integration times
%   statesMoonInertial       - Nx6 MCI states

arguments
    initialStateMoonInertial (6,1) double
    timeSpan (:,1) double
    options.moonMu (1,1) double {mustBePositive} = 4902.800066
end

solverOptions = odeset( ...
    "RelTol", 1e-12, ...
    "AbsTol", 1e-12);

dynamicsFunction = @(time, state) ...
    orbitDynamics.lunarTwoBodyDynamics( ...
        time, state, options.moonMu);

[times, statesMoonInertial] = ode113( ...
    dynamicsFunction, ...
    timeSpan, ...
    initialStateMoonInertial, ...
    solverOptions);
end
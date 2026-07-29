function stateDerivative = lunarTwoBodyDynamics(~, state, moonMu)
% Inputs:
%   state  - 6x1 MCI state [position; velocity], km and km/s
%   moonMu - lunar gravitational parameter, km^3/s^2
%
% Output:
%   stateDerivative - [velocity; acceleration]

arguments
    ~
    state (6,1) double
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

% Extract position and velocity from the state vector
position = state(1:3);
velocity = state(4:6);

% Calculate the acceleration due to lunar gravity
r = norm(position); % Distance from the moon's center
acceleration = -moonMu * position / r^3;

% Combine velocity and acceleration into the state derivative
stateDerivative = [velocity; acceleration];
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

position = state(1:3);
velocity = state(4:6);

r = norm(position);
acceleration = -moonMu * position / r^3;

stateDerivative = [velocity; acceleration];
function dynamicsJacobian = lunarTwoBodyJacobian(~, state, moonMu)
% LUNARTWOBODYJACOBIAN Continuous two-body dynamics Jacobian in MCI.
%
% Inputs:
%   state  - 6x1 MCI state [position; velocity], km and km/s
%   moonMu - Lunar gravitational parameter, km^3/s^2
%
% Output:
%   dynamicsJacobian - 6x6 continuous-time Jacobian df/dx

arguments
    ~
    state (6,1) double
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

position = state(1:3);
radius = norm(position);

if radius == 0
    error("The spacecraft position cannot be at the Moon center.");
end

identityMatrix = eye(3);
zeroMatrix = zeros(3);

accelerationJacobian = moonMu * ( ...
    3*(position*position.')/radius^5 ...
    - identityMatrix/radius^3);

dynamicsJacobian = [
    zeroMatrix,             identityMatrix
    accelerationJacobian,  zeroMatrix
];

end
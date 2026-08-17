function dynamicsJacobian = lunarTwoBodyJacobian(~, state, moonMu)
% LUNARTWOBODYJACOBIAN Continuous-time Jacobian df/dx in MCI.
%
% state  = [position; velocity], km and km/s
% output = 6x6 continuous-time dynamics matrix

position = state(1:3);
radius = norm(position);

identity3 = eye(3);
zero3 = zeros(3);

accelerationPositionJacobian = moonMu * ...
    (3*(position*position.')/radius^5 - identity3/radius^3);

dynamicsJacobian = [ ...
    zero3, identity3; ...
    accelerationPositionJacobian, zero3];
end
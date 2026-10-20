function augmentedDerivative = lunarStateAndStmDynamics( ...
    time, augmentedState, moonMu)
% LUNARSTATEANDSTMDYNAMICS - Propagate the MCI state and STM.
%
% Inputs:
%   - time - Propagation time, s
%   - augmentedState - 42x1 vector [state; STM(:)]
%   - moonMu - Lunar gravitational parameter, km^3/s^2
%
% Outputs:
%   - augmentedDerivative - 42x1 derivative [stateDerivative; STMdot(:)]

arguments
    time (1,1) double
    augmentedState (42,1) double
    moonMu (1,1) double {mustBePositive} = 4902.800066
end

state = augmentedState(1:6);

stateTransitionMatrix = reshape( ...
    augmentedState(7:42), 6, 6);

stateDerivative = orbitDynamics.lunarTwoBodyDynamics( ...
    time, state, moonMu);

dynamicsJacobian = orbitDynamics.lunarTwoBodyJacobian( ...
    time, state, moonMu);

stateTransitionMatrixDerivative = ...
    dynamicsJacobian * stateTransitionMatrix;

augmentedDerivative = [
    stateDerivative
    stateTransitionMatrixDerivative(:)
];

end

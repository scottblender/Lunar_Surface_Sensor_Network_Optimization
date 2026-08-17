function augmentedDerivative = lunarStateAndStmDynamics( ...
    time, augmentedState, moonMu)

state = augmentedState(1:6);
stateTransitionMatrix = reshape(augmentedState(7:42), 6, 6);

stateDerivative = orbitDynamics.lunarTwoBodyDynamics( ...
    time, state, moonMu);

dynamicsJacobian = orbitDynamics.lunarTwoBodyJacobian( ...
    time, state, moonMu);

stmDerivative = dynamicsJacobian*stateTransitionMatrix;

augmentedDerivative = [ ...
    stateDerivative; ...
    stmDerivative(:)];
end
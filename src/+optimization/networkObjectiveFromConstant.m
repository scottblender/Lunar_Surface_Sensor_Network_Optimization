function [objectiveValue,details] = ...
    networkObjectiveFromConstant( ...
        sensorDecision, ...
        databaseConstant, ...
        objectiveMode)
% NETWORKOBJECTIVEFROMCONSTANT - Evaluate a network using worker-local data.
%
% Inputs:
%   - sensorDecision - Candidate-site IDs.
%   - databaseConstant - Worker-local parallel.pool.Constant holding frozen data.
%   - objectiveMode - "information" or "coverage".
%
% Outputs:
%   - objectiveValue, details - Network objective and optional diagnostics.

arguments
    sensorDecision double
    databaseConstant (1,1) parallel.pool.Constant
    objectiveMode (1,1) string
end

[objectiveValue,details] = ...
    optimization.networkObjective( ...
        sensorDecision, ...
        databaseConstant.Value, ...
        objectiveMode);

end

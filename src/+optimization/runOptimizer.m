function result = runOptimizer(objectiveFcn,problem,config)
% RUNOPTIMIZER - Dispatch the selected sensor-network optimizer.
%
% Inputs:
%   - objectiveFcn - Scalar network objective.
%   - problem - Shared sensor-index bounds, constraints, and penalty.
%   - config - Solver selection and search settings.
%
% Outputs:
%   - result - Standard solver result and FE history.
%
% See also optimization.runGA, optimization.runPSO, optimization.runSurrogate,
%   optimization.runABC.

switch upper(string(config.optimizer))
    case "GA"
        result = optimization.runGA(objectiveFcn,problem,config);
    case "SURROGATE"
        result = optimization.runSurrogate(objectiveFcn,problem,config);
    case "PSO"
        % MATLAB particleswarm uses continuous variables. Round candidates,
        % penalize duplicates; never repair or deduplicate the particles.
        discreteObjective = @(x) optimization.roundAndPenalize( ...
            x,objectiveFcn,problem);
        result = optimization.runPSO(discreteObjective,problem,config);
    case "ABC"
        result = optimization.runABC(objectiveFcn,problem,config);
    otherwise
        error("runOptimizer:UnsupportedOptimizer", ...
            "Unsupported optimizer: %s",string(config.optimizer));
end
end

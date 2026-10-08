function result = runOptimizer(objectiveFcn,problem,config)
% RUNOPTIMIZER Common entry point for pluggable discrete optimizers.
% See docs/optimizer_adapter_guide.md for the solver result contract.
% Do not put solver-specific logic into runGlobalOptimization.m.

switch upper(string(config.optimizer))
    case "GA"
        result = optimization.runGA(objectiveFcn,problem,config);
    case "SURROGATE"
        assert(~isempty(which("optimization.runSurrogate")), ...
            "runOptimizer:MissingSurrogate", ...
            "Add src/+optimization/runSurrogate.m (Ava's task).");
        result = optimization.runSurrogate(objectiveFcn,problem,config);
    case "PSO"
        assert(~isempty(which("optimization.runPSO")), ...
            "runOptimizer:MissingPSO", ...
            "Add src/+optimization/runPSO.m (Ava's task).");
        % MATLAB particleswarm uses continuous variables. Round candidates,
        % penalize duplicates; never repair or deduplicate the particles.
        discreteObjective = @(x) optimization.roundAndPenalize( ...
            x,objectiveFcn,problem);
        result = optimization.runPSO(discreteObjective,problem,config);
    otherwise
        error("runOptimizer:UnsupportedOptimizer", ...
            "Unsupported optimizer: %s",string(config.optimizer));
end
end

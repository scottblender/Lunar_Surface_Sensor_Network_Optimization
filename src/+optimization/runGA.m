function result = runGA(objectiveFcn,problem,config)
% RUNGA Preserve production integer-GA callback FE accounting and incumbent.
% This adapter was extracted from scripts/runGlobalOptimization.m.
% Input/output contract: docs/optimizer_adapter_guide.md.

populationSize = config.populationSize;
functionEvaluationBudget = config.functionEvaluationBudget;
validateattributes(populationSize,{'numeric'}, ...
    {'scalar','integer','>=',2});
assert(mod(functionEvaluationBudget,populationSize) == 0, ...
    ["For exact GA FE accounting, functionEvaluationBudget must be " ...
     "divisible by populationSize."]);
numberOfGenerations = functionEvaluationBudget/populationSize - 1;
assert(numberOfGenerations >= 0, ...
    "FE budget must be at least one population.");

historyFe = zeros(0,1);
historyBestJ = zeros(0,1);
historyGeneration = zeros(0,1);
incumbentJ = Inf;
incumbentX = [];

gaOptions = optimoptions( ...
    "ga", ...
    "UseParallel",config.useParallel, ...
    "UseVectorized",false, ...
    "Display",config.display, ...
    "PopulationSize",populationSize, ...
    "EliteCount",0, ...
    "MaxGenerations",numberOfGenerations, ...
    "MaxStallGenerations",Inf, ...
    "FunctionTolerance",0, ...
    "ConstraintTolerance",0, ...
    "FitnessLimit",-Inf, ...
    "OutputFcn",@gaOutputFunction);

[solverBestX,solverBestObjective,exitFlag,solverOutput, ...
    finalPopulation,finalScores] = ga( ...
        objectiveFcn,problem.nvars, ...
        problem.A,problem.b,problem.Aeq,problem.beq, ...
        problem.lb,problem.ub,[],problem.intcon,gaOptions);

assert(~isempty(incumbentX) && isfinite(incumbentJ), ...
    "GA did not record a finite best-so-far incumbent.");
% Preserve the original production accounting convention. The callback
% supplies the FE count admitted to the comparison history, capped at the
% requested budget. MATLAB's final output.funccount can be one (or more)
% higher; it is retained separately and MUST NOT redefine the callback FE.
assert(~isempty(historyFe) && ...
    isfinite(historyFe(end)) && historyFe(end) > 0 && ...
    historyFe(end) <= functionEvaluationBudget, ...
    "GA did not produce a valid callback FE history.");
solverFe = double(solverOutput.funccount);
assert(isfinite(solverFe) && solverFe >= historyFe(end), ...
    "GA solver FE count is inconsistent with its callback FE history.");

result = struct();
result.x = incumbentX(:);
result.fval = incumbentJ;
result.exitflag = exitFlag;
result.output = solverOutput;
result.functionEvaluations = historyFe(end);
result.solverFunctionEvaluations = solverFe;
result.history = struct("fe",historyFe,"bestJ",historyBestJ, ...
    "generation",historyGeneration);
result.numberOfGenerations = numberOfGenerations;
result.solverFinalBestX = solverBestX;
result.solverFinalBestObjective = solverBestObjective;
result.finalPopulation = finalPopulation;
result.finalScores = finalScores;

    function [state,options,optChanged] = ...
            gaOutputFunction(options,state,flag)
        % Best-so-far across generations, including generation zero.
        % EliteCount=0 means the solver's final population can lose the best.
        optChanged = false;
        if ~(strcmp(flag,"init") || strcmp(flag,"iter"))
            return
        end
        values = state.Score(:);
        if isfield(state,"Fitness")
            values = state.Fitness(:);
        end
        values(~isfinite(values)) = Inf;
        [generationBest,generationBestIndex] = min(values);
        if ~isempty(generationBest) && generationBest < incumbentJ
            incumbentJ = generationBest;
            incumbentX = state.Population(generationBestIndex,:);
        end
        if isfield(state,"FunEval") && isfinite(state.FunEval)
            currentFe = min(state.FunEval,functionEvaluationBudget);
        else
            currentFe = min((state.Generation+1)*populationSize, ...
                functionEvaluationBudget);
        end
        if isempty(historyFe) || currentFe > historyFe(end)
            historyFe(end+1,1) = currentFe;
            historyBestJ(end+1,1) = incumbentJ;
            historyGeneration(end+1,1) = state.Generation;
        elseif currentFe == historyFe(end)
            historyBestJ(end) = min(historyBestJ(end),incumbentJ);
        end
    end
end


function result = runPSO(objectiveFcn,problem,config)
% RUNPSO Particle swarm optimizer adapter for discrete sensor selection.
% The objectiveFcn is already wrapped by roundAndPenalize in runOptimizer.
% Tracks callback FE and best-so-far objective.

budget = config.functionEvaluationBudget;
swarmSize = config.populationSize;

validateattributes(budget,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(swarmSize,{'numeric'}, ...
    {'scalar','integer','>=',2});

assert(mod(budget,swarmSize) == 0, ...
    "PSO FE budget must be divisible by swarm size.");
assert(budget >= swarmSize, ...
    "PSO FE budget must be at least one swarm.");

maxIterations = budget/swarmSize - 1;

historyFe = zeros(0,1);
historyBestJ = zeros(0,1);

incumbentX = [];
incumbentJ = Inf;

options = optimoptions("particleswarm", ...
    "SwarmSize",swarmSize, ...
    "MaxIterations",maxIterations, ...
    "MaxStallIterations",max(200,maxIterations+1), ...
    "FunctionTolerance",0, ...
    "UseParallel",config.useParallel, ...
    "Display",config.display, ...
    "OutputFcn",@outfun);

[solverX,solverFval,exitFlag,solverOutput] = ...
    particleswarm(objectiveFcn,problem.nvars, ...
    problem.lb,problem.ub,options);

% Check callback history
assert(~isempty(historyFe), ...
    "PSO produced no function evaluation history.");

assert(~isempty(incumbentX) && isfinite(incumbentJ), ...
    "PSO found no finite incumbent.");

assert(incumbentJ < problem.infeasiblePenalty, ...
    "PSO found no feasible discrete sensor network.");

% Verify final decoded sensor IDs without modifying particle positions
decoded = sort(round(double(incumbentX(:).')));

assert(numel(decoded) == problem.nvars, ...
    "Incorrect number of sensor IDs.");
assert(all(isfinite(decoded)), ...
    "Nonfinite sensor IDs.");
assert(all(decoded >= problem.lb(:).') && ...
       all(decoded <= problem.ub(:).'), ...
    "Sensor IDs violate bounds.");
assert(numel(unique(decoded)) == problem.nvars, ...
    "Duplicate sensor IDs in best solution.");

solverFe = double(solverOutput.funccount);

assert(solverFe >= historyFe(end), ...
    "Solver FE count is inconsistent with callback history.");

result = struct();
result.x = incumbentX(:);
result.fval = incumbentJ;
result.exitflag = exitFlag;
result.output = solverOutput;
result.functionEvaluations = historyFe(end);
result.solverFunctionEvaluations = solverFe;
result.history = struct( ...
    "fe",historyFe, ...
    "bestJ",historyBestJ);

result.solverFinalBestX = solverX;
result.solverFinalBestObjective = solverFval;
result.numberOfGenerations = maxIterations;

    function stop = outfun(optimValues,state)
        stop = false;
        if ~(strcmp(state,"init") || strcmp(state,"iter") || ...
                strcmp(state,"done"))
            return
        end

        currentFe = min(double(optimValues.funccount),budget);
        currentJ = double(optimValues.bestfval);

        % Track only non-penalty solutions
        if isfinite(currentJ) && ...
                currentJ < problem.infeasiblePenalty && ...
                currentJ < incumbentJ

            incumbentJ = currentJ;
            incumbentX = optimValues.bestx(:);
        end

        if currentFe > 0 && ...
                (isempty(historyFe) || currentFe > historyFe(end))
            historyFe(end+1,1) = currentFe;
            historyBestJ(end+1,1) = incumbentJ;
        elseif ~isempty(historyFe) && currentFe == historyFe(end)
            historyBestJ(end) = incumbentJ;
        end

        if optimValues.funccount >= budget
            stop = true;
        end
    end
end

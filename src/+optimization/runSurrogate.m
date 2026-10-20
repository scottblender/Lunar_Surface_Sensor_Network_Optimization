
function result = runSurrogate(objectiveFcn,problem,config)
% RUNSURROGATE - Run mixed-integer surrogate optimization for sensor selection.
%
% Inputs:
%   - objectiveFcn - Scalar network objective.
%   - problem - Integer bounds and linear constraints.
%   - config - FE budget, parallel flag, and display setting.
%
% Outputs:
%   - result - Feasible incumbent, callback history, and raw solver FE count.

budget = config.functionEvaluationBudget;

validateattributes(budget,{'numeric'}, ...
    {'scalar','integer','positive'});

% Initialize optimization history
historyFe = zeros(0,1);
historyBestJ = zeros(0,1);

incumbentX = [];
incumbentJ = Inf;

% Configure surrogate optimization
options = optimoptions("surrogateopt", ...
    "MaxFunctionEvaluations",budget, ...
    "UseParallel",config.useParallel, ...
    "Display",config.display, ...
    "OutputFcn",@outfun);

% Run optimization with native integer and linear constraints
[solverX,solverFval,exitFlag,solverOutput,trials] = ...
    surrogateopt( ...
        objectiveFcn, ...
        problem.lb,problem.ub,problem.intcon, ...
        problem.A,problem.b,problem.Aeq,problem.beq, ...
        options);

% Validate the callback history
assert(~isempty(historyFe), ...
    "Surrogate optimization produced no FE history.");

assert(~isempty(incumbentX) && isfinite(incumbentJ), ...
    "Surrogate optimization found no finite incumbent.");

% Validate decision bounds and integrality
x = incumbentX(:);
tol = 1e-6;

assert(numel(x) == problem.nvars, ...
    "Incorrect number of decision variables.");

assert(all(x >= problem.lb(:)-tol) && ...
       all(x <= problem.ub(:)+tol), ...
    "Returned solution violates bounds.");

assert(all(abs(x(problem.intcon) - ...
    round(x(problem.intcon))) <= tol), ...
    "Returned solution violates integer constraints.");

if ~isempty(problem.A)
    assert(all(problem.A*x <= problem.b(:)+tol), ...
        "Returned solution violates linear inequalities.");
end

if ~isempty(problem.Aeq)
    assert(all(abs(problem.Aeq*x-problem.beq(:)) <= tol), ...
        "Returned solution violates linear equalities.");
end

assert(incumbentJ < problem.infeasiblePenalty, ...
    "No non-penalty solution was found.");

% Store raw solver evaluation count separately
solverFe = double(solverOutput.funccount);

assert(solverFe >= historyFe(end), ...
    "Solver FE count is inconsistent with callback history.");

% Construct the required result structure
result = struct();
result.x = x;
result.fval = incumbentJ;
result.exitflag = exitFlag;
result.output = solverOutput;

result.functionEvaluations = historyFe(end);
result.solverFunctionEvaluations = solverFe;

result.history = struct( ...
    "fe",historyFe, ...
    "bestJ",historyBestJ);

% Optional solver diagnostics
result.solverFinalBestX = solverX;
result.solverFinalBestObjective = solverFval;
result.trials = trials;

    function stop = outfun(xBest,optimValues,state)
        % Called by surrogateopt during optimization.

        stop = false;

        if strcmp(state,"init")
            return
        end

        if strcmp(state,"iter") || strcmp(state,"done")

            currentFe = min( ...
                double(optimValues.funccount),budget);

            currentJ = double(optimValues.fval);

            % Preserve the best feasible incumbent
            if ~isempty(xBest) && isfinite(currentJ) && ...
                    currentJ < incumbentJ && ...
                    currentJ < problem.infeasiblePenalty

                incumbentJ = currentJ;
                incumbentX = xBest(:);
            end

            % Record strictly increasing FE checkpoints
            if currentFe > 0 && ...
                    (isempty(historyFe) || ...
                     currentFe > historyFe(end))

                historyFe(end+1,1) = currentFe;
                historyBestJ(end+1,1) = incumbentJ;

            elseif ~isempty(historyFe) && ...
                    currentFe == historyFe(end)

                historyBestJ(end) = incumbentJ;
            end

            if optimValues.funccount >= budget
                stop = true;
            end
        end
    end
end

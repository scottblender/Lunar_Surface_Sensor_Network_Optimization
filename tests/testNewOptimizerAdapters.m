function tests = testNewOptimizerAdapters
% TESTNEWOPTIMIZERADAPTERS - Test PSO and surrogate adapters through the common dispatcher.

tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"src"));
end

function testSurrogateAdapter(testCase)
previousRng = rng;
cleanup = onCleanup(@()rng(previousRng)); %#ok<NASGU>
rng(1451,"twister");

[problem,objectiveFcn,config] = makeTestProblem();
config.optimizer = "SURROGATE";

result = optimization.runOptimizer(objectiveFcn,problem,config);
verifyAdapterResult(testCase,result,problem,objectiveFcn,config);

% Surrogate optimization must honor native mixed-integer and ordering
% constraints, without a rounding or repair wrapper.
x = double(result.x(:));
verifyEqual(testCase,x,round(x),"AbsTol",1e-6);
verifyLessThanOrEqual(testCase,problem.A*x,problem.b+1e-6);
end

function testPSOAdapter(testCase)
previousRng = rng;
cleanup = onCleanup(@()rng(previousRng)); %#ok<NASGU>
rng(1452,"twister");

[problem,objectiveFcn,config] = makeTestProblem();
config.optimizer = "PSO";

% The dispatcher wraps the objective in roundAndPenalize before PSO.
result = optimization.runOptimizer(objectiveFcn,problem,config);
verifyAdapterResult(testCase,result,problem,objectiveFcn,config);

% Decode without repairing duplicated sensor IDs.
decoded = sort(round(double(result.x(:))));
verifyEqual(testCase,numel(unique(decoded)),problem.nvars);
end

function testPSODuplicatePenalty(testCase)
[problem,objectiveFcn,~] = makeTestProblem();

% Different continuous positions mapping to the same site get a penalty.
invalid = [12.2 12.4 50.1];
verifyEqual(testCase,optimization.roundAndPenalize( ...
    invalid,objectiveFcn,problem),problem.infeasiblePenalty);

% Valid candidates are rounded and sorted before objective evaluation.
continuous = [165.4 25.3 88.8];
decoded = sort(round(continuous));
verifyEqual(testCase,optimization.roundAndPenalize( ...
    continuous,objectiveFcn,problem), ...
    objectiveFcn(decoded),"AbsTol",1e-10);
end

function [problem,objectiveFcn,config] = makeTestProblem()
% Three ordered integer sensor IDs selected from a 200-site grid.
target = [25 90 165];
nvars = 3;
nCandidates = 200;

problem = struct();
problem.nvars = nvars;
problem.numberOfCandidates = nCandidates;
problem.lb = ones(1,nvars);
problem.ub = nCandidates*ones(1,nvars);
problem.intcon = 1:nvars;
problem.A = [1 -1 0;0 1 -1];
problem.b = [-1;-1];
problem.Aeq = [];
problem.beq = [];
problem.infeasiblePenalty = 1e12;

objectiveFcn = @(x) sum((double(x(:).')-target).^2);

config = struct();
config.optimizer = "";
config.populationSize = 60;
config.functionEvaluationBudget = 120;
config.useParallel = false;
config.display = "off";
end

function verifyAdapterResult(testCase,result,problem,objectiveFcn,config)
% Validate the single result structure expected by the production driver.
required = ["x","fval","exitflag","output", ...
    "functionEvaluations","solverFunctionEvaluations","history"];
verifyTrue(testCase,all(isfield(result,cellstr(required))), ...
    "The solver did not return all required fields.");

% Valid discrete lunar-candidate indices after decoding PSO particles.
x = double(result.x(:));
verifyEqual(testCase,numel(x),problem.nvars);
verifyTrue(testCase,all(isfinite(x)));
decoded = sort(round(x));
verifyGreaterThanOrEqual(testCase,decoded,problem.lb(:));
verifyLessThanOrEqual(testCase,decoded,problem.ub(:));
verifyEqual(testCase,numel(unique(decoded)),problem.nvars);
verifyLessThanOrEqual(testCase,problem.A*decoded,problem.b+1e-6);

verifyTrue(testCase,isscalar(result.fval) && isfinite(result.fval));
verifyLessThan(testCase,result.fval,problem.infeasiblePenalty);
% Test-only reevaluation is outside the solver's search FE budget.
verifyEqual(testCase,result.fval,objectiveFcn(decoded),"AbsTol",1e-8);

% Shared FE accounting: the comparison count is the final CALLBACK
% checkpoint; MATLAB's raw output.funccount is diagnostic and may differ.
verifyTrue(testCase,isfield(result.history,"fe") && ...
    isfield(result.history,"bestJ"));
historyFe = double(result.history.fe(:));
historyBestJ = double(result.history.bestJ(:));
verifyNotEmpty(testCase,historyFe);
verifyEqual(testCase,numel(historyFe),numel(historyBestJ));
verifyTrue(testCase,all(isfinite(historyFe)) && ...
    all(historyFe == round(historyFe)));
verifyTrue(testCase,all(diff(historyFe) > 0));
verifyTrue(testCase,all(historyFe > 0 & ...
    historyFe <= config.functionEvaluationBudget));
verifyTrue(testCase,all(isfinite(historyBestJ)));
verifyTrue(testCase,all(diff(historyBestJ) <= 1e-10));

verifyEqual(testCase,result.functionEvaluations,historyFe(end));
verifyEqual(testCase,historyBestJ(end),result.fval,"AbsTol",1e-8);
verifyTrue(testCase,isstruct(result.output) && ...
    isfield(result.output,"funccount"));
verifyEqual(testCase,result.solverFunctionEvaluations, ...
    result.output.funccount);
verifyGreaterThanOrEqual(testCase, ...
    result.solverFunctionEvaluations,result.functionEvaluations);
end

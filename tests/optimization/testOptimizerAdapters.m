function tests = testOptimizerAdapters
% TESTOPTIMIZERADAPTERS - Test GA, PSO, surrogate optimization, and index penalties.

tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root,"src"));
end

function testRoundAndPenalize(testCase)
problem = struct("nvars",3,"lb",ones(1,3), ...
    "ub",10*ones(1,3),"infeasiblePenalty",1e12);
objectiveFcn = @(indices) sum(indices.^2);
verifyEqual(testCase, ...
    optimization.roundAndPenalize([8.3,2.1,5.6],objectiveFcn,problem), ...
    sum([2,6,8].^2));
verifyEqual(testCase, ...
    optimization.roundAndPenalize([2.1,2.4,5.6],objectiveFcn,problem), ...
    problem.infeasiblePenalty);
verifyEqual(testCase, ...
    optimization.roundAndPenalize([0,2,5],objectiveFcn,problem), ...
    problem.infeasiblePenalty);
end

function testExtractedGAContract(testCase)
previous = rng;
cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
rng(1000,"twister");
problem = struct("nvars",2, ...
    "lb",[1 1],"ub",[10 10], ...
    "intcon",1:2, ...
    "A",[1 -1],"b",-1, ...
    "Aeq",[],"beq",[],"infeasiblePenalty",1e12);
cfg = struct("optimizer","GA","populationSize",60, ...
    "functionEvaluationBudget",120,"useParallel",false,"display","off");
fun = @(x) sum((x(:).'-[3 7]).^2);
result = optimization.runOptimizer(fun,problem,cfg);
% A small finite domain can stop early; preserve the callback history.
% Never replace its FE count with MATLAB's final raw solver funccount.
verifyGreaterThan(testCase,result.functionEvaluations,0);
verifyLessThanOrEqual(testCase,result.functionEvaluations,120);
verifyEqual(testCase,result.history.fe(end),result.functionEvaluations);
verifyEqual(testCase,result.solverFunctionEvaluations,result.output.funccount);
verifyGreaterThanOrEqual(testCase,result.solverFunctionEvaluations, ...
    result.functionEvaluations);
verifyEqual(testCase,result.history.bestJ(end),result.fval);
verifyTrue(testCase,all(diff(result.history.bestJ) <= 1e-10));
verifyEqual(testCase,numel(unique(result.x)),2);
verifyGreaterThan(testCase,diff(sort(result.x)),0);
verifyEqual(testCase,fun(result.x),result.fval,'AbsTol',1e-10);
end

function testGAActualFeOnLargerDiscreteSpace(testCase)
% A larger candidate grid makes duplicate fitness reuse less common.
previous = rng;
cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
rng(1000,"twister");
problem = struct("nvars",3, ...
    "lb",[1 1 1],"ub",[300 300 300], ...
    "intcon",1:3, ...
    "A",[1 -1 0;0 1 -1],"b",[-1;-1], ...
    "Aeq",[],"beq",[],"infeasiblePenalty",1e12);
cfg = struct("optimizer","GA","populationSize",60, ...
    "functionEvaluationBudget",120,"useParallel",false,"display","off");
fun = @(x) sum((x(:).'-[10 50 250]).^2);
result = optimization.runOptimizer(fun,problem,cfg);
verifyGreaterThan(testCase,result.functionEvaluations,0);
verifyLessThanOrEqual(testCase,result.functionEvaluations,120);
verifyEqual(testCase,result.history.fe(end),result.functionEvaluations);
verifyEqual(testCase,result.solverFunctionEvaluations,result.output.funccount);
verifyGreaterThanOrEqual(testCase,result.solverFunctionEvaluations, ...
    result.functionEvaluations);
verifyEqual(testCase,result.history.bestJ(end),result.fval);
verifyEqual(testCase,fun(result.x),result.fval,'AbsTol',1e-10);
verifyEqual(testCase,numel(unique(result.x)),3);
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

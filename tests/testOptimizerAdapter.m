function tests = testOptimizerAdapter
% Small deterministic interface tests; no lunar production database needed.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
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

function tests = testABCOptimizer
% TESTABCOPTIMIZER - Test ABC feasibility, evaluation budgets, and reproducibility.

tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root);
setupProject;
end

function testExactBudgetsAndFeasibleCalls(testCase)
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
for budget = [5 6 11 29 103]
    rng(1000,"twister");
    [problem,config] = makeProblem(3,12,budget);
    calls = zeros(0,3);
    result = optimization.runOptimizer(@objective,problem,config);
    verifyEqual(testCase,size(calls,1),budget);
    verifyEqual(testCase,result.functionEvaluations,budget);
    verifyEqual(testCase,result.solverFunctionEvaluations,budget);
    verifyEqual(testCase,result.output.funccount,budget);
    verifyTrue(testCase,all(diff(calls,1,2) > 0,'all'));
    verifyTrue(testCase,all(calls >= 1 & calls <= 12,'all'));
    verifyEqual(testCase,calls,round(calls));
    scores = sum((calls-[2 6 11]).^2,2)-100;
    verifyEqual(testCase,result.fval,min(scores));
    for k = 1:numel(result.history.fe)
        verifyEqual(testCase,result.history.bestJ(k), ...
            min(scores(1:result.history.fe(k))));
    end
    verifyTrue(testCase,all(diff(result.history.fe) > 0));
    verifyEqual(testCase,result.history.fe(end),budget);
    verifyEqual(testCase,result.history.bestJ(end),result.fval);
    verifyEqual(testCase,sum((result.x(:).'-[2 6 11]).^2)-100,result.fval);
end
    function value = objective(x)
        calls(end+1,:) = x;
        value = sum((x-[2 6 11]).^2)-100;
    end
end

function testOneSensorAndFullCandidateSet(testCase)
for n = [1 4]
    [problem,config] = makeProblem(n,4,37);
    result = optimization.runOptimizer(@(x)sum(x.^2),problem,config);
    verifyEqual(testCase,numel(unique(result.x)),n);
    verifyEqual(testCase,result.fval,sum(result.x.^2));
    verifyEqual(testCase,result.functionEvaluations,37);
end
end

function testScoutKeepsHistoricalIncumbent(testCase)
[problem,config] = makeProblem(2,10,41);
config.abcLimit = 1;
count = 0;
result = optimization.runOptimizer(@objective,problem,config);
verifyEqual(testCase,count,41);
verifyEqual(testCase,result.fval,-10);
verifyTrue(testCase,all(result.history.bestJ == -10));
% All initial sources, including the best, eventually stagnate and become
% scouts. Their replacement must not erase the historical incumbent.
verifyTrue(testCase,all(result.finalScores == 10));
    function value = objective(~)
        count = count+1;
        value = 10;
        if count == 1, value = -10; end
    end
end

function testReproducibility(testCase)
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
[problem,config] = makeProblem(3,25,97);
objective = @(x)sum((x-[3 12 21]).^2);
rng(42,"twister"); first = optimization.runOptimizer(objective,problem,config);
rng(42,"twister"); second = optimization.runOptimizer(objective,problem,config);
verifyEqual(testCase,first,second);
end

function testInvalidSettingsAndPenaltyOnlyObjective(testCase)
[problem,config] = makeProblem(3,10,31);
verifyError(testCase,@()optimization.runOptimizer( ...
    @(x)problem.infeasiblePenalty,problem,config),"runABC:NoFeasibleNetwork");
verifyError(testCase,@()optimization.runOptimizer( ...
    @(x)NaN,problem,config),"runABC:NoFeasibleNetwork");
config.populationSize = 9;
verifyError(testCase,@()optimization.runOptimizer(@sum,problem,config), ...
    "runABC:ColonySize");
config.populationSize = 10; config.functionEvaluationBudget = 4;
verifyError(testCase,@()optimization.runOptimizer(@sum,problem,config), ...
    "runABC:InsufficientBudget");
config.functionEvaluationBudget = 31; problem.Aeq = ones(1,3); problem.beq = 5;
verifyError(testCase,@()optimization.runOptimizer(@sum,problem,config), ...
    "runABC:Constraints");
end

function testParallelMatchesSerial(testCase)
% Batch-token licensing can report false from license('test',...) even
% when the installed toolbox is usable. Let parpool verify execution.
assumeFalse(testCase,isempty(ver('parallel')));
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
pool = gcp('nocreate');
if isempty(pool)
    pool = parpool('Processes',2);
    poolCleanup = onCleanup(@()delete(pool)); %#ok<NASGU>
end
[problem,config] = makeProblem(3,25,47);
objective = @(x)sum((x-[3 12 21]).^2);
rng(42,"twister"); serial = optimization.runOptimizer(objective,problem,config);
config.useParallel = true;
rng(42,"twister"); parallel = optimization.runOptimizer(objective,problem,config);
verifyEqual(testCase,parallel,serial);
end

function [problem,config] = makeProblem(n,count,budget)
A = zeros(max(0,n-1),n);
for k = 1:n-1, A(k,k:k+1) = [1 -1]; end
problem = struct('nvars',n,'numberOfCandidates',count, ...
    'lb',ones(1,n),'ub',count*ones(1,n),'intcon',1:n, ...
    'A',A,'b',-ones(n-1,1),'Aeq',[],'beq',[],'infeasiblePenalty',1e12);
config = struct('optimizer','ABC','populationSize',10, ...
    'functionEvaluationBudget',budget,'abcLimit',2, ...
    'useParallel',false,'display','off');
end

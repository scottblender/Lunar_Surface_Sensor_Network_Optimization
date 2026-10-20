function tests = testOptimizers
% TESTOPTIMIZERS - Verify solver contracts, exact ABC budgets, and discrete candidate sampling.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupProject;
end

function setup(testCase)
previous = rng;
testCase.addTeardown(@()rng(previous));
end

function testExactBudgetsAndFeasibleCalls(testCase)
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
for budget = [5 6 11 29 103]
    rng(1000,"twister");
    [problem,config] = abcProblem(3,12,budget);
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
    [problem,config] = abcProblem(n,4,37);
    result = optimization.runOptimizer(@(x)sum(x.^2),problem,config);
    verifyEqual(testCase,numel(unique(result.x)),n);
    verifyEqual(testCase,result.fval,sum(result.x.^2));
    verifyEqual(testCase,result.functionEvaluations,37);
end
end

function testScoutKeepsHistoricalIncumbent(testCase)
[problem,config] = abcProblem(2,10,41);
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
[problem,config] = abcProblem(3,25,97);
objective = @(x)sum((x-[3 12 21]).^2);
rng(42,"twister"); first = optimization.runOptimizer(objective,problem,config);
rng(42,"twister"); second = optimization.runOptimizer(objective,problem,config);
verifyEqual(testCase,first,second);
end

function testInvalidSettingsAndPenaltyOnlyObjective(testCase)
[problem,config] = abcProblem(3,10,31);
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
[problem,config] = abcProblem(3,25,47);
objective = @(x)sum((x-[3 12 21]).^2);
rng(42,"twister"); serial = optimization.runOptimizer(objective,problem,config);
config.useParallel = true;
rng(42,"twister"); parallel = optimization.runOptimizer(objective,problem,config);
verifyEqual(testCase,parallel,serial);
end

function [problem,config] = abcProblem(n,count,budget)
A = zeros(max(0,n-1),n);
for k = 1:n-1, A(k,k:k+1) = [1 -1]; end
problem = struct('nvars',n,'numberOfCandidates',count, ...
    'lb',ones(1,n),'ub',count*ones(1,n),'intcon',1:n, ...
    'A',A,'b',-ones(n-1,1),'Aeq',[],'beq',[],'infeasiblePenalty',1e12);
config = struct('optimizer','ABC','populationSize',10, ...
    'functionEvaluationBudget',budget,'abcLimit',2, ...
    'useParallel',false,'display','off');
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

function testCommonSolverContract(testCase)
[problem,objectiveFcn,config] = makeTestProblem();
for method = ["GA","PSO","SURROGATE","ABC"]
    rng(1451,"twister");
    config.optimizer = method;
    result = optimization.runOptimizer(objectiveFcn,problem,config);
    verifyAdapterResult(testCase,result,problem,objectiveFcn,config);
    if method ~= "PSO"
        x = double(result.x(:));
        verifyEqual(testCase,x,round(x),"AbsTol",1e-6);
        verifyLessThanOrEqual(testCase,problem.A*x,problem.b+1e-6);
    end
end
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

function testUniqueGlobalSamplesAndReproducibility(testCase)
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
rng(7000,"twister");
a = zeros(10,1000);
for k=1:1000
    a(:,k) = sampleGlobalCandidateNetwork(100,10);
    verifyEqual(testCase,numel(unique(a(:,k))),10);
end
verifyEqual(testCase,unique(a(:)),(1:100).');
rng(7000,"twister");
verifyEqual(testCase,sampleGlobalCandidateNetwork(100,10),a(:,1));
% No nominal-site exclusions: even a network containing every site is valid.
verifyEqual(testCase,sampleGlobalCandidateNetwork(10,10),(1:10).');
end

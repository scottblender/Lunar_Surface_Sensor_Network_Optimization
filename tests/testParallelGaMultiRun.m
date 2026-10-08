function tests = testParallelGaMultiRun
% TESTPARALLELGAMULTIRUN Function-based test of the shared process pool.
% Keep setup, all three GA runs, and checks in the SAME function workspace.
% MATLAB runtests treats sections in a script as independent tests with
% separate workspaces, so this must not be a section-based script.
tests = functiontests(localfunctions);
end

function testSharedPoolAcrossThreeGARuns(testCase)
% Exercise the normal pilot/production policy: reuse ONE process pool.
% Leave an existing pool untouched, and leave the pool open afterward.

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
addpath(fullfile(projectRoot,"src"));
addpath(fullfile(projectRoot,"scripts"));
rehash path;

% Use the caller's existing process pool. Create one only if absent.
poolBefore = gcp("nocreate");
if isempty(poolBefore)
    poolBefore = parpool("Processes");
elseif isa(poolBefore,"parallel.ThreadPool")
    error("testParallelGaMultiRun:ThreadPool", ...
        ["A thread-based pool is active; this test requires a " ...
         "process pool. Close the thread pool and rerun."]);
end
workerCount = poolBefore.NumWorkers;
fprintf("Parallel GA smoke test using process pool: %d workers.\n", ...
    workerCount);

% Run once, then keep all assertions in this same test function.
config = struct();
config.optimizer = "GA";
config.networkSize = 3;
config.objectiveMode = "coverage";
config.functionEvaluationBudget = 120;
config.populationSize = 60;
config.numberOfRuns = 3;
config.baseSeed = 1000;
config.useParallel = true;
config.parallelRestartEachRun = false;
config.parallelRetryOnFailure = true;
config.closeParallelPoolAtEnd = false;
config.useParallelDatabaseConstant = true;
config.display = "off";
config.studyName = "parallel_ga_shared_pool_smoke_test";

studyState = runGlobalOptimization(config);

verifyEqual(testCase,studyState.numberOfRuns,3);
verifyEqual(testCase,studyState.config.parallelRestartEachRun,false);
verifyEqual(testCase,studyState.config.closeParallelPoolAtEnd,false);

expectedSeeds = (1000:1002).';
actualSeeds = zeros(3,1);

for runIndex = 1:3
    runState = studyState.runStates{runIndex};
    actualSeeds(runIndex) = runState.seed;

    verifyTrue(testCase,runState.usedParallel);
    verifyFalse(testCase,runState.parallelRestartEachRun);
    verifyEqual(testCase,runState.parallelRetryCount,0);
    verifyFalse(testCase,runState.parallelPoolRestarted);

    % The comparison FE uses the capped callback checkpoint, not raw
    % solver output.funccount (GA commonly reports 121 here).
    verifyEqual(testCase,runState.searchFunctionEvaluations,120);
    verifyEqual(testCase,runState.history.fe(end),120);
    verifyGreaterThanOrEqual(testCase, ...
        runState.solverFunctionEvaluations,120);
    verifyTrue(testCase,all(diff(runState.history.fe) > 0));
    verifyTrue(testCase,all(diff(runState.history.bestJ) <= 1e-12));
    verifyEqual(testCase,runState.history.bestJ(end), ...
        runState.bestObjective,"AbsTol", ...
        1e-10*max(1,abs(runState.bestObjective)));
    verifyEqual(testCase,numel(unique(runState.bestSensorIndices)),3);
end
verifyEqual(testCase,actualSeeds,expectedSeeds);

% The same handle proves the study did not replace the original pool.
poolAfter = gcp("nocreate");
assert(~isempty(poolAfter), ...
    "The optimization study unexpectedly closed the shared process pool.");
verifyTrue(testCase,isequal(poolAfter,poolBefore), ...
    "The optimization study replaced the shared process pool.");
verifyEqual(testCase,poolAfter.NumWorkers,workerCount);

fprintf("\nShared-pool parallel GA smoke test passed.\n");
fprintf("  Independent runs: 3\n");
fprintf("  Callback FE:       120 per run\n");
fprintf("  Seeds:             1000 through 1002\n");
fprintf("  Pool:              same pool, still open (%d workers)\n", ...
    poolAfter.NumWorkers);
end

%% testParallelGaMultiRun
% Exercise three independent parallel GA runs using ONE shared process pool,
% matching the normal pilot and production workflow.
%
% The test deliberately does NOT delete an existing process pool, restart
% the pool between runs, or close it afterward. It checks the pool's identity,
% callback FE accounting, reproducible seeds, and preserved GA incumbent.
%
% This is intentionally small: three independent 120-FE runs with a
% 60-member population. The frozen objective database is shared on workers.

%% Project paths

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
addpath(fullfile(projectRoot,"src"));
addpath(fullfile(projectRoot,"scripts"));
rehash path;

%% Start or reuse one process pool before entering the driver

poolBefore = gcp("nocreate");

if isempty(poolBefore)
    poolBefore = parpool("Processes");
elseif isa(poolBefore,"parallel.ThreadPool")
    error("testParallelGaMultiRun:ThreadPool", ...
        ["An existing thread-based pool is active. This test checks " ...
         "process-pool reuse; close the thread pool and rerun."]);
end

initialWorkerCount = poolBefore.NumWorkers;
fprintf("Parallel GA smoke test using existing pool: %d workers.\n", ...
    initialWorkerCount);

%% Three-run parallel smoke test (shared pool, no per-run restart)

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

%% Verify callback FE, best-so-far results, seeds, and no pool restarts

assert(studyState.numberOfRuns == 3, ...
    "Expected three independent GA runs.");

expectedSeeds = (1000:1002).';
actualSeeds = zeros(3,1);

for runIndex = 1:3
    runState = studyState.runStates{runIndex};
    actualSeeds(runIndex) = runState.seed;

    assert(runState.usedParallel, ...
        "Run %d did not use parallel evaluation.",runIndex);
    assert(~runState.parallelRestartEachRun, ...
        "Run %d requested a per-run pool restart.",runIndex);
    assert(runState.parallelRetryCount == 0 && ...
        ~runState.parallelPoolRestarted, ...
        "Run %d restarted the pool after a dispatch failure.",runIndex);

    assert(runState.searchFunctionEvaluations == 120, ...
        "Run %d did not reach 120 callback FE.",runIndex);
    assert(runState.history.fe(end) == 120, ...
        "Run %d callback history does not end at 120 FE.",runIndex);
    assert(all(diff(runState.history.fe) > 0), ...
        "Run %d callback FE history is not strictly increasing.",runIndex);
    assert(all(diff(runState.history.bestJ) <= 1e-12), ...
        "Run %d best-so-far objective is not monotonic.",runIndex);
    assert(abs(runState.history.bestJ(end)-runState.bestObjective) <= ...
        1e-10*max(1,abs(runState.bestObjective)), ...
        "Run %d stored network is not the best-so-far incumbent.",runIndex);
    assert(numel(unique(runState.bestSensorIndices)) == 3, ...
        "Run %d returned duplicate sensor indices.",runIndex);
end

assert(isequal(actualSeeds,expectedSeeds), ...
    "Independent optimizer seeds are incorrect.");

%% Verify that the exact same pool remains open after all runs

poolAfter = gcp("nocreate");

assert(~isempty(poolAfter), ...
    "Shared parallel pool was closed by the optimization study.");
assert(isequal(poolAfter,poolBefore), ...
    "The process pool was replaced during the three-run study.");
assert(poolAfter.NumWorkers == initialWorkerCount, ...
    "The process pool worker count changed during the study.");

fprintf("\n");
fprintf("Shared-pool parallel GA smoke test passed.\n");
fprintf("  Runs:          3\n");
fprintf("  Callback FE:   120 per run\n");
fprintf("  Seeds:         1000 through 1002\n");
fprintf("  Pool reuse:    same process pool throughout\n");
fprintf("  Pool remains:  open (%d workers)\n",poolAfter.NumWorkers);
fprintf("  Incumbent:     preserved\n");
fprintf("\n");
fprintf("testParallelGaMultiRun passed.\n");

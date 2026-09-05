%% testParallelGaMultiRun
% Exercise repeated parallel GA calls with fresh process pools before running
% the longer 10 x 1200-FE pilot.
%
% This is intentionally small: three independent 120-FE runs with a 60-member
% population. It verifies worker dispatch, pool restart/cleanup, optimizer seed
% sequencing, exact FE accounting, and best-so-far incumbent preservation.

clear;
clc;

%% Project paths

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
addpath(fullfile(projectRoot,"src"));
addpath(fullfile(projectRoot,"scripts"));
rehash path;

%% Ensure the test begins without a stale pool

pool = gcp("nocreate");
if ~isempty(pool)
    delete(pool);
end

%% Three-run parallel smoke test

config = struct();
config.networkSize = 3;
config.objectiveMode = "coverage";
config.functionEvaluationBudget = 120;
config.populationSize = 60;
config.numberOfRuns = 3;
config.baseSeed = 1000;
config.useParallel = true;
config.parallelRestartEachRun = true;
config.closeParallelPoolAtEnd = true;
config.useParallelDatabaseConstant = true;
config.display = "off";
config.studyName = "parallel_ga_multirun_smoke_test";

studyState = runGlobalOptimization(config);

%% Checks

assert(studyState.numberOfRuns == 3, ...
    "Expected three independent GA runs.");

expectedSeeds = (1000:1002).';
actualSeeds = zeros(3,1);

for runIndex = 1:3
    runState = studyState.runStates{runIndex};
    actualSeeds(runIndex) = runState.seed;

    assert(runState.searchFunctionEvaluations == 120, ...
        "Run %d did not reach 120 FE.",runIndex);
    assert(runState.history.fe(end) == 120, ...
        "Run %d history does not end at 120 FE.",runIndex);
    assert(all(diff(runState.history.fe) > 0), ...
        "Run %d FE history is not strictly increasing.",runIndex);
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

% Per-run restart mode should leave no pool alive after the study.
pool = gcp("nocreate");
assert(isempty(pool), ...
    "Parallel pool should be closed after the repeated-run smoke test.");

fprintf("\n");
fprintf("Repeated parallel GA smoke test passed.\n");
fprintf("  Runs:          3\n");
fprintf("  FE per run:    120\n");
fprintf("  Seeds:         1000 through 1002\n");
fprintf("  Pool cleanup:  passed\n");
fprintf("  Incumbent:     preserved\n");
fprintf("\n");
fprintf("testParallelGaMultiRun passed.\n");

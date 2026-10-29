function comparison = runOptimizerComparisonTrial(objectiveMode)
% RUNOPTIMIZERCOMPARISONTRIAL - Compare four optimizers using three seeds and 1200 FE per run.
%
% Inputs:
%   - objectiveMode - "information" only.
%
% Outputs:
%   - comparison - Per-run metrics and saved CSV/MAT report paths.
%
% Notes:
%   - Uses GA, SURROGATE, PSO, and ABC with one shared process pool.

arguments
    objectiveMode (1,1) string = "information"
end

objectiveMode = lower(strtrim(objectiveMode));
assert(objectiveMode == "information", ...
    'Only information gain is supported for optimization.');

projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(genpath(fullfile(projectRoot,"scripts")));
addpath(fullfile(projectRoot,"src"));

databaseFile = fullfile(projectRoot,"results","optimization_database.mat");
assert(isfile(databaseFile), ...
    "Required frozen lunar optimization database is missing:\n%s", ...
    databaseFile);

optimizers = ["GA","SURROGATE","PSO","ABC"];
networkSize = 3;
numberOfRuns = 3;
feBudget = 1200;
populationSize = 60;
baseSeed = 1000;
expectedSeeds = (baseSeed:baseSeed+numberOfRuns-1).';
totalRuns = numel(optimizers)*numberOfRuns;

% Configure the production driver identically for all four solvers.
baseConfig = struct();
baseConfig.databaseFile = databaseFile;
baseConfig.networkSize = networkSize;
baseConfig.objectiveMode = objectiveMode;
baseConfig.functionEvaluationBudget = feBudget;
baseConfig.populationSize = populationSize;
baseConfig.numberOfRuns = numberOfRuns;
baseConfig.baseSeed = baseSeed;
baseConfig.useParallel = true;
baseConfig.parallelRestartEachRun = false;
baseConfig.parallelRetryOnFailure = true;
baseConfig.closeParallelPoolAtEnd = false;
baseConfig.useParallelDatabaseConstant = true;
baseConfig.display = "off";
baseConfig.studyName = "lunar_optimizer_comparison_3x1200_n3";

% Compact per-run reporting (each driver call saves the full study).
method = strings(totalRuns,1);
runNumber = zeros(totalRuns,1);
seed = zeros(totalRuns,1);
callbackFE = zeros(totalRuns,1);
solverFE = zeros(totalRuns,1);
bestObjective = zeros(totalRuns,1);
informationScore = zeros(totalRuns,1);
coverageScore = zeros(totalRuns,1);
runtimeSeconds = zeros(totalRuns,1);
parallelRetries = zeros(totalRuns,1);
studyDirectories = strings(numel(optimizers),1);
sharedPool = [];

fprintf("\n============================================================\n");
fprintf("Optimizer comparison: Ns=%d, %d runs x %d FE per method\n", ...
    networkSize,numberOfRuns,feBudget);
fprintf("Objective: %s | Seed sequence: %d to %d\n", ...
    objectiveMode,expectedSeeds(1),expectedSeeds(end));
fprintf("Methods: GA, SURROGATE, PSO, ABC | Shared parallel pool\n");
fprintf("============================================================\n");

for optimizerIndex = 1:numel(optimizers)
    solverName = optimizers(optimizerIndex);
    config = baseConfig;
    config.optimizer = solverName;

    fprintf("\n========== Starting %s (%d of %d) ==========\n", ...
        solverName,optimizerIndex,numel(optimizers));

    studyState = runGlobalOptimization(config);
    studyDirectories(optimizerIndex) = string(studyState.studyDirectory);

    % Check that the same process pool is reused BETWEEN optimizers.
    currentPool = gcp("nocreate");
    assert(~isempty(currentPool) && ...
        ~isa(currentPool,"parallel.ThreadPool"), ...
        "%s left no active process-based parallel pool.",solverName);
    if isempty(sharedPool)
        sharedPool = currentPool;
    else
        assert(isequal(currentPool,sharedPool), ...
            "Parallel pool was unexpectedly replaced between methods.");
    end

    assert(studyState.numberOfRuns == numberOfRuns, ...
        "%s did not complete all three independent runs.",solverName);
    assert(studyState.config.networkSize == networkSize && ...
        studyState.config.functionEvaluationBudget == feBudget && ...
        string(studyState.config.objectiveMode) == objectiveMode, ...
        "Study configuration changed unexpectedly for %s.",solverName);
    assert(isfile(fullfile(studyDirectories(optimizerIndex), ...
        "study_summary.mat")), ...
        "%s did not save study_summary.mat.",solverName);

    for runIndex = 1:numberOfRuns
        state = studyState.runStates{runIndex};
        row = (optimizerIndex-1)*numberOfRuns + runIndex;

        assert(string(state.optimizer) == solverName && ...
            string(state.objectiveMode) == objectiveMode && ...
            state.networkSize == networkSize, ...
            "%s run %d has inconsistent metadata.",solverName,runIndex);
        assert(state.seed == expectedSeeds(runIndex), ...
            "%s run %d used the wrong independent seed.",solverName,runIndex);
        assert(state.searchFunctionEvaluations == feBudget, ...
            "%s run %d finished at %d callback FE, expected %d.", ...
            solverName,runIndex,state.searchFunctionEvaluations,feBudget);
        assert(isfinite(state.solverFunctionEvaluations) && ...
            state.solverFunctionEvaluations >= feBudget, ...
            "%s run %d has invalid raw solver FE.",solverName,runIndex);

        assert(isfield(state.history,"fe") && ...
            isfield(state.history,"bestJ") && ...
            ~isempty(state.history.fe), ...
            "%s run %d has no callback convergence history.", ...
            solverName,runIndex);
        historyFE = double(state.history.fe(:));
        historyJ = double(state.history.bestJ(:));
        assert(numel(historyFE) == numel(historyJ) && ...
            historyFE(end) == feBudget && ...
            all(historyFE > 0 & historyFE <= feBudget) && ...
            all(diff(historyFE) > 0), ...
            "%s run %d has inconsistent callback FE checkpoints.", ...
            solverName,runIndex);
        assert(all(isfinite(historyJ)) && ...
            all(diff(historyJ) <= 1e-10) && ...
            abs(historyJ(end)-state.bestObjective) <= ...
            1e-10*max(1,abs(state.bestObjective)), ...
            "%s run %d failed best-so-far history validation.", ...
            solverName,runIndex);

        sensorIDs = double(state.bestSensorIndices(:));
        assert(numel(sensorIDs) == networkSize && ...
            all(sensorIDs == round(sensorIDs)) && ...
            all(diff(sensorIDs) > 0) && ...
            all(sensorIDs >= 1) && ...
            all(sensorIDs <= state.numberOfCandidates), ...
            "%s run %d returned an invalid sensor network.", ...
            solverName,runIndex);
        assert(isfinite(state.bestObjective) && ...
            isfinite(state.bestInformationScore) && ...
            isfinite(state.bestCoverageScore), ...
            "%s run %d has nonfinite optimization metrics.", ...
            solverName,runIndex);
        assert(state.usedParallel && ...
            ~state.parallelRestartEachRun && ...
            state.parallelRetryCount == 0 && ...
            ~state.parallelPoolRestarted, ...
            "%s run %d did not preserve the shared process pool.", ...
            solverName,runIndex);
        assert(isfile(fullfile(studyDirectories(optimizerIndex), ...
            sprintf("run_%03d.mat",runIndex))), ...
            "%s run %d was not saved.",solverName,runIndex);

        method(row) = solverName;
        runNumber(row) = runIndex;
        seed(row) = state.seed;
        callbackFE(row) = state.searchFunctionEvaluations;
        solverFE(row) = state.solverFunctionEvaluations;
        bestObjective(row) = state.bestObjective;
        informationScore(row) = state.bestInformationScore;
        coverageScore(row) = state.bestCoverageScore;
        runtimeSeconds(row) = state.runtimeSeconds;
        parallelRetries(row) = state.parallelRetryCount;
    end

    % Avoid retaining duplicate study data; the full files are on disk.
    clear studyState
end

% Summarize all 12 runs in a MATLAB table and files.
runResults = table(method,runNumber,seed,callbackFE,solverFE, ...
    bestObjective,informationScore,coverageScore,runtimeSeconds, ...
    parallelRetries);

reportFolder = fullfile(projectRoot,"results","optimization_runs");
reportTag = string(datetime("now","Format","yyyyMMdd_HHmmss_SSS"));
reportBase = fullfile(reportFolder, ...
    "optimizer_comparison_n3_3x1200_" + objectiveMode + "_" + reportTag);
csvPath = reportBase + ".csv";
matPath = reportBase + ".mat";

comparison = struct();
comparison.version = "lunar_optimizer_trial_n3_3x1200_v1";
comparison.objectiveMode = objectiveMode;
comparison.networkSize = networkSize;
comparison.numberOfRunsPerOptimizer = numberOfRuns;
comparison.functionEvaluationBudget = feBudget;
comparison.populationSize = populationSize;
comparison.seeds = expectedSeeds;
comparison.optimizers = optimizers;
comparison.studyDirectories = studyDirectories;
comparison.runResults = runResults;
comparison.csvFile = csvPath;
comparison.matFile = matPath;

writetable(runResults,csvPath);
save(matPath,"comparison");

fprintf("\n============================================================\n");
fprintf("All 12 optimizer trial runs passed the end-to-end assertions.\n");
fprintf("Shared parallel process pool remains open.\n");
fprintf("Comparison CSV: %s\n",csvPath);
fprintf("MATLAB summary: %s\n",matPath);
fprintf("============================================================\n");
disp(runResults);
end

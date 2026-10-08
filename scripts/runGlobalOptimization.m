function studyState = runGlobalOptimization(userConfig)
% RUNGLOBALOPTIMIZATION
% Run discrete lunar-surface sensor-network optimization using a frozen
% precomputed optimization database.
%
% The decision vector contains candidate-site indices
%
%       x = [i1,i2,...,iNs]
%
% with strictly increasing integer indices, so duplicate sensors and
% permutation-equivalent networks are not intentionally searched.
%
% A common function-evaluation (FE) budget and discrete design problem are
% shared across solvers. The original GA search and its exact FE accounting
% live in optimization.runGA; new methods implement the same result contract.
%
% % Parallel execution normally follows the same efficient pattern used by the
% related cislunar gradient-free study: create/reuse one process pool for the
% complete multi-run study and create one worker-local parallel.pool.Constant
% containing the frozen objective database. If MATLAB reports a recoverable
% worker-dispatch failure, the affected run is retried once after rebuilding
% the process pool and worker constant. The optimizer RNG is reset to the same
% run seed before retrying, so the stochastic study definition is preserved.
%
% Example
%
%   config = struct();
%   config.networkSize = 3;
%   config.objectiveMode = "information";
%   config.functionEvaluationBudget = 12000;
%   config.populationSize = 60;
%   config.numberOfRuns = 10;
%   config.useParallel = true;
%   studyState = runGlobalOptimization(config);

arguments
    userConfig (1,1) struct = struct()
end

%% Project paths

thisFile = mfilename("fullpath");
scriptDirectory = fileparts(thisFile);
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);

if ~isfolder(resultsDirectory)
    mkdir(resultsDirectory);
end

%% Configuration

defaultConfig = struct();
defaultConfig.databaseFile = ...
    fullfile(resultsDirectory,"optimization_database.mat");
defaultConfig.optimizer = "GA";
defaultConfig.networkSize = 3;
defaultConfig.objectiveMode = "information";
defaultConfig.functionEvaluationBudget = 12000;
defaultConfig.populationSize = 60;
defaultConfig.numberOfRuns = 1;
defaultConfig.baseSeed = 1000;
defaultConfig.useParallel = false;
defaultConfig.parallelRestartEachRun = false;
defaultConfig.parallelRetryOnFailure = true;
defaultConfig.closeParallelPoolAtEnd = false;
defaultConfig.useParallelDatabaseConstant = true;
defaultConfig.display = "iter";
defaultConfig.studyName = "lunar_surface_global_optimization";

config = mergeStruct(defaultConfig,userConfig);
config.optimizer = upper(string(config.optimizer));
config.objectiveMode = lower(string(config.objectiveMode));

validateattributes(config.networkSize,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.functionEvaluationBudget,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.populationSize,{'numeric'}, ...
    {'scalar','integer','>=',2});
validateattributes(config.numberOfRuns,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.baseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});

logicalFields = [ ...
    "useParallel", ...
    "parallelRestartEachRun", ...
    "parallelRetryOnFailure", ...
    "closeParallelPoolAtEnd", ...
    "useParallelDatabaseConstant" ...
    ];

for fieldIndex = 1:numel(logicalFields)
    fieldName = logicalFields(fieldIndex);
    assert(islogical(config.(fieldName)) && isscalar(config.(fieldName)), ...
        "%s must be a scalar logical.",fieldName);
end

assert(ismember(config.optimizer,["GA","SURROGATE","PSO"]), ...
    "optimizer must be GA, SURROGATE, or PSO.");
assert(ismember(config.objectiveMode,["information","coverage"]), ...
    "objectiveMode must be information or coverage.");


%% Load frozen production database

assert(isfile(config.databaseFile), ...
    "Optimization database not found:\n%s",config.databaseFile);

fprintf("\nLoading optimization database:\n  %s\n",config.databaseFile);

databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "MAT file does not contain database.");
database = databaseData.database;

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

assert(config.networkSize <= numberOfCandidates, ...
    "Requested network exceeds candidate-site count.");

fprintf("\n");
fprintf("============================================================\n");
fprintf("Lunar surface global optimization\n");
fprintf("============================================================\n");
fprintf("Optimizer:             %s\n",config.optimizer);
fprintf("Objective:             %s\n",config.objectiveMode);
fprintf("Network size:          %d\n",config.networkSize);
fprintf("Candidate locations:   %d\n",numberOfCandidates);
fprintf("RSOs:                  %d\n",numberOfObjects);
fprintf("FE budget / run:       %d\n",config.functionEvaluationBudget);
fprintf("Independent runs:      %d\n",config.numberOfRuns);
fprintf("Parallel objective:    %d\n",config.useParallel);

if config.useParallel
    fprintf("Restart pool each run: %d\n",config.parallelRestartEachRun);
    fprintf("Retry parallel failure:%d\n",config.parallelRetryOnFailure);
end

%% Lightweight frozen database used only by the search objective

objectiveDatabase = buildObjectiveDatabase(database);

%% Shared parallel resources

sharedPool = [];
sharedPoolOwned = false;
sharedPoolCleanup = [];
sharedObjectiveDatabaseConstant = [];

if config.useParallel && ~config.parallelRestartEachRun
    [sharedPool,poolWasCreated] = ensureProcessPool(false);
    sharedPoolOwned = poolWasCreated;

    if config.useParallelDatabaseConstant
        fprintf("Loading frozen objective database on parallel workers...\n");
        sharedObjectiveDatabaseConstant = ...
            parallel.pool.Constant(objectiveDatabase);
    end

    if config.closeParallelPoolAtEnd
        sharedPoolCleanup = onCleanup(@cleanupOwnedSharedPool);
    end
end

%% Study output directory

timestamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
studyTag = sprintf("%s_%s_n%d_%s", ...
    lower(config.optimizer),config.objectiveMode,config.networkSize,timestamp);
studyDirectory = fullfile(resultsDirectory,"optimization_runs",studyTag);

assert(~isfolder(studyDirectory), ...
    "Study output directory already exists.");
mkdir(studyDirectory);

%% Shared discrete decision-space formulation

numberOfVariables = config.networkSize;
lowerBounds = ones(1,numberOfVariables);
upperBounds = numberOfCandidates*ones(1,numberOfVariables);
integerVariables = 1:numberOfVariables;

% xi < x(i+1) is xi - x(i+1) <= -1 for integer solutions.
if numberOfVariables > 1
    A = zeros(numberOfVariables-1,numberOfVariables);
    b = -ones(numberOfVariables-1,1);
    for constraintIndex = 1:numberOfVariables-1
        A(constraintIndex,constraintIndex) = 1;
        A(constraintIndex,constraintIndex+1) = -1;
    end
else
    A = [];
    b = [];
end

problem = struct();
problem.nvars = numberOfVariables;
problem.numberOfCandidates = numberOfCandidates;
problem.lb = lowerBounds;
problem.ub = upperBounds;
problem.intcon = integerVariables;
problem.A = A;
problem.b = b;
problem.Aeq = [];
problem.beq = [];
problem.infeasiblePenalty = database.objective.infeasiblePenalty;

%% Run storage

populationSize = config.populationSize;
functionEvaluationBudget = config.functionEvaluationBudget;
runStates = cell(config.numberOfRuns,1);
bestObjectives = NaN(config.numberOfRuns,1);
runTimes = NaN(config.numberOfRuns,1);

%% Independent optimization runs

for runIndex = 1:config.numberOfRuns

    fprintf("\n");
    fprintf("============================================================\n");
    fprintf("Run %d of %d\n",runIndex,config.numberOfRuns);
    fprintf("============================================================\n");

    runSeed = config.baseSeed + runIndex - 1;
    rng(runSeed,"twister");


    %% Parallel resources for this run

    runPoolCleanup = [];
    activeDatabaseConstant = [];

    if config.useParallel && config.parallelRestartEachRun
        fprintf("\nRefreshing process-based pool for run %d...\n",runIndex);
        [runPool,~] = ensureProcessPool(true);
        runPoolCleanup = onCleanup(@() cleanupParallelPool(runPool));

        if config.useParallelDatabaseConstant
            activeDatabaseConstant = ...
                parallel.pool.Constant(objectiveDatabase);
        end

    elseif config.useParallel
        % If a shared pool vanished unexpectedly between runs, rebuild the
        % shared worker resources once and continue.
        currentPool = gcp("nocreate");

        if isempty(currentPool) || isa(currentPool,"parallel.ThreadPool")
            sharedObjectiveDatabaseConstant = [];
            [sharedPool,poolWasCreated] = ensureProcessPool(false);
            sharedPoolOwned = sharedPoolOwned || poolWasCreated;

            if config.useParallelDatabaseConstant
                sharedObjectiveDatabaseConstant = ...
                    parallel.pool.Constant(objectiveDatabase);
            end
        else
            sharedPool = currentPool;
        end

        if config.useParallelDatabaseConstant
            activeDatabaseConstant = sharedObjectiveDatabaseConstant;
        end
    end

    objectiveFunction = buildObjectiveFunction(activeDatabaseConstant);

    %% Execute the selected solver, retaining the shared-pool retry policy

    parallelRetryCount = 0;
    parallelPoolRestarted = false;
    runTimer = tic;

    try
        solverResult = optimization.runOptimizer( ...
            objectiveFunction,problem,config);
    catch optimizerError
        canRetry = ...
            config.useParallel && ...
            ~config.parallelRestartEachRun && ...
            config.parallelRetryOnFailure && ...
            isRecoverableParallelDispatchError(optimizerError);
        if ~canRetry
            rethrow(optimizerError);
        end
        parallelRetryCount = 1;
        parallelPoolRestarted = true;
        fprintf("\nRecoverable parallel %s dispatch failure detected.\n", ...
            config.optimizer);
        fprintf("Restarting the process pool and retrying run %d once...\n", ...
            runIndex);

        objectiveFunction = [];
        activeDatabaseConstant = [];
        sharedObjectiveDatabaseConstant = [];
        [sharedPool,~] = ensureProcessPool(true);
        sharedPoolOwned = true;
        if config.useParallelDatabaseConstant
            sharedObjectiveDatabaseConstant = ...
                parallel.pool.Constant(objectiveDatabase);
            activeDatabaseConstant = sharedObjectiveDatabaseConstant;
        end
        objectiveFunction = buildObjectiveFunction(activeDatabaseConstant);
        rng(runSeed,"twister");
        solverResult = optimization.runOptimizer( ...
            objectiveFunction,problem,config);
    end

    runtimeSeconds = toc(runTimer);

    % Release per-run worker resources before deleting a per-run pool.
    objectiveFunction = [];
    activeDatabaseConstant = [];

    if ~isempty(runPoolCleanup)
        clear runPoolCleanup
    end

    %% Validate standardized result and candidate-site feasibility

    requiredFields = ["x","fval","exitflag","output", ...
        "functionEvaluations","history"];
    assert(all(isfield(solverResult,cellstr(requiredFields))), ...
        "Optimizer returned an incomplete standard result.");

    candidateX = double(solverResult.x(:));
    assert(numel(candidateX) == config.networkSize && ...
        all(isfinite(candidateX)), ...
        "Optimizer did not return one finite index per sensor.");
    if config.optimizer == "PSO"
        candidateX = round(candidateX);
    else
        assert(all(candidateX == round(candidateX)), ...
            "Discrete optimizer returned noninteger indices.");
    end
    bestSensorIndices = sort(candidateX);
    bestObjective = double(solverResult.fval);

    assert(isscalar(bestObjective) && isfinite(bestObjective), ...
        "Optimizer returned no finite objective.");
    assert(numel(unique(bestSensorIndices)) == config.networkSize, ...
        "Optimizer returned duplicate candidate indices.");
    assert(all(bestSensorIndices >= 1) && ...
        all(bestSensorIndices <= numberOfCandidates), ...
        "Optimizer returned invalid candidate indices.");

    assert(isfield(solverResult.history,"fe") && ...
        isfield(solverResult.history,"bestJ"), ...
        "Optimizer must return history.fe and history.bestJ.");
    historyFe = double(solverResult.history.fe(:));
    historyBestJ = double(solverResult.history.bestJ(:));
    assert(~isempty(historyFe) && numel(historyFe) == numel(historyBestJ), ...
        "Optimizer convergence history is empty or inconsistent.");
    assert(all(isfinite(historyFe)) && ...
        all(historyFe > 0 & historyFe == round(historyFe)) && ...
        all(diff(historyFe) > 0), ...
        "FE history must contain strictly increasing integer counts.");
    assert(all(diff(historyBestJ) <= 1e-10), ...
        "Best-so-far history must be nonincreasing.");
    if isfield(solverResult.history,"generation")
        historyGeneration = double(solverResult.history.generation(:));
    else
        historyGeneration = NaN(size(historyFe));
    end
    assert(numel(historyGeneration) == numel(historyFe), ...
        "Optimizer iteration history length mismatch.");

    %% Diagnostic evaluation outside the search FE budget

    [diagnosticObjective,bestDetails] = ...
        optimization.networkObjective( ...
            bestSensorIndices,database,config.objectiveMode);

    objectiveTolerance = 1e-10*max(1,abs(bestObjective));
    assert(abs(diagnosticObjective-bestObjective) <= objectiveTolerance, ...
        "Final diagnostic objective does not match the optimizer incumbent.");

    assert(~isempty(historyBestJ) && ...
        abs(historyBestJ(end)-bestObjective) <= objectiveTolerance, ...
        "Convergence history does not end at the stored incumbent.");

    %% Candidate coordinates

    bestLatitudesRad = database.candidates.latitudesRad(bestSensorIndices);
    bestLongitudesRad = database.candidates.longitudesRad(bestSensorIndices);
    bestLatitudesDeg = rad2deg(bestLatitudesRad);
    bestLongitudesDeg = rad2deg(bestLongitudesRad);

    bestSensorTable = table( ...
        (1:config.networkSize).', ...
        bestSensorIndices, ...
        bestLatitudesDeg, ...
        bestLongitudesDeg, ...
        'VariableNames',{ ...
            'Sensor','CandidateIndex','LatitudeDeg','LongitudeDeg'});

    %% Standard FE audit: GA remains exact; other solvers report actual FE

    searchFunctionEvaluations = double(solverResult.functionEvaluations);
    assert(isscalar(searchFunctionEvaluations) && ...
        isfinite(searchFunctionEvaluations) && ...
        searchFunctionEvaluations > 0 && ...
        searchFunctionEvaluations == round(searchFunctionEvaluations), ...
        "Optimizer must report a positive integer FE count.");
    assert(historyFe(end) <= searchFunctionEvaluations, ...
        "FE history cannot exceed the reported FE count.");
    if isfield(solverResult,"solverFunctionEvaluations")
        solverFunctionEvaluations = ...
            double(solverResult.solverFunctionEvaluations);
    elseif isfield(solverResult.output,"funccount")
        solverFunctionEvaluations = ...
            double(solverResult.output.funccount);
    else
        solverFunctionEvaluations = searchFunctionEvaluations;
    end

    if config.optimizer == "GA"
        assert(searchFunctionEvaluations == functionEvaluationBudget, ...
            "GA callback history did not reach the requested FE budget.");
    elseif searchFunctionEvaluations > functionEvaluationBudget
        warning("runGlobalOptimization:FeBudgetOvershoot", ...
            "%s used %d FE against a %d-FE budget; report actual FE.", ...
            config.optimizer,searchFunctionEvaluations,functionEvaluationBudget);
    end

    %% Run state

    runState = struct();
    runState.version = "lunar_global_optimization_run_v3_shared_pool";
    runState.created = string(datetime("now"));
    runState.studyName = string(config.studyName);
    runState.runIndex = runIndex;
    runState.seed = runSeed;
    runState.optimizer = config.optimizer;
    runState.objectiveMode = config.objectiveMode;
    runState.networkSize = config.networkSize;
    runState.databaseFile = string(config.databaseFile);
    runState.databaseVersion = string(database.meta.version);
    runState.numberOfCandidates = numberOfCandidates;
    runState.numberOfObjects = numberOfObjects;
    runState.functionEvaluationBudget = functionEvaluationBudget;
    runState.populationSize = populationSize;
    runState.numberOfGenerations = NaN;
    if isfield(solverResult,"numberOfGenerations")
        runState.numberOfGenerations = solverResult.numberOfGenerations;
    end
    runState.searchFunctionEvaluations = searchFunctionEvaluations;
    runState.solverFunctionEvaluations = solverFunctionEvaluations;
    runState.bestSensorIndices = bestSensorIndices;
    runState.bestSensorLatitudesRad = bestLatitudesRad;
    runState.bestSensorLongitudesRad = bestLongitudesRad;
    runState.bestSensorTable = bestSensorTable;
    runState.bestObjective = bestObjective;
    runState.bestInformationScore = bestDetails.informationScore;
    runState.bestCoverageScore = bestDetails.coverageScore;
    runState.informationByObject = bestDetails.informationByObject;
    runState.coverageByObject = bestDetails.coverageByObject;
    runState.runtimeSeconds = runtimeSeconds;
    runState.exitFlag = solverResult.exitflag;
    runState.solverOutput = solverResult.output;
    runState.solverFinalBestX = [];
    runState.solverFinalBestObjective = NaN;
    runState.finalPopulation = [];
    runState.finalScores = [];
    if isfield(solverResult,"solverFinalBestX")
        runState.solverFinalBestX = solverResult.solverFinalBestX;
    end
    if isfield(solverResult,"solverFinalBestObjective")
        runState.solverFinalBestObjective = ...
            solverResult.solverFinalBestObjective;
    end
    if isfield(solverResult,"finalPopulation")
        runState.finalPopulation = solverResult.finalPopulation;
    end
    if isfield(solverResult,"finalScores")
        runState.finalScores = solverResult.finalScores;
    end
    runState.usedParallel = config.useParallel;
    runState.parallelRestartEachRun = config.parallelRestartEachRun;
    runState.parallelRetryCount = parallelRetryCount;
    runState.parallelPoolRestarted = parallelPoolRestarted;
    runState.history = struct();
    runState.history.fe = historyFe;
    runState.history.bestJ = historyBestJ;
    runState.history.generation = historyGeneration;
    runState.config = config;

    %% Save individual run

    runFile = fullfile(studyDirectory,sprintf("run_%03d.mat",runIndex));
    save(runFile,"runState","-v7.3");

    runStates{runIndex} = runState;
    bestObjectives(runIndex) = bestObjective;
    runTimes(runIndex) = runtimeSeconds;

    %% Console summary

    fprintf("\nRun %d complete\n",runIndex);
    fprintf("----------------------------------\n");
    fprintf("Seed:                 %d\n",runSeed);
    fprintf("Search FE:            %d\n",searchFunctionEvaluations);

    if isfinite(solverFunctionEvaluations)
        fprintf("Solver calls:          %d\n",solverFunctionEvaluations);
    end

    if parallelRetryCount > 0
        fprintf("Parallel retries:      %d\n",parallelRetryCount);
    end

    fprintf("Best objective J:      %.12g\n",bestObjective);
    fprintf("Information score:     %.8f\n",bestDetails.informationScore);
    fprintf("Coverage score:        %.0f\n",bestDetails.coverageScore);
    fprintf("Runtime:               %.2f min\n",runtimeSeconds/60);
    fprintf("\nBest sensor network\n");
    disp(bestSensorTable);
end

%% Release shared worker data and owned pool

sharedObjectiveDatabaseConstant = [];

if ~isempty(sharedPoolCleanup)
    clear sharedPoolCleanup
end

%% Aggregate study results

[overallBestObjective,overallBestRunIndex] = min(bestObjectives);
overallBestRunState = runStates{overallBestRunIndex};

studyState = struct();
studyState.version = "lunar_global_optimization_study_v3_shared_pool";
studyState.created = string(datetime("now"));
studyState.studyDirectory = string(studyDirectory);
studyState.config = config;
studyState.numberOfRuns = config.numberOfRuns;
studyState.runStates = runStates;
studyState.bestObjectives = bestObjectives;
studyState.runTimesSeconds = runTimes;
studyState.meanBestObjective = mean(bestObjectives);
studyState.stdBestObjective = std(bestObjectives);
studyState.meanRuntimeSeconds = mean(runTimes);
studyState.stdRuntimeSeconds = std(runTimes);
studyState.overallBestRunIndex = overallBestRunIndex;
studyState.overallBestObjective = overallBestObjective;
studyState.overallBestSensorIndices = overallBestRunState.bestSensorIndices;
studyState.overallBestSensorTable = overallBestRunState.bestSensorTable;
studyState.overallBestInformationScore = ...
    overallBestRunState.bestInformationScore;
studyState.overallBestCoverageScore = ...
    overallBestRunState.bestCoverageScore;
studyState.parallelRetryCounts = cellfun( ...
    @(runState) runState.parallelRetryCount,runStates);

%% Save study summary

summaryFile = fullfile(studyDirectory,"study_summary.mat");
save(summaryFile,"studyState","-v7.3");

%% Final console summary

fprintf("\n");
fprintf("============================================================\n");
fprintf("Global optimization study complete\n");
fprintf("============================================================\n");
fprintf("Optimizer:              %s\n",config.optimizer);
fprintf("Objective:              %s\n",config.objectiveMode);
fprintf("Network size:           %d\n",config.networkSize);
fprintf("Independent runs:       %d\n",config.numberOfRuns);
fprintf("FE budget / run:        %d\n",config.functionEvaluationBudget);
fprintf("Mean best J:            %.12g\n",studyState.meanBestObjective);
fprintf("Std best J:             %.12g\n",studyState.stdBestObjective);
fprintf("Parallel retries:       %d\n",sum(studyState.parallelRetryCounts));
fprintf("Best run:               %d\n",overallBestRunIndex);
fprintf("Overall best J:         %.12g\n",overallBestObjective);
fprintf("Information score:      %.8f\n", ...
    studyState.overallBestInformationScore);
fprintf("Coverage score:         %.0f\n", ...
    studyState.overallBestCoverageScore);
fprintf("\nOverall best network\n");
disp(studyState.overallBestSensorTable);
fprintf("Results saved to:\n  %s\n",studyDirectory);

%% Nested helpers for objective handles and pool cleanup

    function objectiveFunctionHandle = ...
            buildObjectiveFunction(databaseConstant)

        if config.useParallel && config.useParallelDatabaseConstant
            assert(~isempty(databaseConstant), ...
                "Parallel objective database constant is unavailable.");

            objectiveFunctionHandle = @(sensorIndices) ...
                optimization.networkObjectiveFromConstant( ...
                    sensorIndices,databaseConstant,config.objectiveMode);
        else
            objectiveFunctionHandle = @(sensorIndices) ...
                optimization.networkObjective( ...
                    sensorIndices,objectiveDatabase,config.objectiveMode);
        end
    end

    function cleanupOwnedSharedPool()
        if ~sharedPoolOwned
            return
        end

        currentPool = gcp("nocreate");
        if ~isempty(currentPool)
            fprintf("\nClosing process-based parallel pool created by this study...\n");
            cleanupParallelPool(currentPool);
        end
    end

end

%% Local helpers

function output = mergeStruct(defaults,override)

output = defaults;
fields = fieldnames(override);

for fieldIndex = 1:length(fields)
    fieldName = fields{fieldIndex};
    overrideValue = override.(fieldName);

    if isfield(output,fieldName) && ...
            isstruct(output.(fieldName)) && isscalar(output.(fieldName)) && ...
            isstruct(overrideValue) && isscalar(overrideValue)
        output.(fieldName) = mergeStruct(output.(fieldName),overrideValue);
    else
        output.(fieldName) = overrideValue;
    end
end
end

function objectiveDatabase = buildObjectiveDatabase(database)
% BUILDOBJECTIVEDATABASE Retain only fields required by networkObjective.

objectiveDatabase = struct();
objectiveDatabase.meta = database.meta;
objectiveDatabase.study = database.study;
objectiveDatabase.objective = database.objective;

objectiveDatabase.visibility = struct();
objectiveDatabase.tracking = struct();

isChunked = ...
    isfield(database.tracking,"measurementJacobianChunks") && ...
    ~isempty(database.tracking.measurementJacobianChunks);

if isChunked
    objectiveDatabase.visibility.candidateChunks = ...
        database.visibility.candidateChunks;

    objectiveDatabase.tracking.measurementJacobianChunks = ...
        database.tracking.measurementJacobianChunks;

    objectiveDatabase.candidates = struct();
    objectiveDatabase.candidates.chunkIndex = ...
        database.candidates.chunkIndex;
    objectiveDatabase.candidates.chunkLocalIndex = ...
        database.candidates.chunkLocalIndex;
    objectiveDatabase.candidates.originalChunkLocalIndex = ...
        database.candidates.originalChunkLocalIndex;
else
    objectiveDatabase.visibility.filteredAvailability = ...
        database.visibility.filteredAvailability;
    objectiveDatabase.visibility.candidateChunks = struct([]);

    objectiveDatabase.tracking.measurementJacobianHistories = ...
        database.tracking.measurementJacobianHistories;
    objectiveDatabase.tracking.measurementJacobianChunks = struct([]);
end

objectiveDatabase.tracking.stateTransitionHistories = ...
    database.tracking.stateTransitionHistories;
objectiveDatabase.tracking.processNoiseHistories = ...
    database.tracking.processNoiseHistories;

objectiveDatabase.prior = struct();
objectiveDatabase.prior.initialCovariances = ...
    database.prior.initialCovariances;

objectiveDatabase.measurement = struct();
objectiveDatabase.measurement.covariance = ...
    database.measurement.covariance;

objectiveDatabase.estimation = struct();
objectiveDatabase.estimation.stateScales = ...
    database.estimation.stateScales;
objectiveDatabase.estimation.objectWeights = ...
    database.estimation.objectWeights;
end

function [pool,poolWasCreated] = ensureProcessPool(forceRestart)
% ENSUREPROCESSPOOL Return a process-based pool.

pool = gcp("nocreate");
poolWasCreated = false;

if forceRestart && ~isempty(pool)
    delete(pool);
    pool = [];
end

if ~isempty(pool) && isa(pool,"parallel.ThreadPool")
    fprintf("Existing thread-based pool detected; replacing it.\n");
    delete(pool);
    pool = [];
end

if isempty(pool)
    pool = parpool("Processes");
    poolWasCreated = true;
end
end

function cleanupParallelPool(pool)
% CLEANUPPARALLELPOOL Best-effort deletion of an owned pool.

if isempty(pool)
    return
end

try
    delete(pool);
catch cleanupError
    warning( ...
        "runGlobalOptimization:PoolCleanupFailed", ...
        "Unable to delete the optimization parallel pool: %s", ...
        cleanupError.message);
end
end

function tf = isRecoverableParallelDispatchError(errorObject)
% ISRECOVERABLEPARALLELDISPATCHERROR Restrict automatic retry to worker/
% pool dispatch failures rather than retrying arbitrary objective errors.

messageText = lower(string(errorObject.message));
stackNames = strings(0,1);

if ~isempty(errorObject.stack)
    stackNames = lower(string({errorObject.stack.name})).';
end

tf = ...
    contains(messageText,"selected parallel environment") || ...
    any(contains(stackNames,"setoptimfcnhandleonworkers")) || ...
    (contains(messageText,"parallel pool") && ...
        (contains(messageText,"shut") || ...
         contains(messageText,"disconnect") || ...
         contains(messageText,"unavailable"))) || ...
    (contains(messageText,"worker") && ...
        (contains(messageText,"disconnect") || ...
         contains(messageText,"unavailable") || ...
         contains(messageText,"failed")));

if tf
    return
end

for causeIndex = 1:numel(errorObject.cause)
    if isRecoverableParallelDispatchError(errorObject.cause{causeIndex})
        tf = true;
        return
    end
end
end

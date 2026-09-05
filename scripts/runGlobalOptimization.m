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
% The search uses a universal function-evaluation (FE) budget. Generation
% zero evaluates the initial population. EliteCount is set to zero so every
% generation consumes one full population of objective evaluations. Because
% this allows MATLAB GA to lose a previously discovered best individual, an
% explicit best-so-far incumbent is recorded by the OutputFcn and returned as
% the run result. This matches the FE-accounting approach used in the related
% cislunar gradient-free comparison study.
%
% Parallel execution can optionally restart a process-based pool before each
% independent run. This is useful for repeated GA calls in MATLAB releases
% where Global Optimization Toolbox worker-function dispatch can become stale
% across consecutive runs. A parallel.pool.Constant stores the frozen search
% database on the workers so the objective handle does not repeatedly capture
% and serialize the full database.
%
% Example
%
%   config = struct();
%   config.networkSize = 3;
%   config.objectiveMode = "information";
%   config.functionEvaluationBudget = 6000;
%   config.populationSize = 60;
%   config.numberOfRuns = 10;
%   config.useParallel = false;
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
defaultConfig.functionEvaluationBudget = 6000;
defaultConfig.populationSize = 60;
defaultConfig.numberOfRuns = 1;
defaultConfig.baseSeed = 1000;
defaultConfig.useParallel = false;
defaultConfig.parallelRestartEachRun = false;
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

assert(islogical(config.useParallel) && isscalar(config.useParallel), ...
    "useParallel must be a scalar logical.");
assert(islogical(config.parallelRestartEachRun) && ...
    isscalar(config.parallelRestartEachRun), ...
    "parallelRestartEachRun must be a scalar logical.");
assert(islogical(config.closeParallelPoolAtEnd) && ...
    isscalar(config.closeParallelPoolAtEnd), ...
    "closeParallelPoolAtEnd must be a scalar logical.");
assert(islogical(config.useParallelDatabaseConstant) && ...
    isscalar(config.useParallelDatabaseConstant), ...
    "useParallelDatabaseConstant must be a scalar logical.");

assert(config.optimizer == "GA", ...
    "This runner currently implements GA only.");
assert(ismember(config.objectiveMode,["information","coverage"]), ...
    "objectiveMode must be information or coverage.");
assert(mod(config.functionEvaluationBudget,config.populationSize) == 0, ...
    ["For exact GA FE accounting, functionEvaluationBudget must be " ...
     "divisible by populationSize."]);

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
end

%% Lightweight frozen database used only by the search objective

objectiveDatabase = buildObjectiveDatabase(database);

%% Shared parallel pool when per-run restart is disabled

sharedPoolCleanup = [];

if config.useParallel && ~config.parallelRestartEachRun
    [~,poolWasCreated] = ensureProcessPool(false);

    if poolWasCreated && config.closeParallelPoolAtEnd
        ownedPool = gcp("nocreate");
        sharedPoolCleanup = onCleanup(@() cleanupParallelPool(ownedPool));
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

%% GA decision-space definition

numberOfVariables = config.networkSize;
lowerBounds = ones(1,numberOfVariables);
upperBounds = numberOfCandidates*ones(1,numberOfVariables);
integerVariables = 1:numberOfVariables;

% xi < x(i+1) for integer variables is equivalent to
% xi - x(i+1) <= -1.
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

%% Exact GA FE definition

populationSize = config.populationSize;
functionEvaluationBudget = config.functionEvaluationBudget;
numberOfGenerations = functionEvaluationBudget/populationSize - 1;

assert(numberOfGenerations >= 0, ...
    "FE budget must be at least one population.");

%% Run storage

runStates = cell(config.numberOfRuns,1);
bestObjectives = NaN(config.numberOfRuns,1);
runTimes = NaN(config.numberOfRuns,1);

%% Variables owned by the nested GA OutputFcn

historyFe = zeros(0,1);
historyBestJ = zeros(0,1);
historyGeneration = zeros(0,1);
incumbentJ = Inf;
incumbentX = [];

%% Independent optimization runs

for runIndex = 1:config.numberOfRuns

    fprintf("\n");
    fprintf("============================================================\n");
    fprintf("Run %d of %d\n",runIndex,config.numberOfRuns);
    fprintf("============================================================\n");

    runSeed = config.baseSeed + runIndex - 1;
    rng(runSeed,"twister");

    historyFe = zeros(0,1);
    historyBestJ = zeros(0,1);
    historyGeneration = zeros(0,1);
    incumbentJ = Inf;
    incumbentX = [];

    %% Fresh process pool for this run when requested

    runPoolCleanup = [];

    if config.useParallel && config.parallelRestartEachRun
        fprintf("\nRefreshing process-based pool for run %d...\n",runIndex);
        [runPool,~] = ensureProcessPool(true);
        runPoolCleanup = onCleanup(@() cleanupParallelPool(runPool));
    elseif config.useParallel
        % Guard against a pool that disappeared between independent runs.
        [~,~] = ensureProcessPool(false);
    end

    %% Worker-local database constant

    objectiveDatabaseConstant = [];

    if config.useParallel && config.useParallelDatabaseConstant
        objectiveDatabaseConstant = parallel.pool.Constant(objectiveDatabase);
        objectiveFunction = @(sensorIndices) ...
            optimization.networkObjectiveFromConstant( ...
                sensorIndices,objectiveDatabaseConstant,config.objectiveMode);
    else
        objectiveFunction = @(sensorIndices) ...
            optimization.networkObjective( ...
                sensorIndices,objectiveDatabase,config.objectiveMode);
    end

    %% GA options

    gaOptions = optimoptions( ...
        "ga", ...
        "UseParallel",config.useParallel, ...
        "UseVectorized",false, ...
        "Display",config.display, ...
        "PopulationSize",populationSize, ...
        "EliteCount",0, ...
        "MaxGenerations",numberOfGenerations, ...
        "MaxStallGenerations",Inf, ...
        "FunctionTolerance",0, ...
        "ConstraintTolerance",0, ...
        "FitnessLimit",-Inf, ...
        "OutputFcn",@gaOutputFunction);

    %% Run optimizer

    runTimer = tic;

    [solverBestX,solverBestObjective,exitFlag,solverOutput, ...
        finalPopulation,finalScores] = ga( ...
            objectiveFunction, ...
            numberOfVariables, ...
            A,b,[],[], ...
            lowerBounds,upperBounds, ...
            [],integerVariables,gaOptions);

    runtimeSeconds = toc(runTimer);

    % Release the worker-local constant before deleting a per-run pool.
    objectiveDatabaseConstant = [];

    if ~isempty(runPoolCleanup)
        clear runPoolCleanup
    end

    %% Best-so-far incumbent across the complete FE budget

    assert(~isempty(incumbentX) && isfinite(incumbentJ), ...
        "GA did not record a finite best-so-far incumbent.");

    bestSensorIndices = sort(round(incumbentX(:)));
    bestObjective = incumbentJ;

    assert(length(unique(bestSensorIndices)) == config.networkSize, ...
        "GA returned duplicate candidate indices.");
    assert(all(bestSensorIndices >= 1) && ...
        all(bestSensorIndices <= numberOfCandidates), ...
        "GA returned an invalid candidate index.");

    %% Diagnostic evaluation outside the search FE budget

    [diagnosticObjective,bestDetails] = ...
        optimization.networkObjective( ...
            bestSensorIndices,database,config.objectiveMode);

    objectiveTolerance = 1e-10*max(1,abs(bestObjective));
    assert(abs(diagnosticObjective-bestObjective) <= objectiveTolerance, ...
        "Final diagnostic objective does not match the GA incumbent.");

    assert(~isempty(historyBestJ) && ...
        abs(historyBestJ(end)-bestObjective) <= objectiveTolerance, ...
        "Convergence history does not end at the stored GA incumbent.");

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

    %% FE audit

    expectedSearchEvaluations = functionEvaluationBudget;

    if isempty(historyFe)
        searchFunctionEvaluations = 0;
    else
        searchFunctionEvaluations = historyFe(end);
    end

    if isfield(solverOutput,"funccount")
        solverFunctionEvaluations = solverOutput.funccount;
    else
        solverFunctionEvaluations = NaN;
    end

    assert(searchFunctionEvaluations == expectedSearchEvaluations, ...
        "GA callback history did not reach the requested FE budget.");

    %% Run state

    runState = struct();
    runState.version = "lunar_global_optimization_run_v2_incumbent";
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
    runState.numberOfGenerations = numberOfGenerations;
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
    runState.exitFlag = exitFlag;
    runState.solverOutput = solverOutput;
    runState.solverFinalBestX = solverBestX;
    runState.solverFinalBestObjective = solverBestObjective;
    runState.finalPopulation = finalPopulation;
    runState.finalScores = finalScores;
    runState.usedParallel = config.useParallel;
    runState.parallelRestartEachRun = config.parallelRestartEachRun;
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

    fprintf("Best objective J:      %.12g\n",bestObjective);
    fprintf("Information score:     %.8f\n",bestDetails.informationScore);
    fprintf("Coverage score:        %.0f\n",bestDetails.coverageScore);
    fprintf("Runtime:               %.2f min\n",runtimeSeconds/60);
    fprintf("\nBest sensor network\n");
    disp(bestSensorTable);
end

%% Close a shared pool only if this function created and owns it

if ~isempty(sharedPoolCleanup)
    fprintf("\nClosing process-based parallel pool created by this study...\n");
    clear sharedPoolCleanup
end

%% Aggregate study results

[overallBestObjective,overallBestRunIndex] = min(bestObjectives);
overallBestRunState = runStates{overallBestRunIndex};

studyState = struct();
studyState.version = "lunar_global_optimization_study_v2_incumbent";
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
fprintf("Best run:               %d\n",overallBestRunIndex);
fprintf("Overall best J:         %.12g\n",overallBestObjective);
fprintf("Information score:      %.8f\n", ...
    studyState.overallBestInformationScore);
fprintf("Coverage score:         %.0f\n", ...
    studyState.overallBestCoverageScore);
fprintf("\nOverall best network\n");
disp(studyState.overallBestSensorTable);
fprintf("Results saved to:\n  %s\n",studyDirectory);

%% Nested GA output function

    function [state,options,optChanged] = ...
            gaOutputFunction(options,state,flag)
        % Record exact callback FE and the cumulative best feasible
        % individual. With EliteCount=0, MATLAB's final-generation result is
        % not necessarily the best individual seen during the run.

        optChanged = false;

        if ~(strcmp(flag,"init") || strcmp(flag,"iter"))
            return
        end

        values = state.Score(:);
        if isfield(state,"Fitness")
            values = state.Fitness(:);
        end
        values(~isfinite(values)) = Inf;

        [generationBest,generationBestIndex] = min(values);

        if ~isempty(generationBest) && generationBest < incumbentJ
            incumbentJ = generationBest;
            incumbentX = state.Population(generationBestIndex,:);
        end

        if isfield(state,"FunEval") && isfinite(state.FunEval)
            currentFe = min(state.FunEval,functionEvaluationBudget);
        else
            currentFe = min((state.Generation+1)*populationSize, ...
                functionEvaluationBudget);
        end

        if isempty(historyFe) || currentFe > historyFe(end)
            historyFe(end+1,1) = currentFe;
            historyBestJ(end+1,1) = incumbentJ;
            historyGeneration(end+1,1) = state.Generation;
        elseif currentFe == historyFe(end)
            historyBestJ(end) = min(historyBestJ(end),incumbentJ);
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
objectiveDatabase.visibility.filteredAvailability = ...
    database.visibility.filteredAvailability;

objectiveDatabase.tracking = struct();
objectiveDatabase.tracking.measurementJacobianHistories = ...
    database.tracking.measurementJacobianHistories;
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

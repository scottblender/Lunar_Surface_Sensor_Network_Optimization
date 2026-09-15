%RUN_LUNAR_BATCH_ENTRY Stable MATLAB entry point for PowerShell production runs.
% Environment variables are populated by run_full_optimization_study.ps1.

try
    projectRoot = getenv('PROJECT_ROOT');
    networkSize = str2double(getenv('NETWORK_SIZE'));
    objectiveMode = string(getenv('OBJECTIVE_MODE'));
    evalBudget = str2double(getenv('EVAL_BUDGET'));
    populationSize = str2double(getenv('POPULATION_SIZE'));
    numberOfRuns = str2double(getenv('NUMBER_OF_RUNS'));
    baseSeed = str2double(getenv('BASE_SEED'));
    parallelWorkers = str2double(getenv('PARALLEL_WORKERS'));

    assert(~isempty(projectRoot), ...
        'PROJECT_ROOT environment variable is not set.');
    assert(isfolder(projectRoot), ...
        'PROJECT_ROOT does not exist: %s', projectRoot);

    validateattributes(networkSize, {'numeric'}, ...
        {'scalar','integer','positive'});
    assert(ismember(lower(objectiveMode), ["information","coverage"]), ...
        'OBJECTIVE_MODE must be information or coverage.');
    validateattributes(evalBudget, {'numeric'}, ...
        {'scalar','integer','positive'});
    validateattributes(populationSize, {'numeric'}, ...
        {'scalar','integer','>=',2});
    validateattributes(numberOfRuns, {'numeric'}, ...
        {'scalar','integer','positive'});
    validateattributes(baseSeed, {'numeric'}, ...
        {'scalar','integer','nonnegative'});
    validateattributes(parallelWorkers, {'numeric'}, ...
        {'scalar','integer','positive'});

    cd(projectRoot);
    addpath(fullfile(projectRoot,'scripts'));
    addpath(fullfile(projectRoot,'src'));

    % Always begin from a clean process pool for this production case.
    p = gcp('nocreate');
    if ~isempty(p)
        delete(p);
    end

    fprintf('Starting process pool with %d workers...\n', parallelWorkers);
    p = parpool('Processes', parallelWorkers);
    fprintf('Parallel pool ready with %d workers.\n', p.NumWorkers);

    config = struct();
    config.networkSize = networkSize;
    config.objectiveMode = lower(objectiveMode);
    config.functionEvaluationBudget = evalBudget;
    config.populationSize = populationSize;
    config.numberOfRuns = numberOfRuns;
    config.baseSeed = baseSeed;
    config.useParallel = true;
    config.parallelRestartEachRun = false;
    config.parallelRetryOnFailure = true;
    config.closeParallelPoolAtEnd = false;
    config.useParallelDatabaseConstant = true;
    config.display = 'iter';
    config.studyName = 'lunar_surface_production_optimization';

    studyState = runGlobalOptimization(config); %#ok<NASGU>

    % Explicitly release workers before MATLAB -batch exits.
    p = gcp('nocreate');
    if ~isempty(p)
        fprintf('Shutting down parallel pool before MATLAB exit...\n');
        delete(p);
        fprintf('Parallel pool shut down successfully.\n');
    end

catch ME
    % Best-effort worker cleanup on failure, matching the proven cislunar
    % batch-runner pattern.
    try
        p = gcp('nocreate');
        if ~isempty(p)
            delete(p);
        end
    catch
    end

    disp(getReport(ME, 'extended'));
    rethrow(ME);
end

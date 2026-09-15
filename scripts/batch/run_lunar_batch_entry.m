%RUN_LUNAR_BATCH_ENTRY Stable MATLAB entry point for PowerShell production runs.
% Environment variables are populated by run_full_optimization_study.ps1.
% Each MATLAB process executes exactly one independent optimization run,
% matching the proven batch pattern used by the cislunar study.

try
    projectRoot = getenv('PROJECT_ROOT');
    networkSize = str2double(getenv('NETWORK_SIZE'));
    objectiveMode = string(getenv('OBJECTIVE_MODE'));
    evalBudget = str2double(getenv('EVAL_BUDGET'));
    populationSize = str2double(getenv('POPULATION_SIZE'));
    baseSeed = str2double(getenv('BASE_SEED'));

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
    validateattributes(baseSeed, {'numeric'}, ...
        {'scalar','integer','nonnegative'});

    cd(projectRoot);
    addpath(fullfile(projectRoot,'scripts'));
    addpath(fullfile(projectRoot,'src'));

    config = struct();
    config.networkSize = networkSize;
    config.objectiveMode = lower(objectiveMode);
    config.functionEvaluationBudget = evalBudget;
    config.populationSize = populationSize;
    config.numberOfRuns = 1;
    config.baseSeed = baseSeed;
    config.useParallel = true;
    config.parallelRestartEachRun = false;
    config.parallelRetryOnFailure = true;
    config.closeParallelPoolAtEnd = false;
    config.useParallelDatabaseConstant = true;
    config.display = 'iter';
    config.studyName = 'lunar_surface_production_optimization';

    % Match the cislunar batch runner: allow MATLAB's default parallel
    % profile to create the pool, rather than forcing a named profile or
    % worker count from PowerShell.
    p = gcp('nocreate');
    if isempty(p)
        fprintf('Starting parallel pool using MATLAB default profile...\n');
        parpool;
    end

    studyState = runGlobalOptimization(config); %#ok<NASGU>

    % Explicitly release process workers before MATLAB -batch exits.
    p = gcp('nocreate');
    if ~isempty(p)
        fprintf('Shutting down parallel pool before MATLAB exit...\n');
        delete(p);
        fprintf('Parallel pool shut down successfully.\n');
    end

catch ME
    % Best-effort pool cleanup also applies when the optimizer throws.
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

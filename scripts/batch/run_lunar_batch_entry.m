%RUN_LUNAR_BATCH_ENTRY Stable MATLAB entry point for the full PowerShell study.
% One MATLAB process and one process-based parallel pool are reused for all
% requested network-size/objective cases and all independent runs.

try
    projectRoot = getenv('PROJECT_ROOT');
    evalBudget = str2double(getenv('EVAL_BUDGET'));
    populationSize = str2double(getenv('POPULATION_SIZE'));
    numberOfRuns = str2double(getenv('NUMBER_OF_RUNS'));
    baseSeed = str2double(getenv('BASE_SEED'));
    startCase = str2double(getenv('START_CASE'));
    parallelWorkers = str2double(getenv('PARALLEL_WORKERS'));

    assert(~isempty(projectRoot), ...
        'PROJECT_ROOT environment variable is not set.');
    assert(isfolder(projectRoot), ...
        'PROJECT_ROOT does not exist: %s', projectRoot);

    validateattributes(evalBudget, {'numeric'}, ...
        {'scalar','integer','positive'});
    validateattributes(populationSize, {'numeric'}, ...
        {'scalar','integer','>=',2});
    validateattributes(numberOfRuns, {'numeric'}, ...
        {'scalar','integer','positive'});
    validateattributes(baseSeed, {'numeric'}, ...
        {'scalar','integer','nonnegative'});
    validateattributes(startCase, {'numeric'}, ...
        {'scalar','integer','positive'});
    validateattributes(parallelWorkers, {'numeric'}, ...
        {'scalar','integer','positive'});

    networkSizes = [3 5 7 10];
    objectiveModes = ["information","coverage"];
    numberOfCases = numel(networkSizes)*numel(objectiveModes);

    assert(startCase <= numberOfCases, ...
        'START_CASE must be between 1 and %d.', numberOfCases);

    cd(projectRoot);
    addpath(fullfile(projectRoot,'scripts'));
    addpath(fullfile(projectRoot,'src'));

    % Start one process pool for the complete production study and reuse it.
    % Seven workers avoid the intermittent eighth-worker connection failure
    % observed on this machine while preserving parallel objective execution.
    p = gcp('nocreate');
    if ~isempty(p)
        delete(p);
    end

    fprintf('BATCH_POOL_START|%d\n', parallelWorkers);
    p = parpool('Processes', parallelWorkers);
    fprintf('BATCH_POOL_READY|%d\n', p.NumWorkers);

    absoluteCase = 0;

    for networkIndex = 1:numel(networkSizes)
        for objectiveIndex = 1:numel(objectiveModes)
            absoluteCase = absoluteCase + 1;

            if absoluteCase < startCase
                continue
            end

            networkSize = networkSizes(networkIndex);
            objectiveMode = objectiveModes(objectiveIndex);

            fprintf('BATCH_CASE_START|%d|%d|%s\n', ...
                absoluteCase, networkSize, objectiveMode);

            config = struct();
            config.networkSize = networkSize;
            config.objectiveMode = objectiveMode;
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

            fprintf('BATCH_CASE_COMPLETE|%d|%d|%s\n', ...
                absoluteCase, networkSize, objectiveMode);
        end
    end

    % Shut down the single pool only after every requested case is complete.
    p = gcp('nocreate');
    if ~isempty(p)
        fprintf('BATCH_POOL_STOP\n');
        delete(p);
        fprintf('BATCH_POOL_STOPPED\n');
    end

    fprintf('BATCH_STUDY_COMPLETE\n');

catch ME
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

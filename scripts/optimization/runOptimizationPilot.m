function studyState = runOptimizationPilot(userConfig)
% RUNOPTIMIZATIONPILOT - Run the standard 10 x 1200-FE GA pilot and EKF check.
%
% Inputs:
%   - userConfig - Optional overrides for the standard 10-run, 1200-FE pilot.
%
% Outputs:
%   - studyState - Optimization results and fixed-noise EKF validation.

arguments
    userConfig (1,1) struct = struct()
end

%% Standard pilot configuration

defaultConfig = struct();
defaultConfig.optimizer = "GA";
defaultConfig.networkSize = 3;
defaultConfig.objectiveMode = "information";
defaultConfig.functionEvaluationBudget = 1200;
defaultConfig.populationSize = 60;
defaultConfig.numberOfRuns = 10;
defaultConfig.baseSeed = 1000;
defaultConfig.useParallel = false;
defaultConfig.display = "iter";
defaultConfig.studyName = "lunar_surface_10x1200_pilot";

defaultConfig.validation = struct();
defaultConfig.validation.measurementNoiseSeed = 5000;
defaultConfig.validation.validateAllRuns = false;
defaultConfig.validation.initialPerturbationScale = 1;
defaultConfig.validation.initialPerturbationDirection = ...
    [1;-1;0.5;0.25;-0.25;0.125];
defaultConfig.validation.demFile = "";
defaultConfig.validation.saveIndividualValidations = true;

config = utilities.mergeConfig(defaultConfig,userConfig);

assert(config.numberOfRuns == 10, ...
    "runOptimizationPilot is intended for exactly 10 independent runs.");
assert(config.functionEvaluationBudget == 1200, ...
    "runOptimizationPilot is intended for exactly 1200 FE per run.");

%% Keep validation configuration separate from the optimizer configuration

optimizationConfig = rmfield(config,"validation");

% Reuse one pool and worker database across runs; retry a dispatch failure once.
optimizationConfig.parallelRestartEachRun = false;
optimizationConfig.parallelRetryOnFailure = ...
    logical(optimizationConfig.useParallel);
optimizationConfig.closeParallelPoolAtEnd = ...
    logical(optimizationConfig.useParallel);
optimizationConfig.useParallelDatabaseConstant = ...
    logical(optimizationConfig.useParallel);

fprintf("\n");
fprintf("============================================================\n");
fprintf("10 x 1200-FE lunar optimization pilot\n");
fprintf("============================================================\n");
fprintf("Primary/default objective: %s\n",optimizationConfig.objectiveMode);
fprintf("Optimizer seed sequence: %d through %d\n", ...
    optimizationConfig.baseSeed, ...
    optimizationConfig.baseSeed + optimizationConfig.numberOfRuns - 1);
fprintf("Fixed EKF measurement-noise seed: %d\n", ...
    config.validation.measurementNoiseSeed);

if optimizationConfig.useParallel
    fprintf("Parallel policy: one shared process pool for all GA runs\n");
    fprintf("Parallel recovery: one retry of an affected run if needed\n");
end

studyState = runGlobalOptimization(optimizationConfig);

%% Fixed-noise final EKF validation outside the search FE budget

studyState = validateOptimizationStudy(studyState,config.validation);

%% Record the complete pilot configuration

studyState.pilot = struct();
studyState.pilot.version = "lunar_10x1200_pilot_v4_information_default";
studyState.pilot.config = config;
studyState.pilot.optimizerSeeds = ...
    optimizationConfig.baseSeed + (0:optimizationConfig.numberOfRuns-1).';
studyState.pilot.measurementNoiseSeed = ...
    config.validation.measurementNoiseSeed;
studyState.pilot.parallelRestartEachRun = ...
    optimizationConfig.parallelRestartEachRun;
studyState.pilot.parallelRetryOnFailure = ...
    optimizationConfig.parallelRetryOnFailure;

summaryFile = fullfile(string(studyState.studyDirectory),"study_summary.mat");
save(summaryFile,"studyState","-v7.3");

fprintf("\nPilot complete.\n");
fprintf("Run the result/visualization test with:\n");
fprintf('  plotOptimizationPilotResults\n');

end

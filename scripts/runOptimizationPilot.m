function studyState = runOptimizationPilot(userConfig)
% RUNOPTIMIZATIONPILOT Run the standard 10 x 1200-FE GA pilot and EKF check.
%
% The pilot uses ten independent optimizer seeds while holding the final
% EKF measurement-noise realization fixed. Optimization remains deterministic
% with respect to the frozen database; the fixed-noise EKF validation is
% performed after the search and is not counted in FE.
%
% When parallel objective evaluation is enabled, the pilot deliberately uses
% a fresh process-based parallel pool for every independent GA run. The prior
% pool is deleted before the next run and the final pool is deleted when that
% run finishes. This avoids repeated-GA worker-function dispatch failures seen
% with reused pools in MATLAB R2026a. The frozen objective database is supplied
% through parallel.pool.Constant so workers do not receive a large captured
% database in the anonymous objective handle.
%
% Default pilot
%   addpath("scripts");
%   studyState = runOptimizationPilot();
%
% Example override
%   config = struct();
%   config.networkSize = 5;
%   config.objectiveMode = "information";
%   config.useParallel = true;
%   studyState = runOptimizationPilot(config);

arguments
    userConfig (1,1) struct = struct()
end

%% Standard pilot configuration

defaultConfig = struct();
defaultConfig.optimizer = "GA";
defaultConfig.networkSize = 3;
defaultConfig.objectiveMode = "coverage";
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

config = mergeStruct(defaultConfig,userConfig);

assert(config.numberOfRuns == 10, ...
    "runOptimizationPilot is intended for exactly 10 independent runs.");
assert(config.functionEvaluationBudget == 1200, ...
    "runOptimizationPilot is intended for exactly 1200 FE per run.");

%% Keep validation configuration separate from the optimizer configuration

optimizationConfig = rmfield(config,"validation");

% Repeated GA calls in R2026a can fail when the same pool is reused. The
% pilot therefore owns a fresh process pool for each independent run.
optimizationConfig.parallelRestartEachRun = ...
    logical(optimizationConfig.useParallel);
optimizationConfig.closeParallelPoolAtEnd = ...
    logical(optimizationConfig.useParallel);
optimizationConfig.useParallelDatabaseConstant = ...
    logical(optimizationConfig.useParallel);

fprintf("\n");
fprintf("============================================================\n");
fprintf("10 x 1200-FE lunar optimization pilot\n");
fprintf("============================================================\n");
fprintf("Optimizer seed sequence: %d through %d\n", ...
    optimizationConfig.baseSeed, ...
    optimizationConfig.baseSeed + optimizationConfig.numberOfRuns - 1);
fprintf("Fixed EKF measurement-noise seed: %d\n", ...
    config.validation.measurementNoiseSeed);

if optimizationConfig.useParallel
    fprintf("Parallel policy: fresh process pool for every GA run\n");
end

studyState = runGlobalOptimization(optimizationConfig);

%% Fixed-noise final EKF validation outside the search FE budget

studyState = validateOptimizationStudy(studyState,config.validation);

%% Record the complete pilot configuration

studyState.pilot = struct();
studyState.pilot.version = "lunar_10x1200_pilot_v2";
studyState.pilot.config = config;
studyState.pilot.optimizerSeeds = ...
    optimizationConfig.baseSeed + (0:optimizationConfig.numberOfRuns-1).';
studyState.pilot.measurementNoiseSeed = ...
    config.validation.measurementNoiseSeed;
studyState.pilot.parallelRestartEachRun = ...
    optimizationConfig.parallelRestartEachRun;

summaryFile = fullfile(string(studyState.studyDirectory),"study_summary.mat");
save(summaryFile,"studyState","-v7.3");

fprintf("\nPilot complete.\n");
fprintf("Run the result/visualization test with:\n");
fprintf('  run("tests/testOptimizationPilotResults.m")\n');

end

function output = mergeStruct(defaults,override)

output = defaults;
fields = fieldnames(override);

for fieldIndex = 1:numel(fields)
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

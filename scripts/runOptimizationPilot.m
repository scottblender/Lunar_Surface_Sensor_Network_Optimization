function studyState = runOptimizationPilot(userConfig)
% RUNOPTIMIZATIONPILOT Run the standard 10 x 1200-FE GA pilot and EKF check.
%
% The pilot uses ten independent optimizer seeds while holding the final
% EKF measurement-noise realization fixed. Optimization remains fully
% deterministic with respect to the frozen database; the fixed-noise EKF
% validation is performed after the search and is not counted in FE.
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

fprintf("\n");
fprintf("============================================================\n");
fprintf("10 x 1200-FE lunar optimization pilot\n");
fprintf("============================================================\n");
fprintf("Optimizer seed sequence: %d through %d\n", ...
    optimizationConfig.baseSeed, ...
    optimizationConfig.baseSeed + optimizationConfig.numberOfRuns - 1);
fprintf("Fixed EKF measurement-noise seed: %d\n", ...
    config.validation.measurementNoiseSeed);

%% Ensure GA uses a supported process-based parallel environment
%
% Global Optimization Toolbox objective/constraint dispatch is not supported
% for every thread-based parallel environment. If the user has an existing
% ThreadPool, replace it with a local process-based pool before calling GA.

if optimizationConfig.useParallel

    pool = gcp("nocreate");

    if ~isempty(pool) && isa(pool,"parallel.ThreadPool")

        fprintf("\nExisting thread-based pool detected.\n");
        fprintf("Restarting parallel execution with process workers for GA...\n");

        delete(pool);
        pool = [];
    end

    if isempty(pool)

        fprintf("\nStarting process-based parallel pool for GA...\n");

        parpool("Processes");
    end
end

studyState = runGlobalOptimization(optimizationConfig);

%% Fixed-noise final EKF validation outside the search FE budget

studyState = validateOptimizationStudy(studyState,config.validation);

%% Record the complete pilot configuration

studyState.pilot = struct();
studyState.pilot.version = "lunar_10x1200_pilot_v1";
studyState.pilot.config = config;
studyState.pilot.optimizerSeeds = ...
    optimizationConfig.baseSeed + (0:optimizationConfig.numberOfRuns-1).';
studyState.pilot.measurementNoiseSeed = ...
    config.validation.measurementNoiseSeed;

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

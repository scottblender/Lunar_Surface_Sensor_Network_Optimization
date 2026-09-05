function studyState = validateOptimizationStudy(studyState,userConfig)
% VALIDATEOPTIMIZATIONSTUDY Run fixed-noise EKF validation after optimization.
%
% This stage is outside the optimization function-evaluation budget. By
% default only the overall best network is validated. Set validateAllRuns
% true to validate every independent optimization run; every run then uses
% the SAME measurement-noise seed and therefore the same candidate/time
% measurement-noise realization.
%
% Example
%   validationConfig = struct();
%   validationConfig.measurementNoiseSeed = 5000;
%   validationConfig.validateAllRuns = false;
%   studyState = validateOptimizationStudy(studyState,validationConfig);

arguments
    studyState (1,1) struct
    userConfig (1,1) struct = struct()
end

%% Configuration

defaultConfig = struct();
defaultConfig.measurementNoiseSeed = 5000;
defaultConfig.validateAllRuns = false;
defaultConfig.initialPerturbationScale = 1;
defaultConfig.initialPerturbationDirection = [1;-1;0.5;0.25;-0.25;0.125];
defaultConfig.demFile = "";
defaultConfig.saveIndividualValidations = true;

config = mergeStruct(defaultConfig,userConfig);

validateattributes(config.measurementNoiseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
assert(islogical(config.validateAllRuns) && isscalar(config.validateAllRuns), ...
    "validateAllRuns must be a scalar logical.");
assert(islogical(config.saveIndividualValidations) && ...
    isscalar(config.saveIndividualValidations), ...
    "saveIndividualValidations must be a scalar logical.");

%% Load frozen database

assert(isfield(studyState,"config") && ...
    isfield(studyState.config,"databaseFile"), ...
    "Study state does not identify its optimization database.");

databaseFile = string(studyState.config.databaseFile);
assert(isfile(databaseFile), ...
    "Optimization database was not found: %s",databaseFile);

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization database MAT file does not contain database.");
database = databaseData.database;

studyDirectory = string(studyState.studyDirectory);
assert(isfolder(studyDirectory), ...
    "Study directory was not found: %s",studyDirectory);

networkValidationConfig = struct();
networkValidationConfig.measurementNoiseSeed = config.measurementNoiseSeed;
networkValidationConfig.initialPerturbationScale = config.initialPerturbationScale;
networkValidationConfig.initialPerturbationDirection = ...
    config.initialPerturbationDirection;
networkValidationConfig.demFile = config.demFile;

%% Validate network(s)

if config.validateAllRuns
    numberOfRunsToValidate = studyState.numberOfRuns;
    validationRunIndices = (1:numberOfRunsToValidate).';
else
    validationRunIndices = studyState.overallBestRunIndex;
end

validations = cell(numel(validationRunIndices),1);

fprintf("\n");
fprintf("============================================================\n");
fprintf("Fixed-noise EKF validation\n");
fprintf("============================================================\n");
fprintf("Measurement-noise seed: %d\n",config.measurementNoiseSeed);
fprintf("Validate all runs:       %d\n",config.validateAllRuns);

for validationIndex = 1:numel(validationRunIndices)
    runIndex = validationRunIndices(validationIndex);
    runState = studyState.runStates{runIndex};

    fprintf("\nValidating run %d of %d selected validation run(s)...\n", ...
        validationIndex,numel(validationRunIndices));
    fprintf("  Optimization run index: %d\n",runIndex);
    fprintf("  Optimization seed:      %d\n",runState.seed);
    fprintf("  Measurement-noise seed: %d\n",config.measurementNoiseSeed);

    validation = optimization.validateNetworkEkf( ...
        database,runState.bestSensorIndices,networkValidationConfig);

    validation.optimizationRunIndex = runIndex;
    validation.optimizationSeed = runState.seed;
    validations{validationIndex} = validation;

    studyState.runStates{runIndex}.ekfValidationSummary = struct( ...
        "measurementNoiseSeed",validation.measurementNoiseSeed, ...
        "meanRmsPositionErrorKm",mean(validation.rmsPositionErrorKm), ...
        "meanRmsVelocityErrorKmS",mean(validation.rmsVelocityErrorKmS), ...
        "totalMeasurementUpdates",sum(validation.measurementUpdateCounts));

    if config.saveIndividualValidations
        validationFile = fullfile( ...
            studyDirectory,sprintf("ekf_validation_run_%03d.mat",runIndex));
        save(validationFile,"validation","-v7.3");
    end
end

%% Overall-best validation handle

overallBestValidationIndex = find( ...
    validationRunIndices == studyState.overallBestRunIndex,1);

if isempty(overallBestValidationIndex)
    % This branch is only possible if future configuration changes select a
    % custom subset of runs. Keep the overall-best product guaranteed.
    overallBestValidation = optimization.validateNetworkEkf( ...
        database,studyState.overallBestSensorIndices,networkValidationConfig);
    overallBestValidation.optimizationRunIndex = studyState.overallBestRunIndex;
    overallBestValidation.optimizationSeed = ...
        studyState.runStates{studyState.overallBestRunIndex}.seed;
else
    overallBestValidation = validations{overallBestValidationIndex};
end

studyState.validation = struct();
studyState.validation.version = "lunar_optimization_validation_v1";
studyState.validation.created = string(datetime("now"));
studyState.validation.measurementNoiseSeed = config.measurementNoiseSeed;
studyState.validation.validateAllRuns = config.validateAllRuns;
studyState.validation.validationRunIndices = validationRunIndices;
studyState.validation.config = config;
studyState.validation.overallBest = overallBestValidation;

if config.validateAllRuns
    studyState.validation.allRuns = validations;
else
    studyState.validation.allRuns = cell(0,1);
end

%% Resave study summary with validation provenance

summaryFile = fullfile(studyDirectory,"study_summary.mat");
save(summaryFile,"studyState","-v7.3");

overallBestValidationFile = ...
    fullfile(studyDirectory,"overall_best_ekf_validation.mat");
validation = overallBestValidation; %#ok<NASGU>
save(overallBestValidationFile,"validation","-v7.3");

fprintf("\nEKF validation complete.\n");
fprintf("Overall-best mean RMS position error: %.6f km\n", ...
    mean(overallBestValidation.rmsPositionErrorKm));
fprintf("Overall-best total measurement updates: %d\n", ...
    sum(overallBestValidation.measurementUpdateCounts));
fprintf("Validation saved to:\n  %s\n",overallBestValidationFile);

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

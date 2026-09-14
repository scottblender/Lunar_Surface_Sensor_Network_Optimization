%% testObjectiveConvergence6000Fe
% Compare 6000-FE GA solutions for the information and coverage objectives.
%
% Purpose:
%   1) Determine whether the 1200-FE pilot solutions were under-converged.
%   2) Re-evaluate both optimized networks using the same fixed-noise EKF.
%   3) Inspect whether the large RSO-3 RMSE in the information-optimal
%      1200-FE solution diminishes after additional optimization.
%
% The seeds below correspond to the overall-best 1200-FE pilot runs:
%   information: run 9 -> seed 1008
%   coverage:    run 8 -> seed 1007

clear;
clc;

%% Project paths

thisFile = mfilename("fullpath");
testDirectory = fileparts(thisFile);
projectRoot = fileparts(testDirectory);

addpath(fullfile(projectRoot,"src"));
addpath(fullfile(projectRoot,"scripts"));

%% Study definition

objectives = ["information","coverage"];
optimizerSeeds = [1008,1007];

networkSize = 3;
functionEvaluationBudget = 6000;
populationSize = 60;

useParallel = true;

measurementNoiseSeed = 5000;

numberOfObjectives = numel(objectives);

studies = cell(numberOfObjectives,1);
validations = cell(numberOfObjectives,1);

%% Run both 6000-FE studies

for objectiveIndex = 1:numberOfObjectives

    objectiveMode = objectives(objectiveIndex);
    optimizerSeed = optimizerSeeds(objectiveIndex);

    fprintf("\n");
    fprintf("============================================================\n");
    fprintf("6000-FE objective convergence test\n");
    fprintf("Objective: %s\n",objectiveMode);
    fprintf("Seed:      %d\n",optimizerSeed);
    fprintf("============================================================\n");

    optimizationConfig = struct();

    optimizationConfig.optimizer = "GA";
    optimizationConfig.networkSize = networkSize;
    optimizationConfig.objectiveMode = objectiveMode;

    optimizationConfig.functionEvaluationBudget = ...
        functionEvaluationBudget;

    optimizationConfig.populationSize = populationSize;
    optimizationConfig.numberOfRuns = 1;
    optimizationConfig.baseSeed = optimizerSeed;

    optimizationConfig.useParallel = useParallel;

    optimizationConfig.parallelRestartEachRun = false;
    optimizationConfig.parallelRetryOnFailure = useParallel;
    optimizationConfig.closeParallelPoolAtEnd = useParallel;
    optimizationConfig.useParallelDatabaseConstant = useParallel;

    optimizationConfig.display = "iter";

    optimizationConfig.studyName = sprintf( ...
        "lunar_6000fe_%s_n%d_seed%d", ...
        objectiveMode, ...
        networkSize, ...
        optimizerSeed);

    studyState = runGlobalOptimization(optimizationConfig);

    %% Fixed-noise EKF validation

    validationConfig = struct();

    validationConfig.measurementNoiseSeed = measurementNoiseSeed;
    validationConfig.validateAllRuns = false;

    validationConfig.initialPerturbationScale = 1;

    validationConfig.initialPerturbationDirection = ...
        [1;-1;0.5;0.25;-0.25;0.125];

    validationConfig.demFile = "";
    validationConfig.saveIndividualValidations = true;

    studyState = validateOptimizationStudy( ...
        studyState, ...
        validationConfig);

    validation = studyState.validation.overallBest;

    studies{objectiveIndex} = studyState;
    validations{objectiveIndex} = validation;

    %% Basic verification

    runState = studyState.runStates{1};

    assert( ...
        runState.searchFunctionEvaluations == ...
        functionEvaluationBudget, ...
        "Incorrect FE count for %s objective.", ...
        objectiveMode);

    assert( ...
        runState.seed == optimizerSeed, ...
        "Unexpected optimizer seed.");

    assert( ...
        isfinite(runState.bestObjective), ...
        "Nonfinite optimization objective.");

    assert( ...
        all(isfinite(validation.rmsPositionErrorKm)), ...
        "Nonfinite EKF RMS position error.");

    fprintf("\n%s 6000-FE study complete.\n",objectiveMode);
end

%% Extract comparison metrics

informationStudy = studies{1};
coverageStudy = studies{2};

informationValidation = validations{1};
coverageValidation = validations{2};

informationRun = informationStudy.runStates{1};
coverageRun = coverageStudy.runStates{1};

rso3 = 3;

objective = objectives(:);
seed = optimizerSeeds(:);

bestObjective = [
    informationRun.bestObjective
    coverageRun.bestObjective
    ];

informationScore = [
    informationRun.bestInformationScore
    coverageRun.bestInformationScore
    ];

coverageScore = [
    informationRun.bestCoverageScore
    coverageRun.bestCoverageScore
    ];

meanRmsPositionErrorKm = [
    mean(informationValidation.rmsPositionErrorKm)
    mean(coverageValidation.rmsPositionErrorKm)
    ];

rso3RmsPositionErrorKm = [
    informationValidation.rmsPositionErrorKm(rso3)
    coverageValidation.rmsPositionErrorKm(rso3)
    ];

rso3RmsVelocityErrorKmS = [
    informationValidation.rmsVelocityErrorKmS(rso3)
    coverageValidation.rmsVelocityErrorKmS(rso3)
    ];

rso3MeasurementUpdates = [
    informationValidation.measurementUpdateCounts(rso3)
    coverageValidation.measurementUpdateCounts(rso3)
    ];

[maximumRmsPositionErrorKm(1,1),worstRso(1,1)] = ...
    max(informationValidation.rmsPositionErrorKm);

[maximumRmsPositionErrorKm(2,1),worstRso(2,1)] = ...
    max(coverageValidation.rmsPositionErrorKm);

comparisonTable = table( ...
    objective, ...
    seed, ...
    bestObjective, ...
    informationScore, ...
    coverageScore, ...
    meanRmsPositionErrorKm, ...
    rso3RmsPositionErrorKm, ...
    rso3RmsVelocityErrorKmS, ...
    rso3MeasurementUpdates, ...
    maximumRmsPositionErrorKm, ...
    worstRso, ...
    'VariableNames',{ ...
        'Objective', ...
        'Seed', ...
        'BestObjective', ...
        'InformationScore', ...
        'CoverageScore', ...
        'MeanRmsPositionErrorKm', ...
        'Rso3RmsPositionErrorKm', ...
        'Rso3RmsVelocityErrorKmS', ...
        'Rso3MeasurementUpdates', ...
        'MaximumRmsPositionErrorKm', ...
        'WorstRso'});

fprintf("\n");
fprintf("============================================================\n");
fprintf("6000-FE objective comparison\n");
fprintf("============================================================\n");

disp(comparisonTable);

%% Sensor networks

fprintf("\nInformation-optimal 6000-FE network:\n");
disp(informationRun.bestSensorTable);

fprintf("\nCoverage-optimal 6000-FE network:\n");
disp(coverageRun.bestSensorTable);

%% Per-RSO EKF comparison

rsoIndex = (1:numel( ...
    informationValidation.rmsPositionErrorKm)).';

perRsoComparison = table( ...
    rsoIndex, ...
    informationRun.informationByObject(:), ...
    coverageRun.informationByObject(:), ...
    informationRun.coverageByObject(:), ...
    coverageRun.coverageByObject(:), ...
    informationValidation.rmsPositionErrorKm(:), ...
    coverageValidation.rmsPositionErrorKm(:), ...
    informationValidation.measurementUpdateCounts(:), ...
    coverageValidation.measurementUpdateCounts(:), ...
    'VariableNames',{ ...
        'RSO', ...
        'InformationOpt_Info', ...
        'CoverageOpt_Info', ...
        'InformationOpt_Coverage', ...
        'CoverageOpt_Coverage', ...
        'InformationOpt_RmsPositionErrorKm', ...
        'CoverageOpt_RmsPositionErrorKm', ...
        'InformationOpt_MeasurementUpdates', ...
        'CoverageOpt_MeasurementUpdates'});

fprintf("\nPer-RSO comparison:\n");
disp(perRsoComparison);

%% RSO 3 diagnostics

fprintf("\n");
fprintf("============================================================\n");
fprintf("RSO 3 diagnostics\n");
fprintf("============================================================\n");

fprintf( ...
    "Information objective:\n" + ...
    "  RMS position error: %.6f km\n" + ...
    "  RMS velocity error: %.6e km/s\n" + ...
    "  Measurement updates: %d\n\n", ...
    informationValidation.rmsPositionErrorKm(rso3), ...
    informationValidation.rmsVelocityErrorKmS(rso3), ...
    informationValidation.measurementUpdateCounts(rso3));

fprintf( ...
    "Coverage objective:\n" + ...
    "  RMS position error: %.6f km\n" + ...
    "  RMS velocity error: %.6e km/s\n" + ...
    "  Measurement updates: %d\n", ...
    coverageValidation.rmsPositionErrorKm(rso3), ...
    coverageValidation.rmsVelocityErrorKmS(rso3), ...
    coverageValidation.measurementUpdateCounts(rso3));

%% RSO 3 innovation histories

for objectiveIndex = 1:numberOfObjectives

    validation = validations{objectiveIndex};

    updateIndices = find( ...
        validation.measurementAvailable(:,rso3));

    timeHr = ...
        validation.observationTimes(updateIndices)/3600;

    raDeg = rad2deg( ...
        validation.rightAscension(updateIndices,rso3));

    decDeg = rad2deg( ...
        validation.declination(updateIndices,rso3));

    raInnovationDeg = rad2deg( ...
        squeeze( ...
            validation.innovationHistories( ...
                1,updateIndices,rso3)));

    decInnovationDeg = rad2deg( ...
        squeeze( ...
            validation.innovationHistories( ...
                2,updateIndices,rso3)));

    updateTable = table( ...
        timeHr, ...
        raDeg, ...
        decDeg, ...
        raInnovationDeg(:), ...
        decInnovationDeg(:), ...
        'VariableNames',{ ...
            'TimeHr', ...
            'RADeg', ...
            'DecDeg', ...
            'RAInnovationDeg', ...
            'DecInnovationDeg'});

    fprintf("\nRSO 3 measurement updates -- %s objective:\n", ...
        objectives(objectiveIndex));

    disp(updateTable);
end

fprintf("\n");
fprintf("testObjectiveConvergence6000Fe passed.\n");

%% testOptimizationPilotResults
% Validate and visualize the most recent 10-run, 1200-FE optimization pilot.
%
% The script checks optimizer-seed independence, exact FE histories,
% monotonic best-so-far convergence, valid sensor selections, and fixed-noise
% final EKF validation. It then calls plotOptimizationPilotResults to create
% repository-style figures for:
%   1. Overall-best optimized sensor locations in the south-polar domain.
%   2. All RSO truth trajectories together with the optimized network.
%   3. Convergence across all ten independent optimization runs.
%
% By default the newest matching study under results/optimization_runs is
% selected. Set studySummaryFile below to an explicit study_summary.mat path
% to inspect a different pilot.

clear;
close all;
clc;

%% ========================================================================
%  Project paths
%  ========================================================================

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
sourceDirectory = fullfile(projectRoot,"src");
scriptsDirectory = fullfile(projectRoot,"scripts");
resultsDirectory = fullfile(projectRoot,"results");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
addpath(scriptsDirectory);
rehash path;

%% ========================================================================
%  Optional explicit study summary
%  ========================================================================

studySummaryFile = "";

if strlength(studySummaryFile) == 0
    studySummaryFile = findLatestPilotSummary(resultsDirectory);
end

assert(isfile(studySummaryFile), ...
    "Pilot study summary was not found: %s",studySummaryFile);

studyData = load(studySummaryFile,"studyState");
assert(isfield(studyData,"studyState"), ...
    "study_summary.mat does not contain studyState.");
studyState = studyData.studyState;

%% ========================================================================
%  Pilot configuration checks
%  ========================================================================

assert(studyState.numberOfRuns == 10, ...
    "Pilot must contain exactly 10 independent runs.");
assert(studyState.config.functionEvaluationBudget == 1200, ...
    "Pilot must use exactly 1200 FE per run.");

expectedSeeds = studyState.config.baseSeed + (0:9).';
actualSeeds = zeros(10,1);

for runIndex = 1:10
    runState = studyState.runStates{runIndex};
    actualSeeds(runIndex) = runState.seed;

    assert(runState.searchFunctionEvaluations == 1200, ...
        "Run %d did not reach the 1200-FE search budget.",runIndex);

    assert(~isempty(runState.history.fe) && ...
        runState.history.fe(end) == 1200, ...
        "Run %d convergence history does not end at 1200 FE.",runIndex);

    assert(all(diff(runState.history.fe) > 0), ...
        "Run %d FE history is not strictly increasing.",runIndex);

    assert(all(diff(runState.history.bestJ) <= 1e-12), ...
        "Run %d best-so-far objective is not monotonic.",runIndex);

    assert(numel(runState.bestSensorIndices) == runState.networkSize, ...
        "Run %d returned the wrong number of sensors.",runIndex);

    assert(numel(unique(runState.bestSensorIndices)) == runState.networkSize, ...
        "Run %d returned duplicate sensor indices.",runIndex);
end

assert(isequal(actualSeeds,expectedSeeds), ...
    "Independent optimizer seeds do not match the expected sequence.");

%% ========================================================================
%  Fixed-noise EKF validation checks
%  ========================================================================

assert(isfield(studyState,"validation"), ...
    ["Pilot does not contain final EKF validation. Run the pilot with " ...
     "runOptimizationPilot or call validateOptimizationStudy first."]);

assert(isfield(studyState.validation,"overallBest"), ...
    "Pilot validation does not contain overallBest results.");

validation = studyState.validation.overallBest;

assert(validation.measurementNoiseSeed == ...
    studyState.validation.measurementNoiseSeed, ...
    "Stored validation seed is inconsistent.");

assert(isequal(validation.sensorIndices(:), ...
    studyState.overallBestSensorIndices(:)), ...
    "EKF validation was not run on the overall best network.");

assert(all(isfinite(validation.positionErrorNormsKm),"all"), ...
    "Position-error history contains nonfinite values.");
assert(all(isfinite(validation.velocityErrorNormsKmS),"all"), ...
    "Velocity-error history contains nonfinite values.");
assert(all(isfinite(validation.positionThreeSigmaNormsKm),"all"), ...
    "Position three-sigma history contains nonfinite values.");
assert(all(isfinite(validation.velocityThreeSigmaNormsKmS),"all"), ...
    "Velocity three-sigma history contains nonfinite values.");
assert(all(isfinite(validation.truthStateHistories(1:3,:,:)),"all"), ...
    "RSO truth-state histories contain nonfinite positions.");

numberOfObjects = size(validation.truthStateHistories,3);
assert(numberOfObjects == studyState.runStates{1}.numberOfObjects, ...
    "Validation RSO count does not match the optimization study.");

%% ========================================================================
%  Publication-style result figures
%  ========================================================================

figureInfo = plotOptimizationPilotResults(studyState);

assert(isgraphics(figureInfo.sensorNetwork,"figure"), ...
    "Sensor-network figure was not created.");
assert(isgraphics(figureInfo.rsoPopulation,"figure"), ...
    "RSO-population figure was not created.");
assert(isgraphics(figureInfo.convergence,"figure"), ...
    "Convergence figure was not created.");
assert(isfile(figureInfo.sensorOutputFile), ...
    "Sensor-network EPS was not exported.");
assert(isfile(figureInfo.rsoOutputFile), ...
    "RSO-population EPS was not exported.");
assert(isfile(figureInfo.convergenceOutputFile), ...
    "Convergence EPS was not exported.");

%% ========================================================================
%  Console summary
%  ========================================================================

[~,worstObjectIndex] = max(validation.rmsPositionErrorKm);

fprintf("\n");
fprintf("Optimization pilot result summary\n");
fprintf("---------------------------------\n");
fprintf("Study:                   %s\n",studySummaryFile);
fprintf("Runs:                    %d\n",studyState.numberOfRuns);
fprintf("FE per run:              %d\n", ...
    studyState.config.functionEvaluationBudget);
fprintf("Optimizer seeds:         %d through %d\n", ...
    actualSeeds(1),actualSeeds(end));
fprintf("Measurement-noise seed:  %d\n", ...
    validation.measurementNoiseSeed);
fprintf("Best run:                %d\n",studyState.overallBestRunIndex);
fprintf("Best objective J:        %.12g\n",studyState.overallBestObjective);
fprintf("Best information score:  %.8f\n", ...
    studyState.overallBestInformationScore);
fprintf("Best coverage score:     %.0f\n", ...
    studyState.overallBestCoverageScore);
fprintf("RSOs visualized:         %d\n",numberOfObjects);
fprintf("Mean RMS position error: %.6f km\n", ...
    mean(validation.rmsPositionErrorKm));
fprintf("Total EKF updates:       %d\n", ...
    sum(validation.measurementUpdateCounts));
fprintf("Worst RMS RSO:           %d\n",worstObjectIndex);

fprintf("\nOverall-best sensor network\n");
disp(studyState.overallBestSensorTable);

fprintf("\nVerification checks\n");
fprintf("Seed checks:              passed\n");
fprintf("FE accounting:            passed\n");
fprintf("Convergence monotonicity: passed\n");
fprintf("Sensor-index validity:    passed\n");
fprintf("Fixed-noise EKF:          passed\n");
fprintf("RSO population geometry:  passed\n");
fprintf("Figure export:            passed\n");
fprintf("\n");
fprintf("testOptimizationPilotResults passed.\n");

%% ========================================================================
%  Local helper
%  ========================================================================

function summaryFile = findLatestPilotSummary(resultsDirectory)

runRoot = fullfile(resultsDirectory,"optimization_runs");
assert(isfolder(runRoot), ...
    "Optimization run directory was not found: %s",runRoot);

summaryFiles = dir(fullfile(runRoot,"**","study_summary.mat"));
assert(~isempty(summaryFiles), ...
    "No optimization study summaries were found under %s.",runRoot);

[~,sortOrder] = sort([summaryFiles.datenum],"descend");
summaryFiles = summaryFiles(sortOrder);

summaryFile = "";

for fileIndex = 1:numel(summaryFiles)
    candidateFile = fullfile( ...
        summaryFiles(fileIndex).folder,summaryFiles(fileIndex).name);

    candidateData = load(candidateFile,"studyState");

    if ~isfield(candidateData,"studyState")
        continue
    end

    candidateStudy = candidateData.studyState;

    isCompletedPilot = ...
        isfield(candidateStudy,"numberOfRuns") && ...
        candidateStudy.numberOfRuns == 10 && ...
        isfield(candidateStudy,"config") && ...
        isfield(candidateStudy.config,"functionEvaluationBudget") && ...
        candidateStudy.config.functionEvaluationBudget == 1200 && ...
        isfield(candidateStudy,"validation") && ...
        isfield(candidateStudy.validation,"overallBest");

    if isCompletedPilot
        summaryFile = string(candidateFile);
        break
    end
end

assert(strlength(summaryFile) > 0, ...
    "No completed 10-run, 1200-FE pilot study summary was found.");
end

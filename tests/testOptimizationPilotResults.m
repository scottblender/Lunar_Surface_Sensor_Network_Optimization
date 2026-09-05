%% testOptimizationPilotResults
% Validate and visualize the most recent 10-run, 1200-FE optimization pilot.
%
% The script checks optimizer-seed independence, exact FE histories,
% monotonic best-so-far convergence, valid sensor selections, and fixed-noise
% final EKF validation. It then generates figures for:
%   1. Optimized sensor locations and selection frequency.
%   2. Convergence across all ten independent runs.
%   3. RSO EKF tracking errors and measurement-update counts.
%   4. Truth versus estimated trajectory for the worst RMS-position-error RSO.
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

%% ========================================================================
%  Load frozen database for candidate geometry
%  ========================================================================

databaseFile = string(studyState.config.databaseFile);
assert(isfile(databaseFile), ...
    "Optimization database was not found: %s",databaseFile);

databaseData = load(databaseFile,"database");
database = databaseData.database;

numberOfCandidates = database.meta.numberOfCandidates;
numberOfObjects = database.meta.numberOfObjects;

%% ========================================================================
%  Figure 1: sensor locations and selection frequency
%  ========================================================================

selectionCount = zeros(numberOfCandidates,1);

for runIndex = 1:10
    selected = studyState.runStates{runIndex}.bestSensorIndices(:);
    selectionCount(selected) = selectionCount(selected) + 1;
end

selectedAtLeastOnce = find(selectionCount > 0);
overallBestSensors = studyState.overallBestSensorIndices(:);

candidateLongitudeDeg = rad2deg(database.candidates.longitudesRad);
candidateLatitudeDeg = rad2deg(database.candidates.latitudesRad);

figure("Name","Pilot Sensor Locations");
hold on;

scatter(candidateLongitudeDeg,candidateLatitudeDeg,8, ...
    [0.75 0.75 0.75],"filled", ...
    "DisplayName","Candidate sites");

frequencyMarkerSize = 30 + 30*selectionCount(selectedAtLeastOnce);
scatter(candidateLongitudeDeg(selectedAtLeastOnce), ...
    candidateLatitudeDeg(selectedAtLeastOnce), ...
    frequencyMarkerSize,selectionCount(selectedAtLeastOnce), ...
    "filled","DisplayName","Selected across runs");

scatter(candidateLongitudeDeg(overallBestSensors), ...
    candidateLatitudeDeg(overallBestSensors), ...
    140,"p","filled","MarkerEdgeColor","k", ...
    "DisplayName","Overall best network");

xlabel("Longitude [deg E]");
ylabel("Latitude [deg]");
xlim([0 360]);
ylim([-90 -75]);
grid on;
box on;
colorbar;
title(sprintf( ...
    "10-Run Pilot Sensor Selection Frequency: %d-Sensor Network", ...
    studyState.config.networkSize));
legend("Location","best");

%% ========================================================================
%  Figure 2: convergence across all independent runs
%  ========================================================================

referenceFe = studyState.runStates{1}.history.fe(:);
numberOfHistoryPoints = numel(referenceFe);
scoreHistory = nan(numberOfHistoryPoints,10);

for runIndex = 1:10
    runState = studyState.runStates{runIndex};
    assert(isequal(runState.history.fe(:),referenceFe), ...
        "Run %d does not share the common FE grid.",runIndex);
    scoreHistory(:,runIndex) = -runState.history.bestJ(:);
end

meanScore = mean(scoreHistory,2);
stdScore = std(scoreHistory,0,2);

figure("Name","Pilot Convergence");
hold on;

for runIndex = 1:10
    plot(referenceFe,scoreHistory(:,runIndex), ...
        "LineWidth",0.8, ...
        "HandleVisibility","off");
end

plot(referenceFe,meanScore, ...
    "k-","LineWidth",2.2,"DisplayName","Mean best-so-far score");
plot(referenceFe,meanScore+stdScore, ...
    "k--","LineWidth",1.1,"DisplayName","Mean \pm 1 std");
plot(referenceFe,meanScore-stdScore, ...
    "k--","LineWidth",1.1,"HandleVisibility","off");

xlabel("Function Evaluations");
if string(studyState.config.objectiveMode) == "coverage"
    ylabel("Best Coverage Score");
else
    ylabel("Best Information Score");
end
grid on;
box on;
title(sprintf( ...
    "GA Convergence: 10 Independent Runs, 1200 FE/Run"));
legend("Location","best");

%% ========================================================================
%  Figure 3: RSO tracking performance for overall best network
%  ========================================================================

timeHours = validation.times(:)/3600;

figure("Name","Pilot RSO EKF Tracking");
tiledlayout(2,2,"TileSpacing","compact","Padding","compact");

nexttile;
plot(timeHours,validation.positionErrorNormsKm,"LineWidth",0.8);
hold on;
plot(timeHours,median(validation.positionErrorNormsKm,2), ...
    "k-","LineWidth",2.2);
xlabel("Time [hr]");
ylabel("Position Error Norm [km]");
title("Position Tracking Error");
grid on;
box on;

nexttile;
plot(timeHours,validation.velocityErrorNormsKmS,"LineWidth",0.8);
hold on;
plot(timeHours,median(validation.velocityErrorNormsKmS,2), ...
    "k-","LineWidth",2.2);
xlabel("Time [hr]");
ylabel("Velocity Error Norm [km/s]");
title("Velocity Tracking Error");
grid on;
box on;

nexttile;
bar(1:numberOfObjects,validation.measurementUpdateCounts);
xlabel("RSO");
ylabel("Measurement Updates");
title("Accepted EKF Measurements");
grid on;
box on;

nexttile;
bar(1:numberOfObjects,validation.rmsPositionErrorKm);
xlabel("RSO");
ylabel("RMS Position Error [km]");
title("Per-RSO RMS Position Error");
grid on;
box on;

sgtitle(sprintf( ...
    "Overall Best Network EKF Validation — Fixed Noise Seed %d", ...
    validation.measurementNoiseSeed));

%% ========================================================================
%  Figure 4: worst-RMS RSO truth and estimate in MCI
%  ========================================================================

[~,worstObjectIndex] = max(validation.rmsPositionErrorKm);
truthTrajectory = validation.truthStateHistories(1:3,:,worstObjectIndex);
estimatedTrajectory = validation.stateHistories(1:3,:,worstObjectIndex);

figure("Name","Worst RSO Trajectory Tracking");
hold on;

plot3(truthTrajectory(1,:),truthTrajectory(2,:),truthTrajectory(3,:), ...
    "LineWidth",2,"DisplayName","Truth");
plot3(estimatedTrajectory(1,:),estimatedTrajectory(2,:), ...
    estimatedTrajectory(3,:),"--","LineWidth",1.5, ...
    "DisplayName","EKF estimate");

[moonX,moonY,moonZ] = sphere(40);
moonRadiusKm = database.config.moon.radiusKm;
surf(moonRadiusKm*moonX,moonRadiusKm*moonY,moonRadiusKm*moonZ, ...
    "FaceAlpha",0.12,"EdgeColor","none", ...
    "HandleVisibility","off");

axis equal;
xlabel("MCI x [km]");
ylabel("MCI y [km]");
zlabel("MCI z [km]");
grid on;
box on;
view(3);
legend("Location","best");
title(sprintf( ...
    "Worst RMS Position-Error RSO: Object %d",worstObjectIndex));

%% ========================================================================
%  Console summary
%  ========================================================================

fprintf("\n");
fprintf("Optimization pilot result summary\n");
fprintf("---------------------------------\n");
fprintf("Study:                  %s\n",studySummaryFile);
fprintf("Runs:                   %d\n",studyState.numberOfRuns);
fprintf("FE per run:             %d\n", ...
    studyState.config.functionEvaluationBudget);
fprintf("Optimizer seeds:        %d through %d\n", ...
    actualSeeds(1),actualSeeds(end));
fprintf("Measurement-noise seed: %d\n", ...
    validation.measurementNoiseSeed);
fprintf("Best run:               %d\n",studyState.overallBestRunIndex);
fprintf("Best objective J:       %.12g\n",studyState.overallBestObjective);
fprintf("Best information score: %.8f\n", ...
    studyState.overallBestInformationScore);
fprintf("Best coverage score:    %.0f\n", ...
    studyState.overallBestCoverageScore);
fprintf("Mean RMS position error: %.6f km\n", ...
    mean(validation.rmsPositionErrorKm));
fprintf("Total EKF updates:       %d\n", ...
    sum(validation.measurementUpdateCounts));
fprintf("Worst RMS RSO:           %d\n",worstObjectIndex);
fprintf("\n");
fprintf("Seed checks:             passed\n");
fprintf("FE accounting:           passed\n");
fprintf("Convergence monotonicity: passed\n");
fprintf("Sensor-index validity:   passed\n");
fprintf("Fixed-noise EKF:         passed\n");
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
    candidateFile = fullfile(summaryFiles(fileIndex).folder, ...
        summaryFiles(fileIndex).name);

    candidateData = load(candidateFile,"studyState");

    if ~isfield(candidateData,"studyState")
        continue
    end

    candidateStudy = candidateData.studyState;

    if isfield(candidateStudy,"numberOfRuns") && ...
            candidateStudy.numberOfRuns == 10 && ...
            isfield(candidateStudy,"config") && ...
            isfield(candidateStudy.config,"functionEvaluationBudget") && ...
            candidateStudy.config.functionEvaluationBudget == 1200
        summaryFile = string(candidateFile);
        break
    end
end

assert(strlength(summaryFile) > 0, ...
    "No 10-run, 1200-FE pilot study summary was found.");
end

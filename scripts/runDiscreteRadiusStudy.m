%% runDiscreteRadiusStudy
% RUNDISCRETERADIUSSTUDY Post-process one saved lunar sensor optimization.
%
% Preferred usage, from the MATLAB project root:
%   run("scripts/runDiscreteRadiusStudy.m");
%
% DEFAULT MODE: reads a saved optimization study_summary.mat, including its
% best sensor indices and objective mode (GA, PSO or surrogateopt results).
% All radius searches remain anchored to that SAME original network.
% The radius sweep calls runDiscreteRadiusSensitivity, which reuses a shared
% objective cache across radii and saves summaries/figures. No global
% optimizer is rerun and no production study files are overwritten.
%
% DATABASE COMPATIBILITY IS REQUIRED. Historical saved studies may use a
% different database from results/optimization_database.mat. For example,
% the 20260915 GA campaign reports a v2 database, while your current file
% may contain v5. Specify a preserved v2 database in the setting below.
% Do not bypass the version/candidate-coordinate check: indices alone do
% not identify the same physical network across different databases.
%
% ALTERNATIVE MODE: to repeat the direct-index workflow used successfully
% with optimization.refineDiscreteNetwork, set radiusStudySource to
% "direct_indices", specify radiusStudyInitialIndices and the objective
% mode, and use the current database as a new baseline. That is NOT a
% quantitative comparison to the saved historical study's objective.

%% ========================================================================
% USER SETTINGS
% ========================================================================

radiusStudySource = "saved_study";  % "saved_study" or "direct_indices"

% A folder name inside results/optimization_runs (not the MAT filename):
radiusStudyStudyFolder = "ga_coverage_n3_20260915_121933";

% Optional explicit .mat path to study summary, instead of the folder.
% Leave empty to use the directory above.
radiusStudySummaryFile = "";

% Optional database MAT-file override; blank chooses the saved study's
% databaseFile path, with existing runner's default-path fallback.
% If the historical v2 file was replaced by v5, specify the preserved v2
% MAT file here. Use the matching candidate chunk files as well.
radiusStudyDatabaseFile = "";

% Used ONLY for "direct_indices" (no historical study summary).
% Use the exact original IDs from your successful standalone refinement:
radiusStudyInitialIndices = [];
radiusStudyObjectiveMode = "information"; % "coverage" or "information"

% Radius sensitivity settings. Raw Cartesian combinations grow quickly.
radiusStudyRadiiKm = [10 20 30 40 50 60];
radiusStudyMaximumCombinations = 50000;
radiusStudySkipOversized = true;
radiusStudyCaptureFraction = 0.95;
radiusStudyMakePlots = true;
radiusStudySaveResults = true;

%% ========================================================================
% PATHS
% ========================================================================

radiusStudyScriptPath = mfilename("fullpath");
assert(~isempty(radiusStudyScriptPath), ...
    "runDiscreteRadiusStudy:ScriptPath", ...
    "Run this file as a script, not by pasting sections individually.");

radiusStudyProjectRoot = fileparts(fileparts(radiusStudyScriptPath));
addpath(fullfile(radiusStudyProjectRoot,"src"));
addpath(fullfile(radiusStudyProjectRoot,"scripts"));

radiusStudyConfig = struct();
radiusStudyConfig.radiiKm = radiusStudyRadiiKm;
radiusStudyConfig.maximumCombinations = radiusStudyMaximumCombinations;
radiusStudyConfig.skipOversized = radiusStudySkipOversized;
radiusStudyConfig.captureFraction = radiusStudyCaptureFraction;
radiusStudyConfig.makePlots = radiusStudyMakePlots;
radiusStudyConfig.saveResults = radiusStudySaveResults;

if strlength(string(radiusStudyDatabaseFile)) > 0
    radiusStudyConfig.databaseFile = string(radiusStudyDatabaseFile);
end

%% ========================================================================
% SELECT STUDY OR DIRECT INITIAL INDICES
% ========================================================================

switch lower(string(radiusStudySource))
    case "saved_study"
        radiusStudySummaryPath = string(radiusStudySummaryFile);

        if strlength(radiusStudySummaryPath) == 0
            assert(strlength(string(radiusStudyStudyFolder)) > 0, ...
                "runDiscreteRadiusStudy:MissingStudyFolder", ...
                "Set radiusStudyStudyFolder or radiusStudySummaryFile.");
            radiusStudySummaryPath = fullfile( ...
                radiusStudyProjectRoot,"results","optimization_runs", ...
                string(radiusStudyStudyFolder),"study_summary.mat");
        elseif ~isfile(radiusStudySummaryPath)
            radiusStudySummaryPath = fullfile( ...
                radiusStudyProjectRoot,radiusStudySummaryPath);
        end

        assert(isfile(radiusStudySummaryPath), ...
            "runDiscreteRadiusStudy:MissingStudySummary", ...
            "Study summary MAT file not found: %s", ...
            radiusStudySummaryPath);

        % Load once here for an explicit, readable preview. The underlying
        % sensitivity function loads it again and checks DB compatibility.
        radiusStudyLoaded = load(radiusStudySummaryPath,"studyState");
        assert(isfield(radiusStudyLoaded,"studyState"), ...
            "runDiscreteRadiusStudy:InvalidStudySummary", ...
            "Study summary must contain a studyState variable.");

        radiusStudySaved = radiusStudyLoaded.studyState;
        assert(isfield(radiusStudySaved,"overallBestSensorIndices") && ...
            isfield(radiusStudySaved,"config") && ...
            isfield(radiusStudySaved.config,"objectiveMode"), ...
            "runDiscreteRadiusStudy:InvalidStudySummary", ...
            "Study summary must contain best indices and objective mode.");

        radiusStudyConfig.studySummaryFile = radiusStudySummaryPath;

        fprintf("\nUsing saved study summary:\n  %s\n",radiusStudySummaryPath);
        fprintf("  Objective: %s\n", ...
            string(radiusStudySaved.config.objectiveMode));
        fprintf("  Original candidate IDs: %s\n", ...
            mat2str(double(radiusStudySaved.overallBestSensorIndices(:).')));
        if isfield(radiusStudySaved.config,"optimizer")
            fprintf("  Optimizer: %s\n", ...
                string(radiusStudySaved.config.optimizer));
        end

    case "direct_indices"
        % Direct current-database sweep, intentionally independent of the
        % historical optimization studies (and their database versions).
        assert(~isempty(radiusStudyInitialIndices), ...
            "runDiscreteRadiusStudy:MissingInitialIndices", ...
            ["Enter the original candidate indices used by your " ...
             "successful refineDiscreteNetwork call."]);

        radiusStudyIndices = sort(double(radiusStudyInitialIndices(:)));
        validateattributes(radiusStudyIndices,{'double'}, ...
            {'vector','nonempty','finite','real','integer','positive'});
        assert(numel(unique(radiusStudyIndices)) == ...
            numel(radiusStudyIndices), ...
            "runDiscreteRadiusStudy:DuplicateSensors", ...
            "Original candidate indices must be distinct.");

        radiusStudyConfig.initialSensorIndices = radiusStudyIndices;
        radiusStudyConfig.objectiveMode = ...
            lower(string(radiusStudyObjectiveMode));

        % Use current production file unless caller names another one.
        if ~isfield(radiusStudyConfig,"databaseFile")
            radiusStudyConfig.databaseFile = fullfile( ...
                radiusStudyProjectRoot,"results", ...
                "optimization_database.mat");
        end

        fprintf("\nUsing direct candidate-index inputs.\n");
        fprintf("  Objective: %s\n",radiusStudyConfig.objectiveMode);
        fprintf("  Original candidate IDs: %s\n", ...
            mat2str(radiusStudyIndices.'));

    otherwise
        error("runDiscreteRadiusStudy:InvalidSource", ...
            "radiusStudySource must be saved_study or direct_indices.");
end

%% ========================================================================
% RUN AND REPORT
% ========================================================================

fprintf("\n============================================================\n");
fprintf("Lunar discrete refinement radius sensitivity\n");
fprintf("============================================================\n");
fprintf("Radii (km): %s\n",mat2str(radiusStudyRadiiKm));
fprintf("Max raw combinations / radius: %.0f\n", ...
    radiusStudyMaximumCombinations);

radiusStudy = runDiscreteRadiusSensitivity(radiusStudyConfig);

fprintf("\n============================================================\n");
fprintf("Radius sensitivity completed\n");
fprintf("============================================================\n");
disp(radiusStudy.summaryTable);
fprintf("Original objective: %.12g\n",radiusStudy.originalObjective);
fprintf("Best discrete objective: %.12g\n",radiusStudy.bestObjective);
fprintf("Best refined candidate IDs: %s\n", ...
    mat2str(radiusStudy.bestSensorIndices.'));
fprintf("Maximum observed improvement: %.12g\n", ...
    radiusStudy.maximumObservedImprovement);
fprintf("Additional unique objective evaluations: %.0f\n", ...
    radiusStudy.totalUniqueObjectiveEvaluations);

if isfinite(radiusStudy.radiusAtCaptureKm)
    fprintf("Observed r%.0f: %.2f km (largest completed radius reference)\n", ...
        100*radiusStudy.captureFraction,radiusStudy.radiusAtCaptureKm);
else
    fprintf("Observed r95 unavailable (no improvement at completed radii).\n");
end
if any(radiusStudy.summaryTable.Status == "skipped_limit")
    fprintf("NOTE: Some radii exceeded the combination limit and were skipped.\n");
end
if strlength(radiusStudy.outputDirectory) > 0
    fprintf("Results folder: %s\n",radiusStudy.outputDirectory);
    if strlength(radiusStudy.summaryCsvFile) > 0
        fprintf("CSV: %s\n",radiusStudy.summaryCsvFile);
    end
end

% The radiusStudy struct remains in your MATLAB workspace.

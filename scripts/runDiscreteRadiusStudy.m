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
% The CURRENT database at results/optimization_database.mat is always
% authoritative by default, even when the saved study lists an old version.
% The saved study supplies observation-site coordinates and objective mode;
% the sensitivity function maps the original physical locations onto the
% current candidate grid and recomputes the starting objective on that DB.
% This means updated databases do not require updating historical studies.
% Old saved objective values are NOT compared to objectives from a new DB.
%
% ALTERNATIVE MODE: set radiusStudySource="direct_indices" to use
% explicit current-grid IDs (instead of coordinates from a saved study).

%% ========================================================================
% USER SETTINGS
% ========================================================================

radiusStudySource = "saved_study";  % "saved_study" or "direct_indices"

% A folder name inside results/optimization_runs (not the MAT filename):
radiusStudyStudyFolder = "ga_coverage_n3_20260915_121933";

% Optional explicit .mat path to study summary, instead of the folder.
% Leave empty to use the directory above.
radiusStudySummaryFile = "";

% Blank = the CURRENT canonical database at results/optimization_database.mat.
% Override only if a newer database is stored at a different path.
radiusStudyDatabaseFile = "";

% For saved studies, allow at most this much movement when mapping each
% old physical location to the CURRENT candidate grid (km). Empty uses
% twice the grid spacing recorded in the current DB (fallback 30 km).
radiusStudyMaximumRemapDistanceKm = [];

% Used ONLY for "direct_indices" (no historical study summary).
% Use the exact original IDs from your successful standalone refinement:
radiusStudyInitialIndices = [];
radiusStudyObjectiveMode = "information"; % "coverage" or "information"

% Search 10 to 100 km. Inf explicitly REMOVES the combinatorial cap.
% This is exhaustive and can require substantial time and RAM. Each
% radius still enumerates all combinations; unique objective calls are cached
% across radii. Leave skipOversized=false so no radius is silently omitted.
radiusStudyRadiiKm = 10:10:100;
radiusStudyMaximumCombinations = Inf;
radiusStudySkipOversized = false;
radiusStudyCaptureFraction = 0.95;
radiusStudyMarginalThresholdPct = 1; % marginal gain below 1% = diminishing returns
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
radiusStudyConfig.marginalThresholdPct = radiusStudyMarginalThresholdPct;
radiusStudyConfig.makePlots = radiusStudyMakePlots;
radiusStudyConfig.saveResults = radiusStudySaveResults;
radiusStudyConfig.maximumRemapDistanceKm = ...
    radiusStudyMaximumRemapDistanceKm;

% Always use the current DB. Never inherit the study's historical DB path.
if strlength(string(radiusStudyDatabaseFile)) > 0
    radiusStudyConfig.databaseFile = string(radiusStudyDatabaseFile);
else
    radiusStudyConfig.databaseFile = fullfile( ...
        radiusStudyProjectRoot,"results","optimization_database.mat");
end
assert(isfile(radiusStudyConfig.databaseFile), ...
    "runDiscreteRadiusStudy:MissingCurrentDatabase", ...
    "Current optimization database not found: %s", ...
    radiusStudyConfig.databaseFile);

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

        % Load once here for an explicit, readable preview. The sensitivity
        % function maps saved site coordinates onto the current DB as needed.
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
        % Direct current-database sweep, without a saved study.
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
fprintf("Current DB: %s\n",radiusStudyConfig.databaseFile);

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
fprintf("Best positive score (-J): %.12g\n", ...
    -radiusStudy.bestObjective);
if isfinite(radiusStudy.tradeoffRadiusKm)
    fprintf("Diminishing-returns radius: %.2f km (%.3g%% marginal threshold)\n", ...
        radiusStudy.tradeoffRadiusKm,radiusStudy.marginalThresholdPct);
    if radiusStudy.tradeoffProvisional
        fprintf("NOTE: This recommendation is provisional; radii were skipped.\n");
    end
else
    fprintf("No diminishing-returns elbow found in the tested radii.\n");
end
fprintf("Additional unique objective evaluations: %.0f\n", ...
    radiusStudy.totalUniqueObjectiveEvaluations);
fprintf("Current DB version: %s\n",radiusStudy.currentDatabaseVersion);
if radiusStudy.mappingApplied
    fprintf("Saved sites were matched to current-grid IDs: %s\n", ...
        mat2str(radiusStudy.originalSensorIndices(:).'));
    fprintf("Max remapping distance: %.6f km\n", ...
        max(radiusStudy.mappingDistancesKm));
end

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

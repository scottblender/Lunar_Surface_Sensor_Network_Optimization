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
%
% If a COMPATIBLE saved radius_sensitivity_study.mat exists, this runner
% automatically reuses it: no expensive objective evaluations are repeated.
% It then recalculates computational-efficiency eta, per-sensor movement,
% and figures/CSVs using analyzeSavedDiscreteRadiusStudy. The single entry
% point for both workflows remains THIS script. An incompatible MAT is
% never reused silently. Set radiusStudyReuseExistingResults=false to
% deliberately rerun the complete radius refinement.

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

% Reuse a compatible previously completed radius sweep, then recompute
% eta and sensor displacements WITHOUT any objective-function evaluations.
radiusStudyReuseExistingResults = true;

% Optional explicit path to an existing radius_sensitivity_study.mat.
% Empty searches newest-to-oldest under results/local_refinement.
radiusStudyExistingMatFile = "";

% The movement/boundary diagnostic marks a sensor as near the edge
% when its displacement >= this fraction of the selected search radius.
radiusStudyBoundaryFraction = 0.90;

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

radiusStudyExpectedSavedIndices = [];
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
        radiusStudyExpectedSavedIndices = ...
            sort(double(radiusStudySaved.overallBestSensorIndices(:)));

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
            "Enter the original candidate indices from refineDiscreteNetwork.");

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

%% ========================================================================
% RECOVER SAVED SWEEP OR PERFORM REFINEMENT
% ========================================================================

radiusStudy = struct();
radiusStudyReusedMatFile = "";
if radiusStudyReuseExistingResults
    radiusStudyCandidates = struct('folder',{},'name',{},'datenum',{});
    if strlength(string(radiusStudyExistingMatFile)) > 0
        radiusStudyRequestedMat = string(radiusStudyExistingMatFile);
        if ~isfile(radiusStudyRequestedMat)
            radiusStudyRequestedMat = fullfile( ...
                radiusStudyProjectRoot,radiusStudyRequestedMat);
        end
        assert(isfile(radiusStudyRequestedMat), ...
            "runDiscreteRadiusStudy:SavedResultNotFound", ...
            "Saved radius MAT not found: %s",radiusStudyRequestedMat);
        radiusStudyCandidates = dir(radiusStudyRequestedMat);
    else
        radiusStudyCandidates = dir(fullfile( ...
            radiusStudyProjectRoot,"results","local_refinement", ...
            "radius_sensitivity_*","radius_sensitivity_study.mat"));
        if ~isempty(radiusStudyCandidates)
            [~,radiusStudyOrder] = sort( ...
                [radiusStudyCandidates.datenum],"descend");
            radiusStudyCandidates = radiusStudyCandidates(radiusStudyOrder);
        end
    end
    for radiusStudyCandidateIndex = 1:numel(radiusStudyCandidates)
        radiusStudyCandidate = ...
            radiusStudyCandidates(radiusStudyCandidateIndex);
        radiusStudyPossibleMat = fullfile( ...
            radiusStudyCandidate.folder,radiusStudyCandidate.name);
        try
            radiusStudySavedMat = load(radiusStudyPossibleMat,"study");
            if ~isfield(radiusStudySavedMat,"study")
                continue
            end
            radiusStudyCandidateResult = radiusStudySavedMat.study;
            if isReusableRadiusStudy(radiusStudyCandidateResult, ...
                    radiusStudyConfig,radiusStudySource, ...
                    radiusStudyProjectRoot,radiusStudyCandidate.datenum, ...
                    radiusStudyExpectedSavedIndices)
                radiusStudy = radiusStudyCandidateResult;
                radiusStudyReusedMatFile = string(radiusStudyPossibleMat);
                fprintf("\nReusing saved radius sweep (NO objective FEs):\n  %s\n", ...
                    radiusStudyReusedMatFile);
                break
            end
        catch ME
            fprintf("Saved result not reusable (%s): %s\n", ...
                radiusStudyPossibleMat,ME.message);
        end
    end
    if strlength(string(radiusStudyExistingMatFile)) > 0 && ...
            strlength(radiusStudyReusedMatFile) == 0
        error("runDiscreteRadiusStudy:IncompatibleSavedResult", ...
            ['The explicitly selected MAT is not compatible with the ' ...
             'selected study, current database, or radii. ' ...
             'Do not silently reuse it.']);
    end
end

if strlength(radiusStudyReusedMatFile) == 0
    fprintf("\nNo compatible completed MAT found; starting refinement.\n");
    radiusStudy = runDiscreteRadiusSensitivity(radiusStudyConfig);
else
    fprintf("Using existing J and FE counts; only metrics are recalculated.\n");
end

% This post-processing step NEVER calls networkObjective or the optimizer.
% The helper is invoked internally: one script runs/reuses everything.
radiusStudyAnalysisConfig = struct();
radiusStudyAnalysisConfig.study = radiusStudy;
radiusStudyAnalysisConfig.databaseFile = ...
    string(radiusStudyConfig.databaseFile);
radiusStudyAnalysisConfig.boundaryFraction = ...
    radiusStudyBoundaryFraction;
radiusStudyAnalysisConfig.saveResults = radiusStudySaveResults;
radiusStudyAnalysisConfig.makePlots = radiusStudyMakePlots;
if strlength(radiusStudyReusedMatFile) > 0
    radiusStudyAnalysisConfig.studyMatFile = radiusStudyReusedMatFile;
elseif isfield(radiusStudy,"studyMatFile") && ...
        strlength(string(radiusStudy.studyMatFile)) > 0
    radiusStudyAnalysisConfig.studyMatFile = radiusStudy.studyMatFile;
end

radiusStudyAnalysis = analyzeSavedDiscreteRadiusStudy( ...
    radiusStudyAnalysisConfig);

% Include refreshed eta and displacement columns in the displayed
% workspace summary without overwriting the saved original MAT/CSV.
radiusStudy.summaryTable = radiusStudyAnalysis.summaryTable;

% Metrics and suggested elbow can be recomputed with a changed threshold
% even if objective evaluations came from a saved study.
radiusStudy.marginalThresholdPct = radiusStudyMarginalThresholdPct;
radiusStudy.tradeoffRadiusKm = NaN;
radiusStudyComplete = ...
    string(radiusStudyAnalysis.summaryTable.Status) == "completed";
radiusStudyMarginal = ...
    radiusStudyAnalysis.summaryTable.MarginalRelativeImprovementPct;
radiusStudyMaterial = find(radiusStudyComplete & ...
    isfinite(radiusStudyMarginal) & ...
    radiusStudyMarginal >= radiusStudyMarginalThresholdPct);
radiusStudyCompletedIdx = find(radiusStudyComplete);
if ~isempty(radiusStudyMaterial) && ~isempty(radiusStudyCompletedIdx) && ...
        radiusStudyMaterial(end) < radiusStudyCompletedIdx(end)
    radiusStudy.tradeoffRadiusKm = ...
        radiusStudyAnalysis.summaryTable.RadiusKm(radiusStudyMaterial(end));
end
radiusStudy.tradeoffProvisional = any(~radiusStudyComplete);

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
fprintf("Unique objective evaluations in original sweep: %.0f\n", ...
    radiusStudy.totalUniqueObjectiveEvaluations);
if strlength(radiusStudyReusedMatFile) > 0
    fprintf("New objective evaluations in this run: 0 (cached MAT reused)\n");
end
fprintf("Eta and sensor displacement tables: radiusStudyAnalysis\n");
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

% Workspace outputs: radiusStudy (sweep) and radiusStudyAnalysis (metrics).
% The original saved sweep MAT is never overwritten by post-processing.

%% ========================================================================
% LOCAL HELPER: REUSE ONLY COMPATIBLE SAVED SWEEPS
% ========================================================================

function tf = isReusableRadiusStudy( ...
    saved,config,source,root,matDatenum,expectedSavedIndices)
tf = false;
if ~isstruct(saved) || ...
        ~all(isfield(saved,{'summaryTable','refinementResults', ...
        'studySummaryFile','originalSensorIndices', ...
        'objectiveMode','databaseFile','currentDatabaseVersion'}))
    return
end
T = saved.summaryTable;
if ~istable(T) || ...
        ~all(ismember({'RadiusKm','Status'},T.Properties.VariableNames))
    return
end
expectedRadii = double(config.radiiKm(:));
if numel(T.RadiusKm) ~= numel(expectedRadii) || ...
        any(abs(double(T.RadiusKm(:))-expectedRadii)>1e-9) || ...
        any(string(T.Status(:)) ~= "completed")
    return
end
if numel(saved.refinementResults) ~= numel(expectedRadii)
    return
end

if string(source)=="saved_study"
    if ~isfield(config,"studySummaryFile") || ...
            ~strcmpi(normalizePath(saved.studySummaryFile), ...
            normalizePath(config.studySummaryFile)) || ...
            ~isfield(saved,"savedOriginalSensorIndices") || ...
            ~isequal(sort(double(saved.savedOriginalSensorIndices(:))), ...
            expectedSavedIndices)
        return
    end
else
    if ~isfield(config,"initialSensorIndices") || ...
            ~isequal(sort(double(saved.originalSensorIndices(:))), ...
            sort(double(config.initialSensorIndices(:)))) || ...
            string(saved.objectiveMode) ~= string(config.objectiveMode)
        return
    end
end
if ~strcmpi(normalizePath(saved.databaseFile), ...
        normalizePath(config.databaseFile))
    return
end

% A rebuilt canonical database must not inherit the cached J values.
% Reject a database file changed after the study's MAT was saved.
dbStat = dir(string(config.databaseFile));
if isempty(dbStat) || dbStat.datenum > matDatenum+1e-7
    return
end

% Check the saved database version and all winning coordinates against
% the current candidate list. Matching a version string alone is unsafe.
D = load(config.databaseFile,"database");
if ~isfield(D,"database") || ~isfield(D.database,"candidates")
    return
end
db = D.database;
version = "";
if isfield(db,"meta") && isfield(db.meta,"version")
    version = string(db.meta.version);
end
if string(saved.currentDatabaseVersion)~=version
    return
end
if ~isfield(db.candidates,"latitudesRad") || ...
        ~isfield(db.candidates,"longitudesRad")
    return
end
lat = double(db.candidates.latitudesRad(:));
lon = double(db.candidates.longitudesRad(:));
for k = 1:numel(expectedRadii)
    r = saved.refinementResults{k};
    if ~isstruct(r) || ~isfield(r,"bestSensorIndices") || ...
            ~isfield(r,"bestLatitudesRad") || ...
            ~isfield(r,"bestLongitudesRad")
        return
    end
    ids = double(r.bestSensorIndices(:));
    if isempty(ids) || any(ids<1) || any(ids>numel(lat)) || ...
            any(ids~=floor(ids)) || ...
            numel(ids)~=numel(r.bestLatitudesRad)
        return
    end
    dLon = atan2( ...
        sin(lon(ids)-double(r.bestLongitudesRad(:))), ...
        cos(lon(ids)-double(r.bestLongitudesRad(:))));
    if any(abs(lat(ids)-double(r.bestLatitudesRad(:)))>1e-8) || ...
            any(abs(dLon)>1e-8)
        return
    end
end
tf = true;
end

function p = normalizePath(value)
p = lower(strrep(char(string(value)),char(92),'/'));
end

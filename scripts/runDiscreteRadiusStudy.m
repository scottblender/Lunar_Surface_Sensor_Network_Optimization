%% runDiscreteRadiusStudy
% RUNDISCRETERADIUSSTUDY  Run a post-processing lunar discrete-radius sweep.
%
% From the repository root, in MATLAB:
%   run("scripts/runDiscreteRadiusStudy.m")
%
% This runner uses the CURRENT results/optimization_database.mat and the
% ORIGINAL sensor IDs from your successful refineDiscreteNetwork call.
% It does NOT load a historical study_summary.mat, so it avoids the v2/v5
% database-version mismatch. All radii stay centered on the SAME original
% network; previous refined solutions are NOT used as new centers.
%
% Choose the original sensor IDs in USER SETTINGS below, or keep them empty
% and run in a workspace containing the prior "refined" result struct.
% IMPORTANT: use refined.initialSensorIndices, NOT refined.bestSensorIndices.
%
% The sweep caches expensive objective evaluations across radii and saves:
%   radius_sensitivity_summary.csv
%   radius_sensitivity_study.mat
%   best_objective_vs_radius.png
%   best_objective_vs_unique_fe.png
% under results/local_refinement/radius_sensitivity_<timestamp>/.
% All objective evaluations are additional post-processing evaluations;
% the original GA/PSO/surrogateopt FE budget remains unchanged.

%% ========================================================================
%  USER SETTINGS -- edit these as needed
%  ========================================================================

radiusStudyObjectiveMode = "information";       % "information" or "coverage"
radiusStudyRadiiKm = [10 20 30 40 50 60];       % strictly increasing radii
radiusStudyMaximumCombinations = 50000;          % RAW combinations per radius
radiusStudySkipOversized = true;                 % skip instead of error
radiusStudyCaptureFraction = 0.95;               % observed r95 threshold
radiusStudyMakePlots = true;
radiusStudySaveResults = true;

% PREFERRED for reproducibility: enter your ORIGINAL candidate indices here,
% e.g. [31 104 587]. If left empty, use refined.initialSensorIndices from
% the MATLAB base workspace when this script is run interactively.
radiusStudyInitialIndices = [];

% No saved optimization-study path is needed for this workflow.

%% ========================================================================
%  Project paths and starting network
%  ========================================================================

radiusStudyScriptPath = mfilename("fullpath");
assert(~isempty(radiusStudyScriptPath), ...
    "runDiscreteRadiusStudy:ScriptPath", ...
    "Run this file as a MATLAB script, not by pasting sections individually.");

radiusStudyProjectRoot = fileparts(fileparts(radiusStudyScriptPath));
addpath(fullfile(radiusStudyProjectRoot,"src"));
addpath(fullfile(radiusStudyProjectRoot,"scripts"));

radiusStudyDatabaseFile = fullfile( ...
    radiusStudyProjectRoot,"results","optimization_database.mat");

assert(isfile(radiusStudyDatabaseFile), ...
    "runDiscreteRadiusStudy:DatabaseNotFound", ...
    "Current optimization database not found: %s",radiusStudyDatabaseFile);

if isempty(radiusStudyInitialIndices)
    if exist("refined","var") == 1 && isstruct(refined) && ...
            isfield(refined,"initialSensorIndices") && ...
            ~isempty(refined.initialSensorIndices)
        radiusStudyInitialIndices = double(refined.initialSensorIndices(:));
        fprintf("Using refined.initialSensorIndices from workspace.\n");
    else
        error("runDiscreteRadiusStudy:MissingInitialIndices", ...
            ['Set radiusStudyInitialIndices to the ORIGINAL candidate ' ...
             'IDs you previously passed to refineDiscreteNetwork, ' ...
             'or run this script with the prior refined result in ' ...
             'the workspace. Do NOT use refined.bestSensorIndices.']);
    end
end

radiusStudyInitialIndices = sort(double(radiusStudyInitialIndices(:)));
validateattributes(radiusStudyInitialIndices,{'double'}, ...
    {'vector','nonempty','finite','real','positive','integer'});
assert(numel(unique(radiusStudyInitialIndices)) == ...
    numel(radiusStudyInitialIndices), ...
    "runDiscreteRadiusStudy:DuplicateSensors", ...
    "Original sensor indices must be distinct.");

fprintf("\n============================================================\n");
fprintf("Lunar discrete refinement radius sensitivity\n");
fprintf("============================================================\n");
fprintf("Database:  %s\n",radiusStudyDatabaseFile);
fprintf("Objective: %s\n",radiusStudyObjectiveMode);
fprintf("Original:  %s\n",mat2str(radiusStudyInitialIndices.'));
fprintf("Radii km:  %s\n",mat2str(radiusStudyRadiiKm));
fprintf("Raw combination limit per radius: %.0f\n", ...
    radiusStudyMaximumCombinations);

%% ========================================================================
%  Run the existing cached sensitivity function
%  ========================================================================

radiusStudyConfig = struct();
radiusStudyConfig.databaseFile = string(radiusStudyDatabaseFile);
radiusStudyConfig.initialSensorIndices = radiusStudyInitialIndices;
radiusStudyConfig.objectiveMode = radiusStudyObjectiveMode;
radiusStudyConfig.radiiKm = radiusStudyRadiiKm;
radiusStudyConfig.maximumCombinations = radiusStudyMaximumCombinations;
radiusStudyConfig.skipOversized = radiusStudySkipOversized;
radiusStudyConfig.captureFraction = radiusStudyCaptureFraction;
radiusStudyConfig.saveResults = radiusStudySaveResults;
radiusStudyConfig.makePlots = radiusStudyMakePlots;

radiusStudy = runDiscreteRadiusSensitivity(radiusStudyConfig);

%% ========================================================================
%  Final interpretation / result locations
%  ========================================================================

fprintf("\n============================================================\n");
fprintf("Radius study completed\n");
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
    fprintf("Observed r%.0f: %.2f km (relative to largest completed radius)\n", ...
        100*radiusStudy.captureFraction,radiusStudy.radiusAtCaptureKm);
else
    fprintf("Observed r95 unavailable: no improvement at completed radii.\n");
end

if any(radiusStudy.summaryTable.Status == "skipped_limit")
    fprintf("NOTE: Some radii exceeded maximumCombinations and were skipped.\n");
end

if strlength(radiusStudy.outputDirectory) > 0
    fprintf("Results folder: %s\n",radiusStudy.outputDirectory);
    if strlength(radiusStudy.summaryCsvFile) > 0
        fprintf("CSV: %s\n",radiusStudy.summaryCsvFile);
    end
end

% The radiusStudy struct remains in the MATLAB workspace for inspection.

function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate the curated conference-paper results.
%
% Main output is intentionally compact:
%   Optimization figures:
%     - convergence for information and coverage;
%     - mean objective versus N_s for information and coverage;
%     - best-network DEM geometry for information and coverage;
%     - sensor-selection frequency for information and coverage.
%   Validation figures:
%     - one combined design-RSO RMS/observability heatmap;
%     - one combined operational-RSO RMS/observability heatmap;
%     - one combined Monte Carlo robustness figure when MC results exist.
%   Main tables:
%     - conference_optimization_summary.csv;
%     - conference_estimation_summary.csv.
%
% Detailed diagnostics are retained under tables/diagnostics and redundant
% plots are moved to supplemental so the main output directory stays clean.

arguments
    userConfig (1,1) struct = struct()
end

results = struct();

results.production = plotProductionOptimizationResults(userConfig);
results.perRsoEkf = plotPerRsoEkfHeatmaps(userConfig);
results.operationalRso = evaluateOperationalRsoNetworks(userConfig);
results.operationalRsoFigure = ...
    plotOperationalRsoTrackingHeatmaps(results.operationalRso,userConfig);
results.monteCarlo = plotMonteCarloConferenceFigure(userConfig);
results.tables = buildConferenceSummaryTables(userConfig);
results.formatting = formatProductionConferenceFigures(results,userConfig);
results.organization = organizeConferenceOutputs(results);

fprintf("\n============================================================\n");
fprintf("Curated conference result generation complete\n");
fprintf("============================================================\n");

fprintf("Main optimization figure groups:\n");
printGroup(results.production.convergence,"  Convergence");
printGroup(results.production.meanObjective,"  Mean objective vs N_s");
printGroup(results.production.geometry,"  Best-network DEM geometry");
printGroup(results.production.networkLocations,"  Selection-frequency maps");

fprintf("Main validation figures:\n");
fprintf("  %s\n",results.perRsoEkf.outputFile);
fprintf("  %s\n",results.operationalRsoFigure.outputFile);
if results.monteCarlo.available
    fprintf("  %s\n",results.monteCarlo.outputFile);
end

fprintf("Main paper tables:\n");
fprintf("  %s\n",results.tables.optimizationFile);
fprintf("  %s\n",results.tables.estimationFile);

fprintf("Supporting diagnostics:\n");
fprintf("  %s\n",results.organization.diagnosticsDirectory);
fprintf("Supplemental figures:\n");
fprintf("  %s\n",results.organization.supplementalDirectory);

end

%% ------------------------------------------------------------------------
function info = organizeConferenceOutputs(results)
outputDirectory = string(results.production.outputDirectory);
supplementalDirectory = fullfile(outputDirectory,"supplemental");
tableDirectory = fullfile(outputDirectory,"tables");
diagnosticsDirectory = fullfile(tableDirectory,"diagnostics");
if ~isfolder(supplementalDirectory), mkdir(supplementalDirectory); end
if ~isfolder(diagnosticsDirectory), mkdir(diagnosticsDirectory); end

% Close redundant figures that are not part of the main-paper set.
if isfield(results.production,"objectiveDistributions")
    fields = fieldnames(results.production.objectiveDistributions);
    for fieldIndex = 1:numel(fields)
        entry = results.production.objectiveDistributions.(fields{fieldIndex});
        if isfield(entry,"figure") && isgraphics(entry.figure)
            close(entry.figure);
        end
    end
end
if isfield(results.operationalRso,"rmsFigure") && isgraphics(results.operationalRso.rmsFigure)
    close(results.operationalRso.rmsFigure);
end
if isfield(results.operationalRso,"observabilityFigure") && ...
        isgraphics(results.operationalRso.observabilityFigure)
    close(results.operationalRso.observabilityFigure);
end

% Explicit whitelist for the main result directory. Any other EPS/PNG/FIG file
% is supporting material and is moved to supplemental. This also cleans stale
% files left by older versions of the plotting pipeline.
mainFigureNames = [ ...
    "convergence_information.eps"; ...
    "convergence_coverage.eps"; ...
    "mean_objective_vs_ns_information.eps"; ...
    "mean_objective_vs_ns_coverage.eps"; ...
    "sensor_geometry_n3_n10_information.eps"; ...
    "sensor_geometry_n3_n10_coverage.eps"; ...
    "network_locations_vs_ns_information.eps"; ...
    "network_locations_vs_ns_coverage.eps"; ...
    "design_rso_tracking_heatmaps.eps"; ...
    "operational_rso_tracking_heatmaps.eps"; ...
    "monte_carlo_robustness.eps"];

extensions = ["*.eps","*.png","*.fig"];
for extensionIndex = 1:numel(extensions)
    files = dir(fullfile(outputDirectory,extensions(extensionIndex)));
    for fileIndex = 1:numel(files)
        fileName = string(files(fileIndex).name);
        if any(fileName == mainFigureNames)
            continue
        end
        sourceFile = string(fullfile(files(fileIndex).folder,files(fileIndex).name));
        moveSupportingFile(sourceFile,supplementalDirectory);
    end
end

% Keep only the two paper-ready CSVs at tables/. Everything else is supporting
% data and is moved one level deeper without deleting it.
mainTableNames = ["conference_optimization_summary.csv", ...
    "conference_estimation_summary.csv"];
csvFiles = dir(fullfile(tableDirectory,"*.csv"));
for fileIndex = 1:numel(csvFiles)
    if any(string(csvFiles(fileIndex).name) == mainTableNames)
        continue
    end
    sourceFile = string(fullfile(csvFiles(fileIndex).folder,csvFiles(fileIndex).name));
    destinationFile = fullfile(diagnosticsDirectory,csvFiles(fileIndex).name);
    movefile(sourceFile,destinationFile,"f");
end

info = struct();
info.supplementalDirectory = string(supplementalDirectory);
info.diagnosticsDirectory = string(diagnosticsDirectory);
info.mainFigureNames = mainFigureNames;
info.mainTableFiles = [ ...
    string(fullfile(tableDirectory,mainTableNames(1))); ...
    string(fullfile(tableDirectory,mainTableNames(2)))];
end

function moveSupportingFile(sourceFile,destinationDirectory)
if strlength(sourceFile) == 0 || ~isfile(sourceFile), return, end
[~,name,extension] = fileparts(sourceFile);
destinationFile = fullfile(destinationDirectory,string(name) + string(extension));
movefile(sourceFile,destinationFile,"f");
end

function printGroup(groupStruct,label)
fprintf("%s:\n",label);
fields = fieldnames(groupStruct);
for fieldIndex = 1:numel(fields)
    entry = groupStruct.(fields{fieldIndex});
    if isfield(entry,"outputFile")
        fprintf("    %s\n",entry.outputFile);
    end
end
end

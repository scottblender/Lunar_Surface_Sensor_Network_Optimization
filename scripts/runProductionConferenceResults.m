function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate only the paper-ready result set.
%
% The final paper output is intentionally minimal:
%   1) convergence: information and coverage;
%   2) sensor-selection frequency: information and coverage;
%   3) one combined design-RSO RMS/observability heatmap;
%   4) one combined operational-RSO RMS/observability heatmap;
%   5) two Monte Carlo robustness subfigures, when available.
%
% A discrete candidate-neighbor robustness study is also evaluated for the
% best network in every N_s/objective case. It produces diagnostic CSV/MAT
% outputs only, not another paper figure or main table.
%
% The two Monte Carlo files are designed to be placed side-by-side in LaTeX.
% Mean-objective plots, best-network geometry plots, final-objective boxplots,
% and separate operational heatmaps are redundant and are removed.
%
% Main paper tables:
%   1) conference_optimization_summary.csv;
%   2) conference_estimation_summary.csv.
%
% Detailed CSV diagnostics are retained under tables/diagnostics. Intermediate
% figures are generated invisibly by legacy helpers and closed before the paper
% figures are shown, so the runner does not flood MATLAB with figure windows.

arguments
    userConfig (1,1) struct = struct()
end

rootHandle = groot;
originalFigureVisibility = get(rootHandle,"defaultFigureVisible");
set(rootHandle,"defaultFigureVisible","off");
visibilityCleanup = onCleanup(@() ...
    set(rootHandle,"defaultFigureVisible",originalFigureVisibility));

results = struct();
results.production = plotProductionOptimizationResults(userConfig);
results.perRsoEkf = plotPerRsoEkfHeatmaps(userConfig);
results.operationalRso = evaluateOperationalRsoNetworks(userConfig);
results.operationalRsoFigure = ...
    plotOperationalRsoTrackingHeatmaps(results.operationalRso,userConfig);
results.monteCarlo = plotMonteCarloConferenceFigure(userConfig);
results.discreteNeighbor = ...
    evaluateDiscreteNeighborRobustness(results.production,userConfig);
results.tables = buildConferenceSummaryTables(userConfig);
results.formatting = formatProductionConferenceFigures(results,userConfig);
results.organization = organizeConferenceOutputs(results);

set(rootHandle,"defaultFigureVisible",originalFigureVisibility);
if string(originalFigureVisibility) == "on"
    showPaperFigures(results);
end

fprintf("\n============================================================\n");
fprintf("Paper result generation complete\n");
fprintf("============================================================\n");

fprintf("Paper figures:\n");
printGroup(results.production.convergence,"  Convergence");
printGroup(results.production.networkLocations,"  Selection-frequency maps");
fprintf("  Design-RSO tracking:\n    %s\n",results.perRsoEkf.outputFile);
fprintf("  Operational-RSO tracking:\n    %s\n", ...
    results.operationalRsoFigure.outputFile);
if results.monteCarlo.available
    fprintf("  Monte Carlo robustness:\n");
    fprintf("    %s\n",results.monteCarlo.information.outputFile);
    fprintf("    %s\n",results.monteCarlo.coverage.outputFile);
end

fprintf("Paper tables:\n");
fprintf("  %s\n",results.tables.optimizationFile);
fprintf("  %s\n",results.tables.estimationFile);
fprintf("Discrete-neighbor diagnostic summary:\n  %s\n", ...
    results.discreteNeighbor.summaryFile);
fprintf("Diagnostic CSVs:\n  %s\n",results.organization.diagnosticsDirectory);

clear visibilityCleanup
end

%% ------------------------------------------------------------------------
function info = organizeConferenceOutputs(results)
outputDirectory = string(results.production.outputDirectory);
tableDirectory = fullfile(outputDirectory,"tables");
diagnosticsDirectory = fullfile(tableDirectory,"diagnostics");
supplementalDirectory = fullfile(outputDirectory,"supplemental");
if ~isfolder(diagnosticsDirectory), mkdir(diagnosticsDirectory); end

closeFigureGroup(results.production,"meanObjective");
closeFigureGroup(results.production,"geometry");
closeFigureGroup(results.production,"objectiveDistributions");
if isfield(results.operationalRso,"rmsFigure") && ...
        isgraphics(results.operationalRso.rmsFigure)
    close(results.operationalRso.rmsFigure);
end
if isfield(results.operationalRso,"observabilityFigure") && ...
        isgraphics(results.operationalRso.observabilityFigure)
    close(results.operationalRso.observabilityFigure);
end

mainFigureNames = [ ...
    "convergence_information.eps"; ...
    "convergence_coverage.eps"; ...
    "network_locations_vs_ns_information.eps"; ...
    "network_locations_vs_ns_coverage.eps"; ...
    "design_rso_tracking_heatmaps.eps"; ...
    "operational_rso_tracking_heatmaps.eps"; ...
    "monte_carlo_information.eps"; ...
    "monte_carlo_coverage.eps"];

deleteNonPaperFigures(outputDirectory,mainFigureNames);
if isfolder(supplementalDirectory)
    deleteGeneratedFigures(supplementalDirectory);
    try
        if isempty(dir(fullfile(supplementalDirectory,"*.*")))
            rmdir(supplementalDirectory);
        end
    catch
    end
end

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
info.diagnosticsDirectory = string(diagnosticsDirectory);
info.mainFigureNames = mainFigureNames;
info.mainTableFiles = [ ...
    string(fullfile(tableDirectory,mainTableNames(1))); ...
    string(fullfile(tableDirectory,mainTableNames(2)))];
end

function closeFigureGroup(parent,fieldName)
if ~isfield(parent,fieldName), return, end
group = parent.(fieldName);
fields = fieldnames(group);
for fieldIndex = 1:numel(fields)
    entry = group.(fields{fieldIndex});
    if isfield(entry,"figure") && isgraphics(entry.figure)
        close(entry.figure);
    end
end
end

function deleteNonPaperFigures(directoryName,mainFigureNames)
extensions = ["*.eps","*.png","*.fig"];
for extensionIndex = 1:numel(extensions)
    files = dir(fullfile(directoryName,extensions(extensionIndex)));
    for fileIndex = 1:numel(files)
        fileName = string(files(fileIndex).name);
        if any(fileName == mainFigureNames)
            continue
        end
        delete(fullfile(files(fileIndex).folder,files(fileIndex).name));
    end
end
end

function deleteGeneratedFigures(directoryName)
extensions = ["*.eps","*.png","*.fig"];
for extensionIndex = 1:numel(extensions)
    files = dir(fullfile(directoryName,extensions(extensionIndex)));
    for fileIndex = 1:numel(files)
        delete(fullfile(files(fileIndex).folder,files(fileIndex).name));
    end
end
end

function showPaperFigures(results)
showFigureGroup(results.production,"convergence");
showFigureGroup(results.production,"networkLocations");
if isfield(results.perRsoEkf,"figure") && isgraphics(results.perRsoEkf.figure)
    results.perRsoEkf.figure.Visible = "on";
end
if isfield(results.operationalRsoFigure,"figure") && ...
        isgraphics(results.operationalRsoFigure.figure)
    results.operationalRsoFigure.figure.Visible = "on";
end
if isfield(results.monteCarlo,"available") && results.monteCarlo.available
    objectiveFields = ["information","coverage"];
    for objectiveField = objectiveFields
        fieldName = char(objectiveField);
        if isfield(results.monteCarlo,fieldName) && ...
                isfield(results.monteCarlo.(fieldName),"figure") && ...
                isgraphics(results.monteCarlo.(fieldName).figure)
            results.monteCarlo.(fieldName).figure.Visible = "on";
        end
    end
end
end

function showFigureGroup(parent,fieldName)
if ~isfield(parent,fieldName), return, end
group = parent.(fieldName);
fields = fieldnames(group);
for fieldIndex = 1:numel(fields)
    entry = group.(fields{fieldIndex});
    if isfield(entry,"figure") && isgraphics(entry.figure)
        entry.figure.Visible = "on";
    end
end
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

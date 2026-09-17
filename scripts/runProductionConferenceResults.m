function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate only the paper-ready result set.
%
% The final paper output is intentionally minimal:
%   1) convergence: information and coverage;
%   2) sensor-selection frequency: information and coverage;
%   3) one combined design-RSO RMS/observability heatmap;
%   4) one combined operational-RSO RMS/observability heatmap;
%   5) separate Monte Carlo boxplots for each objective/network size.
%
% Additional validation studies do not add paper figures:
%   - discrete candidate-neighbor robustness/local optimality;
%   - synthetic-versus-full DEM terrain-resolution validation at the exact
%     optimized sites.
%
% Canonical DEM files:
%   synthetic: data/Synthetic_Lunar_DEM.mat
%   full:      data/Full_Resolution_DEM.mat
%
% Main paper tables:
%   1) conference_optimization_summary.csv;
%   2) conference_estimation_summary.csv;
%   3) conference_dem_resolution_validation.csv.
%
% Detailed CSV diagnostics are retained under tables/diagnostics. Intermediate
% figures are generated invisibly by legacy helpers and closed before the paper
% figures are shown, so the runner does not flood MATLAB with figure windows.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
dataDirectory = fullfile(projectRoot,"data");

if ~isfield(userConfig,"demFile") || strlength(string(userConfig.demFile)) == 0
    userConfig.demFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
end
if ~isfield(userConfig,"syntheticDemFile") || ...
        strlength(string(userConfig.syntheticDemFile)) == 0
    userConfig.syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
end
if ~isfield(userConfig,"fullDemFile") || ...
        strlength(string(userConfig.fullDemFile)) == 0
    userConfig.fullDemFile = fullfile(dataDirectory,"Full_Resolution_DEM.mat");
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
results.demValidation = ...
    evaluateDemResolutionValidation(results.production,userConfig);
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
    printMonteCarloGroup(results.monteCarlo);
end

fprintf("Paper tables:\n");
fprintf("  %s\n",results.tables.optimizationFile);
fprintf("  %s\n",results.tables.estimationFile);
fprintf("  %s\n",results.demValidation.outputFile);
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
    "monte_carlo_information_n3.eps"; ...
    "monte_carlo_information_n5.eps"; ...
    "monte_carlo_information_n7.eps"; ...
    "monte_carlo_information_n10.eps"; ...
    "monte_carlo_coverage_n3.eps"; ...
    "monte_carlo_coverage_n5.eps"; ...
    "monte_carlo_coverage_n7.eps"; ...
    "monte_carlo_coverage_n10.eps"];

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

mainTableNames = [ ...
    "conference_optimization_summary.csv", ...
    "conference_estimation_summary.csv", ...
    "conference_dem_resolution_validation.csv"];
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
info.mainTableFiles = strings(numel(mainTableNames),1);
for tableIndex = 1:numel(mainTableNames)
    info.mainTableFiles(tableIndex) = ...
        string(fullfile(tableDirectory,mainTableNames(tableIndex)));
end
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
    showMonteCarloFigures(results.monteCarlo);
end
end

function showMonteCarloFigures(monteCarlo)
objectiveFields = ["information","coverage"];
for objectiveField = objectiveFields
    fieldName = char(objectiveField);
    if ~isfield(monteCarlo,fieldName), continue, end
    group = monteCarlo.(fieldName);
    networkFields = fieldnames(group);
    for networkFieldIndex = 1:numel(networkFields)
        entry = group.(networkFields{networkFieldIndex});
        if isfield(entry,"figure") && isgraphics(entry.figure)
            entry.figure.Visible = "on";
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

function printMonteCarloGroup(monteCarlo)
objectiveFields = ["information","coverage"];
for objectiveField = objectiveFields
    fieldName = char(objectiveField);
    if ~isfield(monteCarlo,fieldName), continue, end
    group = monteCarlo.(fieldName);
    networkFields = fieldnames(group);
    for networkFieldIndex = 1:numel(networkFields)
        entry = group.(networkFields{networkFieldIndex});
        if isfield(entry,"outputFile")
            fprintf("    %s\n",entry.outputFile);
        end
    end
end
end

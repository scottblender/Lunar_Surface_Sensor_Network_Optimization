function results = runProductionConferenceResults(userConfig)
% RUNPRODUCTIONCONFERENCERESULTS Generate only the paper-ready result set.
%
<<<<<<< HEAD
% The final paper output is intentionally minimal:
%   1) convergence: information and coverage;
%   2) sensor-selection frequency: information and coverage;
%   3) one combined design-RSO RMS/observability heatmap;
%   4) one combined operational-RSO RMS/observability heatmap;
%   5) two Monte Carlo robustness subfigures, when available.
%
% Additional validation studies do not add paper figures:
%   - discrete candidate-neighbor robustness/local optimality;
%   - synthetic-versus-full DEM terrain-resolution validation at the exact
%     optimized sites.
%
% Main paper tables:
%   1) conference_optimization_summary.csv;
%   2) conference_estimation_summary.csv;
%   3) conference_dem_resolution_validation.csv.
%
% Detailed CSV diagnostics are retained under tables/diagnostics. Intermediate
% figures are generated invisibly by legacy helpers and closed before the paper
% figures are shown, so the runner does not flood MATLAB with figure windows.
=======
% This wrapper runs the production optimization figures/tables, per-RSO EKF
% heatmaps, compact paper-ready tables, and -- when a completed local Monte
% Carlo study exists -- the Monte Carlo robustness boxplots. All main-paper
% figure products are collected under results/production_figures.
%
% The large manuscript typography is applied first, then the generated
% production figures are resized/re-exported so ticks, labels, tiled layouts,
% and annotations have enough source-canvas area before LaTeX reduction.
%
% Usage:
%   results = runProductionConferenceResults;
%   results = runProductionConferenceResults(config);
%
% Optional MC override:
%   config.monteCarloResultsFile = "path/to/monte_carlo_results.mat";
>>>>>>> origin/Scott

arguments
    userConfig (1,1) struct = struct()
end

<<<<<<< HEAD
rootHandle = groot;
originalFigureVisibility = get(rootHandle,"defaultFigureVisible");
set(rootHandle,"defaultFigureVisible","off");
visibilityCleanup = onCleanup(@() ...
    set(rootHandle,"defaultFigureVisible",originalFigureVisibility));
=======
scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsRoot = fullfile(projectRoot,"results");
>>>>>>> origin/Scott

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

% Re-size/re-export the existing result figures after the larger manuscript
% font has been applied. This keeps all canonical EPS filenames unchanged.
results.formatting = formatProductionConferenceFigures(results,userConfig);

%% Monte Carlo robustness figures, when available
monteCarloResultsFile = resolveMonteCarloResultsFile( ...
    resultsRoot,userConfig,results.production.configuration);

if strlength(monteCarloResultsFile) > 0
    results.monteCarlo = plotMonteCarloRobustness( ...
        monteCarloResultsFile,results.production.outputDirectory);
    results.monteCarlo.status = "generated";
else
    results.monteCarlo = struct();
    results.monteCarlo.status = "not_available";
    results.monteCarlo.resultsFile = "";
end

fprintf("\n============================================================\n");
fprintf("Paper result generation complete\n");
fprintf("============================================================\n");

<<<<<<< HEAD
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
=======
if results.monteCarlo.status == "generated"
    fprintf("Monte Carlo main-paper figures:\n  %s\n  %s\n", ...
        results.monteCarlo.informationFigure, ...
        results.monteCarlo.coverageFigure);
else
    fprintf(["Monte Carlo figures: no completed monte_carlo_results.mat was " ...
        "found yet. They will be added automatically after the MC study.\n"]);
end

end

%% ------------------------------------------------------------------------
function resultsFile = resolveMonteCarloResultsFile( ...
    resultsRoot,userConfig,productionConfig)
resultsFile = "";

% Explicit caller request takes precedence.
if isfield(userConfig,"monteCarloResultsFile")
    requestedFile = string(userConfig.monteCarloResultsFile);
    if strlength(requestedFile) > 0 && isfile(requestedFile)
        assertCompletedMonteCarlo(requestedFile);
        resultsFile = requestedFile;
        return
    end
end

% Preserve compatibility with the placeholder/configuration field already
% carried by plotProductionOptimizationResults if the file actually exists.
if isfield(productionConfig,"monteCarloResultsFile")
    configuredFile = string(productionConfig.monteCarloResultsFile);
    if strlength(configuredFile) > 0 && isfile(configuredFile)
        assertCompletedMonteCarlo(configuredFile);
        resultsFile = configuredFile;
        return
    end
end

% Otherwise find the newest completed timestamped Monte Carlo study.
monteCarloRoot = fullfile(resultsRoot,"monte_carlo_robustness");
if ~isfolder(monteCarloRoot)
    return
end

files = dir(fullfile(monteCarloRoot,"**","monte_carlo_results.mat"));
if isempty(files)
    return
end
[~,order] = sort([files.datenum],"descend");
files = files(order);

for k = 1:numel(files)
    candidate = string(fullfile(files(k).folder,files(k).name));
    try
        data = load(candidate,"studyState");
        if isfield(data,"studyState") && isfield(data.studyState,"completed") && ...
                logical(data.studyState.completed)
            resultsFile = candidate;
            return
        end
    catch
        % Ignore incomplete/corrupt candidates and continue to the next one.
>>>>>>> origin/Scott
    end
end
end

<<<<<<< HEAD
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
=======
function assertCompletedMonteCarlo(resultsFile)
data = load(resultsFile,"studyState");
assert(isfield(data,"studyState") && isfield(data.studyState,"completed") && ...
    logical(data.studyState.completed), ...
    "Requested Monte Carlo result is incomplete: %s",resultsFile);
>>>>>>> origin/Scott
end

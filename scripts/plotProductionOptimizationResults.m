function figureInfo = plotProductionOptimizationResults(userConfig)
% PLOTPRODUCTIONOPTIMIZATIONRESULTS Create conference-paper result products.
%
% Figures generated for the completed production campaign:
%   1) Mean best-so-far convergence versus function evaluations.
%   2) Mean final objective versus network size with +/- one sample std.
%   3) DEM-backed overall-best geometry for N_s = 3 and N_s = 10.
%   4) DEM-backed sensor-selection frequency versus network size.
%   5) Final-objective box-and-whisker distributions versus network size.
%
% Tables printed and written to CSV:
%   - optimization summary across all 20 runs per case;
%   - solution-diversity / sensor-set overlap metrics;
%   - overall-best network definitions;
%   - fixed-noise EKF estimation metrics for each overall-best network;
%   - optional per-RSO EKF tables for each overall-best network.
%
% Monte Carlo plotting remains intentionally reserved for a future MC driver.
% The expected MC result-file path and data convention are returned in
% figureInfo.monteCarlo.
%
% Default production definition:
%   network sizes:      [3 5 7 10]
%   objectives:         information, coverage
%   runs/case:          20
%   FE/run:             6000
%   population size:    60
%   seeds/case:         1000:1019
%
% Usage
%   figureInfo = plotProductionOptimizationResults;
%
% Optional configuration example
%   config = struct();
%   config.computeEstimationMetrics = true;
%   config.measurementNoiseSeed = 5000;
%   figureInfo = plotProductionOptimizationResults(config);

arguments
    userConfig (1,1) struct = struct()
end

%% ========================================================================
%  Project paths and configuration
%  ========================================================================

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
dataDirectory = fullfile(projectRoot,"data");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
addpath(scriptDirectory);
rehash path;

style = publicationPlotStyle();

defaultConfig = struct();
defaultConfig.resultsDirectory = resultsDirectory;
defaultConfig.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
defaultConfig.outputDirectory = fullfile(resultsDirectory,"production_figures");
defaultConfig.demFile = "";
defaultConfig.networkSizes = [3 5 7 10];
defaultConfig.objectiveModes = ["information","coverage"];
defaultConfig.geometryNetworkSizes = [3 10];
defaultConfig.numberOfRuns = 20;
defaultConfig.functionEvaluationBudget = 6000;
defaultConfig.populationSize = 60;
defaultConfig.baseSeed = 1000;
defaultConfig.studyName = "lunar_surface_production_optimization";
defaultConfig.maximumCampaignSpanHours = 168;
defaultConfig.exportResolution = 600;
defaultConfig.closeExistingFigures = false;
defaultConfig.computeEstimationMetrics = true;
defaultConfig.reuseEstimationMetricCache = true;
defaultConfig.writePerRsoTables = true;
defaultConfig.measurementNoiseSeed = 5000;
defaultConfig.monteCarloResultsFile = ...
    fullfile(resultsDirectory,"monte_carlo","production_mc_results.mat");

config = mergeStruct(defaultConfig,userConfig);
config.resultsDirectory = string(config.resultsDirectory);
config.databaseFile = string(config.databaseFile);
config.outputDirectory = string(config.outputDirectory);
config.demFile = string(config.demFile);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));
config.geometryNetworkSizes = double(config.geometryNetworkSizes(:).');
config.studyName = string(config.studyName);
config.monteCarloResultsFile = string(config.monteCarloResultsFile);

validateattributes(config.networkSizes,{'numeric'}, ...
    {'vector','integer','positive','nonempty'});
validateattributes(config.geometryNetworkSizes,{'numeric'}, ...
    {'vector','integer','positive','numel',2});
validateattributes(config.numberOfRuns,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.functionEvaluationBudget,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.populationSize,{'numeric'}, ...
    {'scalar','integer','>=',2});
validateattributes(config.baseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
validateattributes(config.maximumCampaignSpanHours,{'numeric'}, ...
    {'scalar','real','positive'});
validateattributes(config.exportResolution,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.measurementNoiseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
assert(islogical(config.closeExistingFigures) && isscalar(config.closeExistingFigures), ...
    "closeExistingFigures must be a scalar logical.");
assert(islogical(config.computeEstimationMetrics) && isscalar(config.computeEstimationMetrics), ...
    "computeEstimationMetrics must be a scalar logical.");
assert(islogical(config.reuseEstimationMetricCache) && isscalar(config.reuseEstimationMetricCache), ...
    "reuseEstimationMetricCache must be a scalar logical.");
assert(islogical(config.writePerRsoTables) && isscalar(config.writePerRsoTables), ...
    "writePerRsoTables must be a scalar logical.");
assert(all(ismember(config.objectiveModes,["information","coverage"])), ...
    "objectiveModes may contain only information and coverage.");
assert(all(ismember(config.geometryNetworkSizes,config.networkSizes)), ...
    "geometryNetworkSizes must be contained in networkSizes.");
assert(mod(config.functionEvaluationBudget,config.populationSize) == 0, ...
    "functionEvaluationBudget must be divisible by populationSize.");

if config.closeExistingFigures
    close all;
end

if ~isfolder(config.outputDirectory)
    mkdir(config.outputDirectory);
end

tableDirectory = fullfile(config.outputDirectory,"tables");
if ~isfolder(tableDirectory)
    mkdir(tableDirectory);
end

cacheDirectory = fullfile(config.outputDirectory,"ekf_metric_cache");
if config.computeEstimationMetrics && ~isfolder(cacheDirectory)
    mkdir(cacheDirectory);
end

%% ========================================================================
%  Load frozen production database and DEM
%  ========================================================================

assert(isfile(config.databaseFile), ...
    "Production optimization database was not found: %s",config.databaseFile);

databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
database = databaseData.database;

moonRadiusKm = database.config.moon.radiusKm;
demFile = resolveDemFile(config,database,dataDirectory);
[demInterpolant,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,moonRadiusKm,24,48);
demPlot = buildDemPlotData(database,demInterpolant,moonRadiusKm);

%% ========================================================================
%  Resolve and load the completed production campaign
%  ========================================================================

runRoot = fullfile(config.resultsDirectory,"optimization_runs");
assert(isfolder(runRoot), ...
    "Optimization result directory was not found: %s",runRoot);

[summaryFiles,campaignTimes] = resolveStudySummaries(runRoot,config);

numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
numberOfCases = numberOfNetworkSizes*numberOfObjectives;
studies = cell(numberOfNetworkSizes,numberOfObjectives);

for networkIndex = 1:numberOfNetworkSizes
    for objectiveIndex = 1:numberOfObjectives
        summaryFile = summaryFiles(networkIndex,objectiveIndex);
        loadedData = load(summaryFile,"studyState");
        assert(isfield(loadedData,"studyState"), ...
            "Study summary does not contain studyState: %s",summaryFile);
        studies{networkIndex,objectiveIndex} = loadedData.studyState;
    end
end

if all(~isnat(campaignTimes),"all")
    campaignSpanHours = hours(max(campaignTimes(:))-min(campaignTimes(:)));
    assert(campaignSpanHours <= config.maximumCampaignSpanHours, ...
        ["Selected production studies span %.2f hours, exceeding the " ...
         "allowed %.2f-hour campaign window. Results may come from " ...
         "different launches."], ...
        campaignSpanHours,config.maximumCampaignSpanHours);
else
    campaignSpanHours = NaN;
end

fprintf("\n============================================================\n");
fprintf("Production optimization conference results\n");
fprintf("============================================================\n");
fprintf("Database:       %s\n",config.databaseFile);
fprintf("DEM:            %s\n",demFile);
fprintf("Output:         %s\n",config.outputDirectory);
fprintf("Runs per case:  %d\n",config.numberOfRuns);
fprintf("FE per run:     %d\n",config.functionEvaluationBudget);
if isfinite(campaignSpanHours)
    fprintf("Campaign span:  %.2f hr\n",campaignSpanHours);
end

%% ========================================================================
%  Output structure
%  ========================================================================

figureInfo = struct();
figureInfo.version = "production_optimization_figures_v2";
figureInfo.created = string(datetime("now"));
figureInfo.configuration = config;
figureInfo.databaseFile = config.databaseFile;
figureInfo.demFile = demFile;
figureInfo.studySummaryFiles = summaryFiles;
figureInfo.outputDirectory = config.outputDirectory;
figureInfo.convergence = struct();
figureInfo.meanObjective = struct();
figureInfo.geometry = struct();
figureInfo.networkLocations = struct();
figureInfo.objectiveDistributions = struct();
figureInfo.tables = struct();

networkColors = [ ...
    style.blueColor; ...
    style.orangeColor; ...
    style.greenColor; ...
    style.magentaColor];
assert(numberOfNetworkSizes <= size(networkColors,1), ...
    "Add more plotting colors for additional network sizes.");

%% ========================================================================
%  Figure 1: convergence curves
%  ========================================================================

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);

    fig = figure( ...
        "Name",sprintf("%s objective convergence",objectiveMode), ...
        "Color",style.backgroundColor, ...
        "Units","inches", ...
        "Position",[1 1 style.exportWidthInches 4.65], ...
        "Renderer","painters");
    ax = axes(fig);
    hold(ax,"on");

    legendHandles = gobjects(numberOfNetworkSizes,1);
    legendText = strings(numberOfNetworkSizes,1);

    for networkIndex = 1:numberOfNetworkSizes
        studyState = studies{networkIndex,objectiveIndex};
        [functionEvaluations,meanHistory,stdHistory] = ...
            aggregateConvergence(studyState,config.numberOfRuns);
        color = networkColors(networkIndex,:);

        fill(ax, ...
            [functionEvaluations;flipud(functionEvaluations)], ...
            [meanHistory-stdHistory;flipud(meanHistory+stdHistory)], ...
            color,"FaceAlpha",0.12,"EdgeColor","none", ...
            "HandleVisibility","off");

        legendHandles(networkIndex) = plot(ax, ...
            functionEvaluations,meanHistory, ...
            "Color",color,"LineWidth",2.2);
        legendText(networkIndex) = sprintf("N_s = %d",config.networkSizes(networkIndex));
    end

    xlabel(ax,"Function evaluations");
    ylabel(ax,"Best-so-far objective, J");
    xlim(ax,[config.populationSize config.functionEvaluationBudget]);
    applyAxesStyle(ax,style);
    lgd = legend(ax,legendHandles,legendText,"Location","best","Interpreter","tex");
    applyLegendStyle(lgd,style);

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("convergence_%s.eps",objectiveMode));
    exportVectorFigure(fig,outputFile,style);
    figureInfo.convergence.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end

%% ========================================================================
%  Figure 2: mean final objective versus network size
%  ========================================================================

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);
    meanObjective = zeros(numberOfNetworkSizes,1);
    stdObjective = zeros(numberOfNetworkSizes,1);

    for networkIndex = 1:numberOfNetworkSizes
        studyState = studies{networkIndex,objectiveIndex};
        meanObjective(networkIndex) = mean(studyState.bestObjectives(:));
        stdObjective(networkIndex) = std(studyState.bestObjectives(:));
    end

    fig = figure( ...
        "Name",sprintf("%s mean objective versus network size",objectiveMode), ...
        "Color",style.backgroundColor, ...
        "Units","inches", ...
        "Position",[1 1 style.exportWidthInches 4.65], ...
        "Renderer","painters");
    ax = axes(fig);
    hold(ax,"on");

    objectiveColor = objectivePlotColor(objectiveMode,style);
    errorbar(ax,config.networkSizes,meanObjective,stdObjective, ...
        "-o","Color",objectiveColor, ...
        "MarkerFaceColor",objectiveColor, ...
        "MarkerEdgeColor",style.backgroundColor, ...
        "LineWidth",2.2,"MarkerSize",8,"CapSize",10);

    xlabel(ax,"Number of sensors, N_s");
    ylabel(ax,"Final objective, J");
    xticks(ax,config.networkSizes);
    xlim(ax,[min(config.networkSizes)-0.5 max(config.networkSizes)+0.5]);
    applyAxesStyle(ax,style);

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("mean_objective_vs_ns_%s.eps",objectiveMode));
    exportVectorFigure(fig,outputFile,style);
    figureInfo.meanObjective.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile), ...
        "networkSizes",config.networkSizes(:), ...
        "meanObjective",meanObjective,"stdObjective",stdObjective);
end

%% ========================================================================
%  Figure 3: DEM-backed overall-best geometry, N_s = 3 versus N_s = 10
%  ========================================================================

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);
    objectiveColor = objectivePlotColor(objectiveMode,style);

    fig = figure( ...
        "Name",sprintf("%s optimized sensor geometry",objectiveMode), ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[0.5 0.5 10.0 5.1],"Renderer","opengl");
    fig.InvertHardcopy = "off";
    layout = tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
    panelAxes = gobjects(1,2);

    for geometryIndex = 1:numel(config.geometryNetworkSizes)
        networkSize = config.geometryNetworkSizes(geometryIndex);
        networkIndex = find(config.networkSizes == networkSize,1);
        studyState = studies{networkIndex,objectiveIndex};
        panelAxes(geometryIndex) = nexttile(layout,geometryIndex);
        drawDemBackground(panelAxes(geometryIndex),demPlot,style,true);
        sensorIndices = double(studyState.overallBestSensorIndices(:));
        plotSensorNetwork(panelAxes(geometryIndex),sensorIndices,database, ...
            demPlot,objectiveColor,style,104);
        title(panelAxes(geometryIndex),sprintf("N_s = %d",networkSize), ...
            "FontName",style.fontName,"FontSize",style.labelFontSize, ...
            "FontWeight","bold","Color",style.textColor);
    end

    cb = colorbar(panelAxes(end));
    cb.Layout.Tile = "east";
    styleColorbar(cb,style);

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("sensor_geometry_n3_n10_%s.eps",objectiveMode));
    exportRasterFigure(fig,outputFile,style,config.exportResolution);
    figureInfo.geometry.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end

%% ========================================================================
%  Figure 4: network locations versus N_s across all 20 runs
%  ========================================================================

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);
    objectiveColor = objectivePlotColor(objectiveMode,style);

    fig = figure( ...
        "Name",sprintf("%s network locations versus N_s",objectiveMode), ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[0.5 0.5 8.2 7.4],"Renderer","opengl");
    fig.InvertHardcopy = "off";
    layout = tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
    panelAxes = gobjects(numberOfNetworkSizes,1);

    maximumMarkerArea = 150;
    minimumMarkerArea = 16;

    for networkIndex = 1:numberOfNetworkSizes
        networkSize = config.networkSizes(networkIndex);
        studyState = studies{networkIndex,objectiveIndex};
        panelAxes(networkIndex) = nexttile(layout,networkIndex);
        drawDemBackground(panelAxes(networkIndex),demPlot,style,false);

        selectionCounts = zeros(database.meta.numberOfCandidates,1);
        for runIndex = 1:config.numberOfRuns
            indices = double(studyState.runStates{runIndex}.bestSensorIndices(:));
            selectionCounts(indices) = selectionCounts(indices) + 1;
        end

        selectedIndices = find(selectionCounts > 0);
        selectedCounts = selectionCounts(selectedIndices);
        markerArea = minimumMarkerArea + ...
            (maximumMarkerArea-minimumMarkerArea) .* ...
            (selectedCounts/config.numberOfRuns);
        [selectedXKm,selectedYKm] = candidatePolarCoordinates( ...
            selectedIndices,database,demPlot.moonRadiusKm);

        scatter(panelAxes(networkIndex),selectedXKm,selectedYKm,markerArea,"o", ...
            "MarkerFaceColor",objectiveColor, ...
            "MarkerEdgeColor",style.backgroundColor,"LineWidth",0.7);
        title(panelAxes(networkIndex),sprintf("N_s = %d",networkSize), ...
            "FontName",style.fontName,"FontSize",style.labelFontSize, ...
            "FontWeight","bold","Color",style.textColor);
    end

    cb = colorbar(panelAxes(end));
    cb.Layout.Tile = "east";
    styleColorbar(cb,style);

    annotation(fig,"textbox",[0.21 0.005 0.58 0.04], ...
        "String",sprintf( ...
            "Marker area scales with selection frequency across %d runs", ...
            config.numberOfRuns), ...
        "HorizontalAlignment","center","VerticalAlignment","middle", ...
        "EdgeColor","none","Color",style.textColor, ...
        "FontName",style.fontName,"FontSize",style.annotationFontSize, ...
        "FontWeight","bold");

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("network_locations_vs_ns_%s.eps",objectiveMode));
    exportRasterFigure(fig,outputFile,style,config.exportResolution);
    figureInfo.networkLocations.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end

%% ========================================================================
%  Figure 5: final-objective distributions across independent runs
%  ========================================================================

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);
    objectiveColor = objectivePlotColor(objectiveMode,style);

    groupValues = zeros(numberOfNetworkSizes*config.numberOfRuns,1);
    objectiveValues = zeros(size(groupValues));
    rowIndex = 0;

    for networkIndex = 1:numberOfNetworkSizes
        values = studies{networkIndex,objectiveIndex}.bestObjectives(:);
        rows = rowIndex + (1:config.numberOfRuns);
        groupValues(rows) = config.networkSizes(networkIndex);
        objectiveValues(rows) = values;
        rowIndex = rowIndex + config.numberOfRuns;
    end

    fig = figure( ...
        "Name",sprintf("%s objective distributions",objectiveMode), ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 style.exportWidthInches 4.65], ...
        "Renderer","painters");
    ax = axes(fig);

    boxHandle = boxchart(ax,groupValues,objectiveValues);
    boxHandle.BoxFaceColor = objectiveColor;
    boxHandle.MarkerColor = style.grayColor;
    boxHandle.LineWidth = 1.3;

    xlabel(ax,"Number of sensors, N_s");
    ylabel(ax,"Final objective, J");
    xticks(ax,config.networkSizes);
    xlim(ax,[min(config.networkSizes)-0.5 max(config.networkSizes)+0.5]);
    applyAxesStyle(ax,style);

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("final_objective_boxplot_%s.eps",objectiveMode));
    exportVectorFigure(fig,outputFile,style);
    figureInfo.objectiveDistributions.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end

%% ========================================================================
%  Conference-paper tables
%  ========================================================================

[optimizationSummaryTable,diversityTable,bestNetworkTable] = ...
    buildOptimizationTables(studies,database,config);

optimizationSummaryFile = fullfile(tableDirectory,"optimization_summary.csv");
diversityFile = fullfile(tableDirectory,"solution_diversity.csv");
bestNetworkFile = fullfile(tableDirectory,"overall_best_networks.csv");

writetable(optimizationSummaryTable,optimizationSummaryFile);
writetable(diversityTable,diversityFile);
writetable(bestNetworkTable,bestNetworkFile);

fprintf("\n============================================================\n");
fprintf("Optimization summary table\n");
fprintf("============================================================\n");
disp(optimizationSummaryTable);

fprintf("\n============================================================\n");
fprintf("Solution-diversity table\n");
fprintf("============================================================\n");
disp(diversityTable);

fprintf("\n============================================================\n");
fprintf("Overall-best network table\n");
fprintf("============================================================\n");
disp(bestNetworkTable);

figureInfo.tables.optimizationSummary = optimizationSummaryTable;
figureInfo.tables.solutionDiversity = diversityTable;
figureInfo.tables.overallBestNetworks = bestNetworkTable;
figureInfo.tables.optimizationSummaryFile = string(optimizationSummaryFile);
figureInfo.tables.solutionDiversityFile = string(diversityFile);
figureInfo.tables.overallBestNetworksFile = string(bestNetworkFile);

%% ========================================================================
%  Fixed-noise EKF metrics for the overall-best network in every case
%  ========================================================================

if config.computeEstimationMetrics
    [estimationMetricTable,perRsoFiles] = buildEstimationMetricTable( ...
        studies,database,demFile,config,cacheDirectory,tableDirectory);

    estimationMetricFile = fullfile(tableDirectory,"ekf_estimation_metrics.csv");
    writetable(estimationMetricTable,estimationMetricFile);

    fprintf("\n============================================================\n");
    fprintf("Overall-best fixed-noise EKF estimation metrics\n");
    fprintf("Measurement-noise seed: %d\n",config.measurementNoiseSeed);
    fprintf("============================================================\n");
    disp(estimationMetricTable);

    figureInfo.tables.estimationMetrics = estimationMetricTable;
    figureInfo.tables.estimationMetricsFile = string(estimationMetricFile);
    figureInfo.tables.perRsoEstimationFiles = perRsoFiles;
else
    figureInfo.tables.estimationMetrics = table();
    figureInfo.tables.estimationMetricsFile = "";
    figureInfo.tables.perRsoEstimationFiles = strings(0,1);
    fprintf("\nEKF estimation metric generation disabled by configuration.\n");
end

%% ========================================================================
%  Monte Carlo hook -- intentionally idle for now
%  ========================================================================
% Future MC driver convention:
%   mcStudy.version
%   mcStudy.networkSizes
%   mcStudy.objectiveModes
%   mcStudy.cases(caseIndex).networkSize
%   mcStudy.cases(caseIndex).objectiveMode
%   mcStudy.cases(caseIndex).referenceObjective
%   mcStudy.cases(caseIndex).sampleObjectives

figureInfo.monteCarlo = struct();
figureInfo.monteCarlo.enabled = false;
figureInfo.monteCarlo.resultsFile = config.monteCarloResultsFile;
figureInfo.monteCarlo.expectedVariable = "mcStudy";
figureInfo.monteCarlo.status = "reserved_for_future_mc_driver";

%% ========================================================================
%  Console summary
%  ========================================================================

fprintf("\nGenerated production result figures:\n");
printFigureFiles(figureInfo.convergence,"Convergence");
printFigureFiles(figureInfo.meanObjective,"Mean objective vs N_s");
printFigureFiles(figureInfo.geometry,"DEM geometry");
printFigureFiles(figureInfo.networkLocations,"Network locations vs N_s");
printFigureFiles(figureInfo.objectiveDistributions,"Objective boxplots");
fprintf("Tables:\n");
fprintf("  %s\n",optimizationSummaryFile);
fprintf("  %s\n",diversityFile);
fprintf("  %s\n",bestNetworkFile);
if config.computeEstimationMetrics
    fprintf("  %s\n",figureInfo.tables.estimationMetricsFile);
end
fprintf("Monte Carlo plotting: reserved; no MC figure generated.\n");
fprintf("\nplotProductionOptimizationResults complete.\n");

end

%% ========================================================================
%  Local helpers
%  ========================================================================

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    fieldName = fields{fieldIndex};
    overrideValue = override.(fieldName);
    if isfield(output,fieldName) && ...
            isstruct(output.(fieldName)) && isscalar(output.(fieldName)) && ...
            isstruct(overrideValue) && isscalar(overrideValue)
        output.(fieldName) = mergeStruct(output.(fieldName),overrideValue);
    else
        output.(fieldName) = overrideValue;
    end
end
end

function [summaryFiles,campaignTimes] = resolveStudySummaries(runRoot,config)
allSummaryFiles = dir(fullfile(runRoot,"*","study_summary.mat"));
assert(~isempty(allSummaryFiles), ...
    "No study_summary.mat files were found under %s.",runRoot);
[~,sortOrder] = sort([allSummaryFiles.datenum],"descend");
allSummaryFiles = allSummaryFiles(sortOrder);
summaryFiles = strings(numel(config.networkSizes),numel(config.objectiveModes));
campaignTimes = NaT(size(summaryFiles));

for networkIndex = 1:numel(config.networkSizes)
    expectedNetworkSize = config.networkSizes(networkIndex);
    for objectiveIndex = 1:numel(config.objectiveModes)
        expectedObjectiveMode = config.objectiveModes(objectiveIndex);
        matchFound = false;
        for fileIndex = 1:numel(allSummaryFiles)
            candidateFile = string(fullfile( ...
                allSummaryFiles(fileIndex).folder,allSummaryFiles(fileIndex).name));
            candidateData = load(candidateFile,"studyState");
            if ~isfield(candidateData,"studyState")
                continue
            end
            candidateStudy = candidateData.studyState;
            if ~matchesStudyConfiguration( ...
                    candidateStudy,expectedNetworkSize,expectedObjectiveMode,config)
                continue
            end
            candidateDirectory = string(fileparts(candidateFile));
            complete = true;
            for runIndex = 1:config.numberOfRuns
                if ~isfile(fullfile(candidateDirectory, ...
                        sprintf("run_%03d.mat",runIndex)))
                    complete = false;
                    break
                end
            end
            if ~complete
                continue
            end
            summaryFiles(networkIndex,objectiveIndex) = candidateFile;
            [~,folderName] = fileparts(candidateDirectory);
            campaignTimes(networkIndex,objectiveIndex) = extractStudyTimestamp(folderName);
            matchFound = true;
            break
        end
        assert(matchFound, ...
            ["Could not find a complete production study for N=%d, %s. " ...
             "Expected %d runs and %d FE/run."], ...
            expectedNetworkSize,expectedObjectiveMode, ...
            config.numberOfRuns,config.functionEvaluationBudget);
    end
end
assert(numel(unique(summaryFiles)) == numel(summaryFiles), ...
    "The same study summary was selected for more than one case.");
end

function tf = matchesStudyConfiguration( ...
    studyState,expectedNetworkSize,expectedObjectiveMode,config)
tf = isstruct(studyState) && isscalar(studyState) && ...
    isfield(studyState,"config") && isfield(studyState,"numberOfRuns");
if ~tf
    return
end
studyConfig = studyState.config;
requiredFields = {'networkSize','objectiveMode','functionEvaluationBudget', ...
    'populationSize','baseSeed','studyName'};
for fieldIndex = 1:numel(requiredFields)
    if ~isfield(studyConfig,requiredFields{fieldIndex})
        tf = false;
        return
    end
end
tf = ...
    studyState.numberOfRuns == config.numberOfRuns && ...
    studyConfig.networkSize == expectedNetworkSize && ...
    lower(string(studyConfig.objectiveMode)) == expectedObjectiveMode && ...
    studyConfig.functionEvaluationBudget == config.functionEvaluationBudget && ...
    studyConfig.populationSize == config.populationSize && ...
    studyConfig.baseSeed == config.baseSeed && ...
    string(studyConfig.studyName) == config.studyName;
end

function timestamp = extractStudyTimestamp(folderName)
folderName = string(folderName);
tokens = regexp(folderName,"_(\d{8}_\d{6})$","tokens","once");
if isempty(tokens)
    timestamp = NaT;
else
    timestamp = datetime(string(tokens{1}),"InputFormat","yyyyMMdd_HHmmss");
end
end

function [functionEvaluations,meanHistory,stdHistory] = ...
    aggregateConvergence(studyState,numberOfRuns)
assert(numel(studyState.runStates) == numberOfRuns, ...
    "Study contains an unexpected number of run states.");
functionEvaluations = double(studyState.runStates{1}.history.fe(:));
numberOfPoints = numel(functionEvaluations);
allHistories = zeros(numberOfPoints,numberOfRuns);
for runIndex = 1:numberOfRuns
    runState = studyState.runStates{runIndex};
    runFe = double(runState.history.fe(:));
    runBest = double(runState.history.bestJ(:));
    assert(isequal(runFe,functionEvaluations), ...
        "Run %d uses a different FE history grid.",runIndex);
    assert(numel(runBest) == numberOfPoints, ...
        "Run %d convergence history has an unexpected length.",runIndex);
    allHistories(:,runIndex) = runBest;
end
meanHistory = mean(allHistories,2);
stdHistory = std(allHistories,0,2);
end

function color = objectivePlotColor(objectiveMode,style)
switch lower(string(objectiveMode))
    case "information"
        color = style.blueColor;
    case "coverage"
        color = style.redColor;
    otherwise
        color = style.grayColor;
end
end

function demFile = resolveDemFile(config,database,dataDirectory)
if strlength(config.demFile) > 0
    assert(isfile(config.demFile), ...
        "Requested DEM file was not found: %s",config.demFile);
    demFile = config.demFile;
    return
end
if isfield(database,"meta") && isfield(database.meta,"demSource")
    databaseDemFile = string(database.meta.demSource);
    if strlength(databaseDemFile) > 0 && isfile(databaseDemFile)
        demFile = databaseDemFile;
        return
    end
end
if isfield(database,"config") && isfield(database.config,"demSource")
    databaseDemFile = string(database.config.demSource);
    if strlength(databaseDemFile) > 0 && isfile(databaseDemFile)
        demFile = databaseDemFile;
        return
    end
end
candidateNames = [ ...
    "Synthetic:LunarDEM.mat"
    "Synthetic_LunarDEM.mat"
    "SyntheticLunarDEM.mat"
    "Final_Lunar_DEM.mat"];
for candidateIndex = 1:numel(candidateNames)
    candidatePath = string(fullfile(dataDirectory,candidateNames(candidateIndex)));
    if isfile(candidatePath)
        demFile = candidatePath;
        return
    end
end
error("plotProductionOptimizationResults:DemNotFound", ...
    ["No production lunar DEM could be resolved. Set config.demFile or " ...
     "place the DEM in the repository data directory."]);
end

function demPlot = buildDemPlotData(database,demInterpolant,moonRadiusKm)
if isfield(database.config,"candidates") && ...
        isfield(database.config.candidates,"latitudeBandRad")
    latitudeBandDeg = rad2deg(database.config.candidates.latitudeBandRad(:));
    domainSouthDeg = min(latitudeBandDeg);
    domainNorthDeg = max(latitudeBandDeg);
else
    domainSouthDeg = -90;
    domainNorthDeg = -75;
end
longitudeDeg = linspace(0,360,721);
latitudeDeg = linspace(domainSouthDeg,domainNorthDeg,301);
[longitudeMeshDeg,latitudeMeshDeg] = meshgrid(longitudeDeg,latitudeDeg);
elevationKm = double(demInterpolant( ...
    deg2rad(latitudeMeshDeg),deg2rad(longitudeMeshDeg)));
finiteElevation = elevationKm(isfinite(elevationKm));
assert(~isempty(finiteElevation), ...
    "DEM produced no finite samples over the optimization domain.");
polarDistanceKm = moonRadiusKm .* deg2rad(90 + latitudeMeshDeg);
xKm = polarDistanceKm .* sind(longitudeMeshDeg);
yKm = polarDistanceKm .* cosd(longitudeMeshDeg);
demPlot = struct();
demPlot.moonRadiusKm = moonRadiusKm;
demPlot.domainSouthDeg = domainSouthDeg;
demPlot.domainNorthDeg = domainNorthDeg;
demPlot.elevationKm = elevationKm;
demPlot.elevationLimitsKm = [min(finiteElevation) max(finiteElevation)];
demPlot.xKm = xKm;
demPlot.yKm = yKm;
demPlot.outerRadiusKm = moonRadiusKm*deg2rad(90 + domainNorthDeg);
end

function drawDemBackground(ax,demPlot,style,showCoordinateLabels)
hold(ax,"on");
ax.Color = style.backgroundColor;
ax.FontName = style.fontName;
ax.FontWeight = "bold";
ax.SortMethod = "childorder";
surf(ax,demPlot.xKm,demPlot.yKm,zeros(size(demPlot.xKm)), ...
    demPlot.elevationKm,"EdgeColor","none","FaceColor","interp");
view(ax,2);
colormap(ax,turbo(256));
clim(ax,demPlot.elevationLimitsKm);
circleAngleDeg = linspace(0,360,721);
latitudeGridDeg = [-85 -80 demPlot.domainNorthDeg];
gridColor = [0.16 0.16 0.18];
for latitudeIndex = 1:numel(latitudeGridDeg)
    latitudeDeg = latitudeGridDeg(latitudeIndex);
    if latitudeDeg < demPlot.domainSouthDeg || latitudeDeg > demPlot.domainNorthDeg
        continue
    end
    radiusKm = demPlot.moonRadiusKm*deg2rad(90 + latitudeDeg);
    xGrid = radiusKm*sind(circleAngleDeg);
    yGrid = radiusKm*cosd(circleAngleDeg);
    if abs(latitudeDeg-demPlot.domainNorthDeg) < 1e-10
        plot(ax,xGrid,yGrid,"-","Color",style.boundaryColor,"LineWidth",1.8);
    else
        plot(ax,xGrid,yGrid,"--","Color",gridColor,"LineWidth",0.9);
    end
end
for longitudeDeg = [0 90 180 270]
    radialDistanceKm = [0 demPlot.outerRadiusKm];
    plot(ax,radialDistanceKm*sind(longitudeDeg), ...
        radialDistanceKm*cosd(longitudeDeg), ...
        "--","Color",gridColor,"LineWidth",0.9);
end
plot(ax,0,0,".","Color",style.textColor,"MarkerSize",11);
if showCoordinateLabels
    labelRadiusKm = demPlot.outerRadiusKm + 23;
    longitudeGridDeg = [0 90 180 270];
    longitudeLabelText = ["0^{\circ}E","90^{\circ}E","180^{\circ}E","270^{\circ}E"];
    for longitudeIndex = 1:numel(longitudeGridDeg)
        longitudeDeg = longitudeGridDeg(longitudeIndex);
        text(ax,labelRadiusKm*sind(longitudeDeg), ...
            labelRadiusKm*cosd(longitudeDeg),longitudeLabelText(longitudeIndex), ...
            "Interpreter","tex","Color",style.textColor, ...
            "FontName",style.fontName,"FontSize",style.annotationFontSize, ...
            "FontWeight","bold","BackgroundColor",style.backgroundColor, ...
            "Margin",1.0,"HorizontalAlignment","center", ...
            "VerticalAlignment","middle");
    end
end
plotLimit = demPlot.outerRadiusKm + 60;
xlim(ax,[-plotLimit plotLimit]);
ylim(ax,[-plotLimit plotLimit]);
axis(ax,"equal");
axis(ax,"off");
end

function plotSensorNetwork( ...
    ax,sensorIndices,database,demPlot,sensorColor,style,markerArea)
[xKm,yKm] = candidatePolarCoordinates( ...
    sensorIndices,database,demPlot.moonRadiusKm);
scatter(ax,xKm,yKm,markerArea,"o", ...
    "MarkerFaceColor",sensorColor, ...
    "MarkerEdgeColor",style.backgroundColor,"LineWidth",1.0);
end

function [xKm,yKm] = candidatePolarCoordinates(sensorIndices,database,moonRadiusKm)
latitudeDeg = rad2deg(database.candidates.latitudesRad(sensorIndices));
longitudeDeg = rad2deg(database.candidates.longitudesRad(sensorIndices));
polarRadiusKm = moonRadiusKm .* deg2rad(90 + latitudeDeg);
xKm = polarRadiusKm .* sind(longitudeDeg);
yKm = polarRadiusKm .* cosd(longitudeDeg);
xKm = xKm(:);
yKm = yKm(:);
end

function [optimizationTable,diversityTable,bestNetworkTable] = ...
    buildOptimizationTables(studies,database,config)
numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
numberOfCases = numberOfNetworkSizes*numberOfObjectives;

objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
meanObjective = zeros(numberOfCases,1);
stdObjective = zeros(numberOfCases,1);
bestObjective = zeros(numberOfCases,1);
meanInformationScore = zeros(numberOfCases,1);
stdInformationScore = zeros(numberOfCases,1);
meanCoverageScore = zeros(numberOfCases,1);
stdCoverageScore = zeros(numberOfCases,1);
meanRuntimeSeconds = zeros(numberOfCases,1);
stdRuntimeSeconds = zeros(numberOfCases,1);

uniqueNetworks = zeros(numberOfCases,1);
uniqueSitesSelected = zeros(numberOfCases,1);
meanPairwiseSharedSensors = zeros(numberOfCases,1);
meanPairwiseOverlapFraction = zeros(numberOfCases,1);
meanPairwiseJaccard = zeros(numberOfCases,1);
stdPairwiseJaccard = zeros(numberOfCases,1);
maximumExactNetworkRepeats = zeros(numberOfCases,1);
maximumSiteSelectionCount = zeros(numberOfCases,1);

bestRun = zeros(numberOfCases,1);
bestSeed = zeros(numberOfCases,1);
bestInformationScore = zeros(numberOfCases,1);
bestCoverageScore = zeros(numberOfCases,1);
bestSensorIndices = strings(numberOfCases,1);
bestSensorLatitudesDeg = strings(numberOfCases,1);
bestSensorLongitudesDeg = strings(numberOfCases,1);

caseIndex = 0;
for objectiveIndex = 1:numberOfObjectives
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        objectiveMode = config.objectiveModes(objectiveIndex);
        networkSize = config.networkSizes(networkIndex);
        studyState = studies{networkIndex,objectiveIndex};

        infoScores = zeros(config.numberOfRuns,1);
        coverageScores = zeros(config.numberOfRuns,1);
        runtimes = zeros(config.numberOfRuns,1);
        networkMatrix = zeros(config.numberOfRuns,networkSize);
        selectionCounts = zeros(database.meta.numberOfCandidates,1);

        for runIndex = 1:config.numberOfRuns
            runState = studyState.runStates{runIndex};
            indices = double(runState.bestSensorIndices(:).');
            networkMatrix(runIndex,:) = indices;
            selectionCounts(indices) = selectionCounts(indices) + 1;
            infoScores(runIndex) = runState.bestInformationScore;
            coverageScores(runIndex) = runState.bestCoverageScore;
            runtimes(runIndex) = runState.runtimeSeconds;
        end

        [uniqueRows,~,uniqueGroups] = unique(networkMatrix,"rows"); %#ok<ASGLU>
        groupCounts = accumarray(uniqueGroups,1);
        [sharedSensors,overlapFraction,jaccard] = ...
            pairwiseNetworkSimilarity(networkMatrix);

        bestRunIndex = studyState.overallBestRunIndex;
        bestRunState = studyState.runStates{bestRunIndex};
        indices = double(bestRunState.bestSensorIndices(:));
        latDeg = rad2deg(database.candidates.latitudesRad(indices));
        lonDeg = rad2deg(database.candidates.longitudesRad(indices));

        objectiveColumn(caseIndex) = objectiveMode;
        networkSizeColumn(caseIndex) = networkSize;
        meanObjective(caseIndex) = mean(studyState.bestObjectives(:));
        stdObjective(caseIndex) = std(studyState.bestObjectives(:));
        bestObjective(caseIndex) = studyState.overallBestObjective;
        meanInformationScore(caseIndex) = mean(infoScores);
        stdInformationScore(caseIndex) = std(infoScores);
        meanCoverageScore(caseIndex) = mean(coverageScores);
        stdCoverageScore(caseIndex) = std(coverageScores);
        meanRuntimeSeconds(caseIndex) = mean(runtimes);
        stdRuntimeSeconds(caseIndex) = std(runtimes);

        uniqueNetworks(caseIndex) = size(uniqueRows,1);
        uniqueSitesSelected(caseIndex) = nnz(selectionCounts);
        meanPairwiseSharedSensors(caseIndex) = mean(sharedSensors);
        meanPairwiseOverlapFraction(caseIndex) = mean(overlapFraction);
        meanPairwiseJaccard(caseIndex) = mean(jaccard);
        stdPairwiseJaccard(caseIndex) = std(jaccard);
        maximumExactNetworkRepeats(caseIndex) = max(groupCounts);
        maximumSiteSelectionCount(caseIndex) = max(selectionCounts);

        bestRun(caseIndex) = bestRunIndex;
        bestSeed(caseIndex) = bestRunState.seed;
        bestInformationScore(caseIndex) = bestRunState.bestInformationScore;
        bestCoverageScore(caseIndex) = bestRunState.bestCoverageScore;
        bestSensorIndices(caseIndex) = string(mat2str(indices(:).'));
        bestSensorLatitudesDeg(caseIndex) = string(mat2str(latDeg(:).',6));
        bestSensorLongitudesDeg(caseIndex) = string(mat2str(lonDeg(:).',6));
    end
end

optimizationTable = table( ...
    objectiveColumn,networkSizeColumn,meanObjective,stdObjective,bestObjective, ...
    meanInformationScore,stdInformationScore,meanCoverageScore,stdCoverageScore, ...
    meanRuntimeSeconds,stdRuntimeSeconds, ...
    'VariableNames',{'Objective','NetworkSize','MeanObjective','StdObjective', ...
    'BestObjective','MeanInformationScore','StdInformationScore', ...
    'MeanCoverageScore','StdCoverageScore','MeanRuntimeSeconds','StdRuntimeSeconds'});

diversityTable = table( ...
    objectiveColumn,networkSizeColumn,uniqueNetworks,uniqueSitesSelected, ...
    meanPairwiseSharedSensors,meanPairwiseOverlapFraction, ...
    meanPairwiseJaccard,stdPairwiseJaccard,maximumExactNetworkRepeats, ...
    maximumSiteSelectionCount, ...
    'VariableNames',{'Objective','NetworkSize','UniqueNetworks','UniqueSitesSelected', ...
    'MeanPairwiseSharedSensors','MeanPairwiseOverlapFraction', ...
    'MeanPairwiseJaccard','StdPairwiseJaccard','MaximumExactNetworkRepeats', ...
    'MaximumSiteSelectionCount'});

bestNetworkTable = table( ...
    objectiveColumn,networkSizeColumn,bestRun,bestSeed,bestObjective, ...
    bestInformationScore,bestCoverageScore,bestSensorIndices, ...
    bestSensorLatitudesDeg,bestSensorLongitudesDeg, ...
    'VariableNames',{'Objective','NetworkSize','BestRun','Seed','BestObjective', ...
    'InformationScore','CoverageScore','SensorIndices', ...
    'SensorLatitudesDeg','SensorLongitudesDeg'});
end

function [sharedSensors,overlapFraction,jaccard] = pairwiseNetworkSimilarity(networkMatrix)
numberOfRuns = size(networkMatrix,1);
networkSize = size(networkMatrix,2);
numberOfPairs = numberOfRuns*(numberOfRuns-1)/2;
if numberOfPairs == 0
    sharedSensors = NaN;
    overlapFraction = NaN;
    jaccard = NaN;
    return
end
sharedSensors = zeros(numberOfPairs,1);
overlapFraction = zeros(numberOfPairs,1);
jaccard = zeros(numberOfPairs,1);
pairIndex = 0;
for firstRun = 1:numberOfRuns-1
    firstSet = networkMatrix(firstRun,:);
    for secondRun = firstRun+1:numberOfRuns
        pairIndex = pairIndex + 1;
        secondSet = networkMatrix(secondRun,:);
        intersectionCount = numel(intersect(firstSet,secondSet));
        unionCount = 2*networkSize-intersectionCount;
        sharedSensors(pairIndex) = intersectionCount;
        overlapFraction(pairIndex) = intersectionCount/networkSize;
        jaccard(pairIndex) = intersectionCount/unionCount;
    end
end
end

function [metricTable,perRsoFiles] = buildEstimationMetricTable( ...
    studies,database,demFile,config,cacheDirectory,tableDirectory)
numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
numberOfCases = numberOfNetworkSizes*numberOfObjectives;

objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
bestRunColumn = zeros(numberOfCases,1);
seedColumn = zeros(numberOfCases,1);
meanRmsPositionErrorKm = zeros(numberOfCases,1);
worstRmsPositionErrorKm = zeros(numberOfCases,1);
meanRmsVelocityErrorKmS = zeros(numberOfCases,1);
worstRmsVelocityErrorKmS = zeros(numberOfCases,1);
meanPositionThreeSigmaKm = zeros(numberOfCases,1);
meanVelocityThreeSigmaKmS = zeros(numberOfCases,1);
totalMeasurementUpdates = zeros(numberOfCases,1);
perRsoFiles = strings(numberOfCases,1);

caseIndex = 0;
for objectiveIndex = 1:numberOfObjectives
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        objectiveMode = config.objectiveModes(objectiveIndex);
        networkSize = config.networkSizes(networkIndex);
        studyState = studies{networkIndex,objectiveIndex};
        bestRunIndex = studyState.overallBestRunIndex;
        bestRunState = studyState.runStates{bestRunIndex};
        sensorIndices = double(studyState.overallBestSensorIndices(:));

        cacheFile = fullfile(cacheDirectory, ...
            sprintf("ekf_best_%s_n%d.mat",objectiveMode,networkSize));
        metricCache = struct();
        cacheAccepted = false;

        if config.reuseEstimationMetricCache && isfile(cacheFile)
            cachedData = load(cacheFile,"metricCache");
            if isfield(cachedData,"metricCache")
                candidateCache = cachedData.metricCache;
                cacheAccepted = isfield(candidateCache,"sensorIndices") && ...
                    isfield(candidateCache,"measurementNoiseSeed") && ...
                    isfield(candidateCache,"demFile") && ...
                    isequal(double(candidateCache.sensorIndices(:)),sensorIndices) && ...
                    candidateCache.measurementNoiseSeed == config.measurementNoiseSeed && ...
                    string(candidateCache.demFile) == string(demFile);
                if cacheAccepted
                    metricCache = candidateCache;
                end
            end
        end

        if ~cacheAccepted
            fprintf("\nRunning fixed-noise EKF validation: %s, N_s=%d ...\n", ...
                objectiveMode,networkSize);
            validationConfig = struct();
            validationConfig.measurementNoiseSeed = config.measurementNoiseSeed;
            validationConfig.demFile = demFile;
            validation = optimization.validateNetworkEkf( ...
                database,sensorIndices,validationConfig);

            metricCache = struct();
            metricCache.version = "production_best_network_ekf_metrics_v1";
            metricCache.sensorIndices = sensorIndices;
            metricCache.measurementNoiseSeed = config.measurementNoiseSeed;
            metricCache.demFile = string(demFile);
            metricCache.meanRmsPositionErrorKm = mean(validation.rmsPositionErrorKm);
            metricCache.worstRmsPositionErrorKm = max(validation.rmsPositionErrorKm);
            metricCache.meanRmsVelocityErrorKmS = mean(validation.rmsVelocityErrorKmS);
            metricCache.worstRmsVelocityErrorKmS = max(validation.rmsVelocityErrorKmS);
            metricCache.meanPositionThreeSigmaKm = ...
                mean(validation.positionThreeSigmaNormsKm,"all");
            metricCache.meanVelocityThreeSigmaKmS = ...
                mean(validation.velocityThreeSigmaNormsKmS,"all");
            metricCache.totalMeasurementUpdates = sum(validation.measurementUpdateCounts);
            metricCache.perRsoTable = validation.summaryTable;
            save(cacheFile,"metricCache");
        else
            fprintf("\nUsing cached fixed-noise EKF metrics: %s, N_s=%d\n", ...
                objectiveMode,networkSize);
        end

        objectiveColumn(caseIndex) = objectiveMode;
        networkSizeColumn(caseIndex) = networkSize;
        bestRunColumn(caseIndex) = bestRunIndex;
        seedColumn(caseIndex) = bestRunState.seed;
        meanRmsPositionErrorKm(caseIndex) = metricCache.meanRmsPositionErrorKm;
        worstRmsPositionErrorKm(caseIndex) = metricCache.worstRmsPositionErrorKm;
        meanRmsVelocityErrorKmS(caseIndex) = metricCache.meanRmsVelocityErrorKmS;
        worstRmsVelocityErrorKmS(caseIndex) = metricCache.worstRmsVelocityErrorKmS;
        meanPositionThreeSigmaKm(caseIndex) = metricCache.meanPositionThreeSigmaKm;
        meanVelocityThreeSigmaKmS(caseIndex) = metricCache.meanVelocityThreeSigmaKmS;
        totalMeasurementUpdates(caseIndex) = metricCache.totalMeasurementUpdates;

        if config.writePerRsoTables
            perRsoTable = metricCache.perRsoTable;
            perRsoTable = addvars(perRsoTable, ...
                repmat(objectiveMode,height(perRsoTable),1), ...
                repmat(networkSize,height(perRsoTable),1), ...
                'Before',1,'NewVariableNames',{'Objective','NetworkSize'});
            perRsoFile = fullfile(tableDirectory, ...
                sprintf("ekf_per_rso_%s_n%d.csv",objectiveMode,networkSize));
            writetable(perRsoTable,perRsoFile);
            perRsoFiles(caseIndex) = string(perRsoFile);
        end
    end
end

metricTable = table( ...
    objectiveColumn,networkSizeColumn,bestRunColumn,seedColumn, ...
    meanRmsPositionErrorKm,worstRmsPositionErrorKm, ...
    meanRmsVelocityErrorKmS,worstRmsVelocityErrorKmS, ...
    meanPositionThreeSigmaKm,meanVelocityThreeSigmaKmS,totalMeasurementUpdates, ...
    'VariableNames',{'Objective','NetworkSize','BestRun','Seed', ...
    'MeanRmsPositionErrorKm','WorstRmsPositionErrorKm', ...
    'MeanRmsVelocityErrorKmS','WorstRmsVelocityErrorKmS', ...
    'MeanPositionThreeSigmaKm','MeanVelocityThreeSigmaKmS', ...
    'TotalMeasurementUpdates'});
end

function applyAxesStyle(ax,style)
ax.Color = style.backgroundColor;
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.XColor = style.textColor;
ax.YColor = style.textColor;
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "on";
ax.YGrid = "on";
ax.GridColor = style.gridColor;
ax.GridAlpha = 0.55;
ax.Layer = "top";
ax.XLabel.FontName = style.fontName;
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontName = style.fontName;
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";
end

function applyLegendStyle(lgd,style)
lgd.FontName = style.fontName;
lgd.FontSize = style.legendFontSize;
lgd.FontWeight = "bold";
lgd.TextColor = style.textColor;
lgd.Color = style.backgroundColor;
lgd.EdgeColor = style.boxEdgeColor;
lgd.Box = "on";
end

function styleColorbar(cb,style)
cb.Label.String = "Elevation (km)";
cb.Label.FontName = style.fontName;
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";
cb.Color = style.textColor;
end

function exportVectorFigure(fig,outputFile,style)
exportgraphics(fig,outputFile, ...
    "ContentType","vector", ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
end

function exportRasterFigure(fig,outputFile,style,resolution)
exportgraphics(fig,outputFile, ...
    "ContentType","image","Resolution",resolution, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
end

function printFigureFiles(groupStruct,groupName)
fprintf("%s:\n",groupName);
fields = fieldnames(groupStruct);
for fieldIndex = 1:numel(fields)
    entry = groupStruct.(fields{fieldIndex});
    fprintf("  %s\n",entry.outputFile);
end
end

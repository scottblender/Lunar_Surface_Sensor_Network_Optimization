function heatmapInfo = plotPerRsoEkfHeatmaps(userConfig)
% PLOTPERRSOEKFHEATMAPS Plot design-population EKF performance.
%
% A single paper-ready figure contains four panels:
%   top row:    per-RSO RMS position error for information/coverage networks;
%   bottom row: per-RSO epoch observability for information/coverage networks.
%
% Epoch observability is the percentage of tracking epochs for which at least
% one selected sensor has an accepted measurement after terrain and celestial
% screening. Because observability depends only on the frozen visibility
% database and selected network, it is computed directly without rerunning the
% EKF. This keeps the results pipeline fast and makes the definition identical
% to the operational-spacecraft validation.

arguments
    userConfig (1,1) struct = struct()
end

%% Paths and configuration
scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
resultsDirectory = fullfile(projectRoot,"results");
addpath(sourceDirectory);
addpath(scriptDirectory);
rehash path;

style = publicationPlotStyle();

config = struct();
config.resultsDirectory = resultsDirectory;
config.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config.networkSizes = [3 5 7 10];
config.objectiveModes = ["information","coverage"];
config.numberOfRuns = 20;
config.functionEvaluationBudget = 12000;
config.exportResolution = 600;
config.closeExistingFigures = false;
config = mergeStruct(config,userConfig);

config.resultsDirectory = string(config.resultsDirectory);
config.databaseFile = string(config.databaseFile);
config.outputDirectory = string(config.outputDirectory);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

assert(all(ismember(config.objectiveModes,["information","coverage"])), ...
    "objectiveModes may contain only information and coverage.");
if config.closeExistingFigures, close all; end

assert(isfile(config.databaseFile), ...
    "Production optimization database was not found: %s",config.databaseFile);
databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Production optimization MAT file does not contain database.");
database = databaseData.database;
numberOfEpochs = numel(database.tracking.times);
numberOfObjects = database.meta.numberOfObjects;
assert(numberOfEpochs > 0,"Production database contains no tracking epochs.");

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end
tableDirectory = fullfile(config.outputDirectory,"tables");
cacheDirectory = fullfile(config.outputDirectory,"ekf_metric_cache");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end
if ~isfolder(cacheDirectory), mkdir(cacheDirectory); end

%% Load per-RSO EKF results and add epoch observability
numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
rmsPositionErrorKm = nan(numberOfObjects,numberOfNetworkSizes,numberOfObjectives);
measurementUpdates = nan(size(rmsPositionErrorKm));
observableEpochPercent = nan(size(rmsPositionErrorKm));
sourceFiles = strings(numberOfNetworkSizes,numberOfObjectives);

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);
    for networkIndex = 1:numberOfNetworkSizes
        networkSize = config.networkSizes(networkIndex);
        cacheFile = fullfile(cacheDirectory, ...
            sprintf("ekf_best_%s_n%d.mat",objectiveMode,networkSize));
        csvFile = fullfile(tableDirectory, ...
            sprintf("ekf_per_rso_%s_n%d.csv",objectiveMode,networkSize));

        [perRsoTable,sourceFile] = loadAndAugmentPerRso( ...
            cacheFile,csvFile,database,config,objectiveMode,networkSize);
        perRsoTable = sortrows(perRsoTable,"ObjectIndex");

        required = ["ObjectIndex","MeasurementUpdates", ...
            "RmsPositionErrorKm","ObservableEpochPercent"];
        assert(all(ismember(required,string(perRsoTable.Properties.VariableNames))), ...
            "Per-RSO table is missing required variables: %s",sourceFile);
        assert(height(perRsoTable) == numberOfObjects, ...
            "Per-RSO table has %d objects; expected %d: %s", ...
            height(perRsoTable),numberOfObjects,sourceFile);

        rmsPositionErrorKm(:,networkIndex,objectiveIndex) = ...
            double(perRsoTable.RmsPositionErrorKm(:));
        measurementUpdates(:,networkIndex,objectiveIndex) = ...
            double(perRsoTable.MeasurementUpdates(:));
        observableEpochPercent(:,networkIndex,objectiveIndex) = ...
            double(perRsoTable.ObservableEpochPercent(:));
        sourceFiles(networkIndex,objectiveIndex) = sourceFile;
    end
end

assert(all(observableEpochPercent >= -1e-12 & ...
    observableEpochPercent <= 100+1e-12,"all"), ...
    "Computed epoch observability lies outside [0,100] percent.");

%% Compact diagnostic summary used by the paper-table builder
numberOfCases = numberOfNetworkSizes*numberOfObjectives;
objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
medianRmsPositionErrorKm = zeros(numberOfCases,1);
worstRsoIndex = zeros(numberOfCases,1);
worstRmsPositionErrorKm = zeros(numberOfCases,1);
meanObservableEpochPercent = zeros(numberOfCases,1);
medianObservableEpochPercent = zeros(numberOfCases,1);
minimumObservabilityRsoIndex = zeros(numberOfCases,1);
minimumObservableEpochPercent = zeros(numberOfCases,1);

caseIndex = 0;
for objectiveIndex = 1:numberOfObjectives
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        positionValues = rmsPositionErrorKm(:,networkIndex,objectiveIndex);
        observabilityValues = observableEpochPercent(:,networkIndex,objectiveIndex);
        [worstValue,worstIndex] = max(positionValues);
        [minimumObservable,minimumIndex] = min(observabilityValues);

        objectiveColumn(caseIndex) = config.objectiveModes(objectiveIndex);
        networkSizeColumn(caseIndex) = config.networkSizes(networkIndex);
        medianRmsPositionErrorKm(caseIndex) = median(positionValues);
        worstRsoIndex(caseIndex) = worstIndex;
        worstRmsPositionErrorKm(caseIndex) = worstValue;
        meanObservableEpochPercent(caseIndex) = mean(observabilityValues);
        medianObservableEpochPercent(caseIndex) = median(observabilityValues);
        minimumObservabilityRsoIndex(caseIndex) = minimumIndex;
        minimumObservableEpochPercent(caseIndex) = minimumObservable;
    end
end

summaryTable = table( ...
    objectiveColumn,networkSizeColumn,medianRmsPositionErrorKm, ...
    worstRsoIndex,worstRmsPositionErrorKm,meanObservableEpochPercent, ...
    medianObservableEpochPercent,minimumObservabilityRsoIndex, ...
    minimumObservableEpochPercent, ...
    'VariableNames',{ ...
    'Objective','NetworkSize','MedianRmsPositionErrorKm', ...
    'WorstRsoIndex','WorstRmsPositionErrorKm','MeanObservableEpochPercent', ...
    'MedianObservableEpochPercent','MinimumObservabilityRsoIndex', ...
    'MinimumObservableEpochPercent'});
summaryFile = fullfile(tableDirectory,"ekf_per_rso_diagnostic_summary.csv");
writetable(summaryTable,summaryFile);

%% Single combined paper figure
positiveErrors = rmsPositionErrorKm(isfinite(rmsPositionErrorKm) & rmsPositionErrorKm > 0);
assert(~isempty(positiveErrors),"No positive RMS position errors were available.");
logMinimum = floor(log10(min(positiveErrors)));
logMaximum = ceil(log10(max(positiveErrors)));
if logMaximum <= logMinimum, logMaximum = logMinimum + 1; end

fig = figure("Name","Design RSO tracking performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 style.heatmapWidthInches style.heatmapHeightInches], ...
    "Renderer","opengl");
fig.InvertHardcopy = "off";

axisPositions = [ ...
    0.08 0.57 0.34 0.32; ...
    0.49 0.57 0.34 0.32; ...
    0.08 0.12 0.34 0.32; ...
    0.49 0.12 0.34 0.32];
axesHandles = gobjects(2,numberOfObjectives);

for objectiveIndex = 1:numberOfObjectives
    ax = axes(fig,"Position",axisPositions(objectiveIndex,:));
    axesHandles(1,objectiveIndex) = ax;
    logValues = log10(max(rmsPositionErrorKm(:,:,objectiveIndex),10^logMinimum));
    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects,logValues);
    colormap(ax,turbo(256));
    clim(ax,[logMinimum logMaximum]);
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)) + " — RMS error", ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    if objectiveIndex == 1, ylabel(ax,"RSO index"); end
    xlabel(ax,"Number of sensors, N_s");

    ax = axes(fig,"Position",axisPositions(2+objectiveIndex,:));
    axesHandles(2,objectiveIndex) = ax;
    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects, ...
        observableEpochPercent(:,:,objectiveIndex));
    colormap(ax,turbo(256));
    clim(ax,[0 100]);
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)) + " — observability", ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    if objectiveIndex == 1, ylabel(ax,"RSO index"); end
    xlabel(ax,"Number of sensors, N_s");
end

annotation(fig,"textbox",[0.18 0.94 0.58 0.045], ...
    "String","Design-population tracking performance", ...
    "HorizontalAlignment","center","VerticalAlignment","middle", ...
    "EdgeColor","none","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold", ...
    "Color",style.textColor);

rmsColorbar = colorbar(axesHandles(1,end),"eastoutside");
rmsColorbar.Position = [0.86 0.57 0.022 0.32];
rmsColorbar.Label.String = "RMS position error (km)";
rmsTicks = chooseIntegerTicks(logMinimum,logMaximum,6);
rmsColorbar.Ticks = rmsTicks;
rmsColorbar.TickLabels = compose("%.3g",10.^rmsTicks);
styleColorbar(rmsColorbar,style);

obsColorbar = colorbar(axesHandles(2,end),"eastoutside");
obsColorbar.Position = [0.86 0.12 0.022 0.32];
obsColorbar.Label.String = "Observable epochs (%)";
obsColorbar.Ticks = 0:20:100;
styleColorbar(obsColorbar,style);

for objectiveIndex = 1:numberOfObjectives
    axesHandles(1,objectiveIndex).Position = axisPositions(objectiveIndex,:);
    axesHandles(2,objectiveIndex).Position = axisPositions(2+objectiveIndex,:);
end

drawnow;
outputFile = fullfile(config.outputDirectory,"design_rso_tracking_heatmaps.eps");
exportgraphics(fig,outputFile,"ContentType","image", ...
    "Resolution",config.exportResolution, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");

staleFiles = [ ...
    fullfile(config.outputDirectory,"ekf_per_rso_position_rmse_heatmap.eps"); ...
    fullfile(config.outputDirectory,"ekf_per_rso_observability_heatmap.eps"); ...
    fullfile(config.outputDirectory,"supplemental", ...
        "ekf_per_rso_measurement_availability_heatmap.eps")];
for fileIndex = 1:numel(staleFiles)
    if isfile(staleFiles(fileIndex)), delete(staleFiles(fileIndex)); end
end

%% Return products
heatmapInfo = struct();
heatmapInfo.version = "per_rso_tracking_heatmaps_v4_epoch_observability";
heatmapInfo.created = string(datetime("now"));
heatmapInfo.configuration = config;
heatmapInfo.numberOfEpochs = numberOfEpochs;
heatmapInfo.sourceFiles = sourceFiles;
heatmapInfo.rmsPositionErrorKm = rmsPositionErrorKm;
heatmapInfo.measurementUpdates = measurementUpdates;
heatmapInfo.observableEpochPercent = observableEpochPercent;
heatmapInfo.summaryTable = summaryTable;
heatmapInfo.summaryFile = string(summaryFile);
heatmapInfo.figure = fig;
heatmapInfo.outputFile = string(outputFile);

fprintf("\nDesign-RSO tracking figure:\n  %s\n",outputFile);
fprintf("Design-RSO diagnostic summary:\n  %s\n",summaryFile);

end

%% ------------------------------------------------------------------------
function [perRsoTable,sourceFile] = loadAndAugmentPerRso( ...
    cacheFile,csvFile,database,config,objectiveMode,networkSize)
metricCache = struct();
haveCache = false;

if isfile(cacheFile)
    data = load(cacheFile,"metricCache");
    if isfield(data,"metricCache")
        metricCache = data.metricCache;
        haveCache = true;
    end
end

if haveCache && isfield(metricCache,"perRsoTable") && ...
        istable(metricCache.perRsoTable)
    perRsoTable = metricCache.perRsoTable;
    sourceFile = string(cacheFile);
elseif isfile(csvFile)
    perRsoTable = readtable(csvFile);
    sourceFile = string(csvFile);
else
    error("plotPerRsoEkfHeatmaps:MissingResults", ...
        ["No per-RSO EKF result was found for %s, N_s=%d. Run " ...
         "plotProductionOptimizationResults first."],objectiveMode,networkSize);
end

if ~ismember("ObservableEpochPercent", ...
        string(perRsoTable.Properties.VariableNames))
    if haveCache && isfield(metricCache,"sensorIndices")
        sensorIndices = double(metricCache.sensorIndices(:));
    else
        sensorIndices = resolveBestSensorIndices( ...
            config.resultsDirectory,networkSize,objectiveMode, ...
            config.functionEvaluationBudget,config.numberOfRuns);
    end
    observable = computeEpochObservability(database,sensorIndices);
    perRsoTable = addvars(perRsoTable,observable, ...
        'After','MeasurementUpdates','NewVariableNames','ObservableEpochPercent');

    if haveCache
        metricCache.version = "production_best_network_ekf_metrics_v2_observability";
        metricCache.observableEpochPercent = observable;
        metricCache.perRsoTable = perRsoTable;
        save(cacheFile,"metricCache");
    end
end

writetable(perRsoTable,csvFile);
end

function observable = computeEpochObservability(database,sensorIndices)
if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)
    availability = optimization.loadChunkedCandidateData( ...
        database,double(sensorIndices(:)),"filteredAvailability");
else
    availability = database.visibility.filteredAvailability(sensorIndices,:,:);
end
epochObservable = squeeze(any(availability,1));
numberOfObjects = database.meta.numberOfObjects;
numberOfEpochs = numel(database.tracking.times);
if numberOfObjects == 1
    epochObservable = epochObservable(:);
end
observable = 100*sum(epochObservable,1).'/numberOfEpochs;
end

function sensorIndices = resolveBestSensorIndices( ...
    resultsDirectory,networkSize,objectiveMode,requiredFe,numberOfRuns)
files = dir(fullfile(resultsDirectory,"optimization_runs","**","study_summary.mat"));
bestDate = -Inf;
sensorIndices = [];
for fileIndex = 1:numel(files)
    filePath = fullfile(files(fileIndex).folder,files(fileIndex).name);
    try
        data = load(filePath,"studyState");
        if ~isfield(data,"studyState"), continue, end
        state = data.studyState;
        if state.config.networkSize ~= networkSize || ...
                lower(string(state.config.objectiveMode)) ~= objectiveMode || ...
                state.config.functionEvaluationBudget ~= requiredFe || ...
                state.numberOfRuns ~= numberOfRuns
            continue
        end
        if files(fileIndex).datenum > bestDate
            sensorIndices = double(state.overallBestSensorIndices(:));
            bestDate = files(fileIndex).datenum;
        end
    catch
    end
end
assert(~isempty(sensorIndices), ...
    "No matching optimized network was found for %s, N_s=%d.", ...
    objectiveMode,networkSize);
end

function styleHeatmapAxes(ax,style,networkSizes,numberOfObjects,showYLabels)
ax.YDir = "reverse";
ax.Color = style.backgroundColor;
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.XColor = style.textColor;
ax.YColor = style.textColor;
ax.LineWidth = 0.9;
ax.Box = "on";
ax.TickDir = "out";
ax.Layer = "top";
ax.XTick = 1:numel(networkSizes);
ax.XTickLabel = string(networkSizes);

if numberOfObjects <= 12
    yTicks = 1:numberOfObjects;
else
    yTicks = unique(round(linspace(1,numberOfObjects,10)));
end
ax.YTick = yTicks;
if showYLabels
    ax.YTickLabel = string(yTicks);
else
    ax.YTickLabel = strings(numel(yTicks),1);
end

ax.XLabel.FontName = style.fontName;
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontName = style.fontName;
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";
end

function titleText = objectiveTitle(objectiveMode)
if objectiveMode == "information"
    titleText = "Information";
else
    titleText = "Coverage";
end
end

function ticks = chooseIntegerTicks(minimumValue,maximumValue,maximumTicks)
allTicks = minimumValue:maximumValue;
if numel(allTicks) <= maximumTicks
    ticks = allTicks;
else
    indices = unique(round(linspace(1,numel(allTicks),maximumTicks)));
    ticks = allTicks(indices);
end
end

function styleColorbar(cb,style)
cb.Label.FontName = style.fontName;
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";
cb.Color = style.textColor;
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    fieldName = fields{fieldIndex};
    overrideValue = override.(fieldName);
    if isfield(output,fieldName) && isstruct(output.(fieldName)) && ...
            isscalar(output.(fieldName)) && isstruct(overrideValue) && ...
            isscalar(overrideValue)
        output.(fieldName) = mergeStruct(output.(fieldName),overrideValue);
    else
        output.(fieldName) = overrideValue;
    end
end
end

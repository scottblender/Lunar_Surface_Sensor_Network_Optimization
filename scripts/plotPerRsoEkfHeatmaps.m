function heatmapInfo = plotPerRsoEkfHeatmaps(userConfig)
% PLOTPERRSOEKFHEATMAPS Plot per-RSO EKF performance for best networks.
%
% Main-paper output:
%   1) Per-RSO RMS position error versus N_s for information and coverage.
%      A logarithmic color mapping is used so isolated EKF-divergence cases
%      do not hide the behavior of the remaining RSOs.
%
% Supplemental output:
%   2) Per-RSO accepted-measurement availability versus N_s. Availability is
%      normalized by N_s times the number of tracking epochs so network sizes
%      can be compared directly.
%
% The function also writes a compact diagnostic CSV used by the conference
% summary-table generator. The paper-ready tables themselves are produced by
% buildConferenceSummaryTables.
%
% Usage:
%   heatmapInfo = plotPerRsoEkfHeatmaps;
%
% The EKF metric cache is preferred. If it is unavailable, the function falls
% back to the per-RSO CSV tables written by plotProductionOptimizationResults.

arguments
    userConfig (1,1) struct = struct()
end

%% Project paths and configuration

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");

addpath(scriptDirectory);
rehash path;

style = publicationPlotStyle();

defaultConfig = struct();
defaultConfig.resultsDirectory = resultsDirectory;
defaultConfig.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
defaultConfig.outputDirectory = fullfile(resultsDirectory,"production_figures");
defaultConfig.networkSizes = [3 5 7 10];
defaultConfig.objectiveModes = ["information","coverage"];
defaultConfig.exportResolution = 600;
defaultConfig.closeExistingFigures = false;

config = mergeStruct(defaultConfig,userConfig);
config.resultsDirectory = string(config.resultsDirectory);
config.databaseFile = string(config.databaseFile);
config.outputDirectory = string(config.outputDirectory);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

validateattributes(config.networkSizes,{'numeric'}, ...
    {'vector','integer','positive','nonempty'});
validateattributes(config.exportResolution,{'numeric'}, ...
    {'scalar','integer','positive'});
assert(islogical(config.closeExistingFigures) && isscalar(config.closeExistingFigures), ...
    "closeExistingFigures must be a scalar logical.");
assert(all(ismember(config.objectiveModes,["information","coverage"])), ...
    "objectiveModes may contain only information and coverage.");

if config.closeExistingFigures
    close all;
end

assert(isfile(config.databaseFile), ...
    "Production optimization database was not found: %s",config.databaseFile);
databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Production optimization MAT file does not contain database.");
database = databaseData.database;

numberOfEpochs = numel(database.tracking.times);
assert(numberOfEpochs > 0, ...
    "Production database contains no optimization tracking epochs.");

if ~isfolder(config.outputDirectory)
    mkdir(config.outputDirectory);
end

tableDirectory = fullfile(config.outputDirectory,"tables");
cacheDirectory = fullfile(config.outputDirectory,"ekf_metric_cache");
supplementalDirectory = fullfile(config.outputDirectory,"supplemental");

if ~isfolder(tableDirectory)
    mkdir(tableDirectory);
end
if ~isfolder(supplementalDirectory)
    mkdir(supplementalDirectory);
end

%% Load per-RSO validation results

numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
numberOfObjects = database.meta.numberOfObjects;

rmsPositionErrorKm = nan(numberOfObjects,numberOfNetworkSizes,numberOfObjectives);
measurementUpdates = nan(numberOfObjects,numberOfNetworkSizes,numberOfObjectives);
measurementAvailabilityPercent = nan(size(measurementUpdates));
sourceFiles = strings(numberOfNetworkSizes,numberOfObjectives);

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = config.objectiveModes(objectiveIndex);

    for networkIndex = 1:numberOfNetworkSizes
        networkSize = config.networkSizes(networkIndex);
        cacheFile = fullfile(cacheDirectory, ...
            sprintf("ekf_best_%s_n%d.mat",objectiveMode,networkSize));
        csvFile = fullfile(tableDirectory, ...
            sprintf("ekf_per_rso_%s_n%d.csv",objectiveMode,networkSize));

        [perRsoTable,sourceFile] = loadPerRsoTable(cacheFile,csvFile);
        perRsoTable = sortrows(perRsoTable,"ObjectIndex");

        requiredVariables = [ ...
            "ObjectIndex", ...
            "MeasurementUpdates", ...
            "RmsPositionErrorKm"];
        assert(all(ismember(requiredVariables, ...
            string(perRsoTable.Properties.VariableNames))), ...
            "Per-RSO table is missing required variables: %s",sourceFile);
        assert(height(perRsoTable) == numberOfObjects, ...
            "Per-RSO table has %d objects; expected %d: %s", ...
            height(perRsoTable),numberOfObjects,sourceFile);
        assert(isequal(double(perRsoTable.ObjectIndex(:)),(1:numberOfObjects).'), ...
            "Per-RSO object indices are incomplete or out of order: %s",sourceFile);

        positionValues = double(perRsoTable.RmsPositionErrorKm(:));
        updateValues = double(perRsoTable.MeasurementUpdates(:));

        assert(all(isfinite(positionValues)) && all(positionValues >= 0), ...
            "Per-RSO RMS position errors are invalid: %s",sourceFile);
        assert(all(isfinite(updateValues)) && all(updateValues >= 0), ...
            "Per-RSO measurement-update counts are invalid: %s",sourceFile);

        rmsPositionErrorKm(:,networkIndex,objectiveIndex) = positionValues;
        measurementUpdates(:,networkIndex,objectiveIndex) = updateValues;
        measurementAvailabilityPercent(:,networkIndex,objectiveIndex) = ...
            100*updateValues/(networkSize*numberOfEpochs);
        sourceFiles(networkIndex,objectiveIndex) = sourceFile;
    end
end

assert(all(measurementAvailabilityPercent >= -1e-12 & ...
    measurementAvailabilityPercent <= 100+1e-12,"all"), ...
    "Computed measurement availability lies outside [0,100] percent.");

%% Compact per-case diagnostic summary

numberOfCases = numberOfNetworkSizes*numberOfObjectives;
objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
medianRmsPositionErrorKm = zeros(numberOfCases,1);
worstRsoIndex = zeros(numberOfCases,1);
worstRmsPositionErrorKm = zeros(numberOfCases,1);
medianMeasurementAvailabilityPercent = zeros(numberOfCases,1);
minimumAvailabilityRsoIndex = zeros(numberOfCases,1);
minimumMeasurementAvailabilityPercent = zeros(numberOfCases,1);

caseIndex = 0;
for objectiveIndex = 1:numberOfObjectives
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        positionValues = rmsPositionErrorKm(:,networkIndex,objectiveIndex);
        availabilityValues = measurementAvailabilityPercent(:,networkIndex,objectiveIndex);

        [worstValue,worstIndex] = max(positionValues);
        [minimumAvailability,minimumIndex] = min(availabilityValues);

        objectiveColumn(caseIndex) = config.objectiveModes(objectiveIndex);
        networkSizeColumn(caseIndex) = config.networkSizes(networkIndex);
        medianRmsPositionErrorKm(caseIndex) = median(positionValues);
        worstRsoIndex(caseIndex) = worstIndex;
        worstRmsPositionErrorKm(caseIndex) = worstValue;
        medianMeasurementAvailabilityPercent(caseIndex) = median(availabilityValues);
        minimumAvailabilityRsoIndex(caseIndex) = minimumIndex;
        minimumMeasurementAvailabilityPercent(caseIndex) = minimumAvailability;
    end
end

summaryTable = table( ...
    objectiveColumn,networkSizeColumn,medianRmsPositionErrorKm, ...
    worstRsoIndex,worstRmsPositionErrorKm, ...
    medianMeasurementAvailabilityPercent,minimumAvailabilityRsoIndex, ...
    minimumMeasurementAvailabilityPercent, ...
    'VariableNames',{ ...
    'Objective','NetworkSize','MedianRmsPositionErrorKm', ...
    'WorstRsoIndex','WorstRmsPositionErrorKm', ...
    'MedianMeasurementAvailabilityPercent','MinimumAvailabilityRsoIndex', ...
    'MinimumMeasurementAvailabilityPercent'});

summaryFile = fullfile(tableDirectory,"ekf_per_rso_diagnostic_summary.csv");
writetable(summaryTable,summaryFile);

%% Main-paper figure: RMS position-error heatmap

positiveErrors = rmsPositionErrorKm(isfinite(rmsPositionErrorKm) & rmsPositionErrorKm > 0);
assert(~isempty(positiveErrors),"No positive RMS position errors were available.");
logMinimum = floor(log10(min(positiveErrors)));
logMaximum = ceil(log10(max(positiveErrors)));
if logMaximum <= logMinimum
    logMaximum = logMinimum + 1;
end

positionFigure = figure( ...
    "Name","Per-RSO RMS Position Error", ...
    "Color",style.backgroundColor, ...
    "Units","inches", ...
    "Position",[0.6 0.6 7.00 5.15], ...
    "Renderer","opengl");
positionFigure.InvertHardcopy = "off";
positionLayout = tiledlayout(positionFigure,1,numberOfObjectives, ...
    "TileSpacing","compact","Padding","compact");

positionAxes = gobjects(numberOfObjectives,1);
for objectiveIndex = 1:numberOfObjectives
    ax = nexttile(positionLayout,objectiveIndex);
    positionAxes(objectiveIndex) = ax;

    logValues = log10(max( ...
        rmsPositionErrorKm(:,:,objectiveIndex),10^logMinimum));
    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects,logValues);
    colormap(ax,turbo(256));
    clim(ax,[logMinimum logMaximum]);
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex == 1);

    title(ax,objectiveShortTitle(config.objectiveModes(objectiveIndex)), ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold","Color",style.textColor);
    xlabel(ax,"Number of sensors, N_s");
    if objectiveIndex == 1
        ylabel(ax,"RSO index");
    end
end

sgtitle(positionLayout,"Per-RSO RMS position error", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold","Color",style.textColor);

positionColorbar = colorbar(positionAxes(end));
positionColorbar.Layout.Tile = "east";
positionColorbar.Label.String = "RMS position error (km)";
positionTicks = chooseIntegerTicks(logMinimum,logMaximum,7);
positionColorbar.Ticks = positionTicks;
positionColorbar.TickLabels = compose("%.3g",10.^positionTicks);
styleColorbar(positionColorbar,style);

positionOutputFile = fullfile(config.outputDirectory, ...
    "ekf_per_rso_position_rmse_heatmap.eps");
exportRasterFigure(positionFigure,positionOutputFile,style,config.exportResolution);

%% Supplemental figure: normalized measurement availability

availabilityFigure = figure( ...
    "Name","Per-RSO Measurement Availability", ...
    "Color",style.backgroundColor, ...
    "Units","inches", ...
    "Position",[0.6 0.6 7.00 5.15], ...
    "Renderer","opengl");
availabilityFigure.InvertHardcopy = "off";
availabilityLayout = tiledlayout(availabilityFigure,1,numberOfObjectives, ...
    "TileSpacing","compact","Padding","compact");

availabilityAxes = gobjects(numberOfObjectives,1);
for objectiveIndex = 1:numberOfObjectives
    ax = nexttile(availabilityLayout,objectiveIndex);
    availabilityAxes(objectiveIndex) = ax;

    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects, ...
        measurementAvailabilityPercent(:,:,objectiveIndex));
    colormap(ax,turbo(256));
    clim(ax,[0 100]);
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex == 1);

    title(ax,objectiveShortTitle(config.objectiveModes(objectiveIndex)), ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold","Color",style.textColor);
    xlabel(ax,"Number of sensors, N_s");
    if objectiveIndex == 1
        ylabel(ax,"RSO index");
    end
end

sgtitle(availabilityLayout,"Accepted measurement availability", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold","Color",style.textColor);

availabilityColorbar = colorbar(availabilityAxes(end));
availabilityColorbar.Layout.Tile = "east";
availabilityColorbar.Label.String = "Accepted measurements (%)";
availabilityColorbar.Ticks = 0:20:100;
styleColorbar(availabilityColorbar,style);

availabilityOutputFile = fullfile(supplementalDirectory, ...
    "ekf_per_rso_measurement_availability_heatmap.eps");
exportRasterFigure(availabilityFigure,availabilityOutputFile,style,config.exportResolution);

%% Return products

heatmapInfo = struct();
heatmapInfo.version = "per_rso_ekf_heatmaps_v2";
heatmapInfo.created = string(datetime("now"));
heatmapInfo.configuration = config;
heatmapInfo.numberOfEpochs = numberOfEpochs;
heatmapInfo.sourceFiles = sourceFiles;
heatmapInfo.rmsPositionErrorKm = rmsPositionErrorKm;
heatmapInfo.measurementUpdates = measurementUpdates;
heatmapInfo.measurementAvailabilityPercent = measurementAvailabilityPercent;
heatmapInfo.summaryTable = summaryTable;
heatmapInfo.summaryFile = string(summaryFile);
heatmapInfo.positionRmseFigure = positionFigure;
heatmapInfo.positionRmseOutputFile = string(positionOutputFile);
heatmapInfo.measurementAvailabilityFigure = availabilityFigure;
heatmapInfo.measurementAvailabilityOutputFile = string(availabilityOutputFile);
heatmapInfo.measurementAvailabilityIsSupplemental = true;

fprintf("\nPer-RSO EKF figures:\n");
fprintf("  Main:         %s\n",positionOutputFile);
fprintf("  Supplemental: %s\n",availabilityOutputFile);
fprintf("  Diagnostics:  %s\n",summaryFile);

end

%% Local helpers

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

function [perRsoTable,sourceFile] = loadPerRsoTable(cacheFile,csvFile)
if isfile(cacheFile)
    cachedData = load(cacheFile,"metricCache");
    if isfield(cachedData,"metricCache") && ...
            isfield(cachedData.metricCache,"perRsoTable") && ...
            istable(cachedData.metricCache.perRsoTable)
        perRsoTable = cachedData.metricCache.perRsoTable;
        sourceFile = string(cacheFile);
        return
    end
end

if isfile(csvFile)
    perRsoTable = readtable(csvFile);
    sourceFile = string(csvFile);
    return
end

error("plotPerRsoEkfHeatmaps:MissingResults", ...
    ["No per-RSO EKF result was found. Run " ...
     "plotProductionOptimizationResults first. Expected either:\n  %s\n  %s"], ...
    cacheFile,csvFile);
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
ax.YTick = 1:numberOfObjects;
if showYLabels
    ax.YTickLabel = string(1:numberOfObjects);
else
    ax.YTickLabel = strings(numberOfObjects,1);
end
ax.XLabel.FontName = style.fontName;
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontName = style.fontName;
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";
end

function titleText = objectiveShortTitle(objectiveMode)
switch lower(string(objectiveMode))
    case "information"
        titleText = "Information";
    case "coverage"
        titleText = "Coverage";
    otherwise
        titleText = string(objectiveMode);
end
end

function ticks = chooseIntegerTicks(minimumValue,maximumValue,maximumTicks)
allTicks = minimumValue:maximumValue;
if numel(allTicks) <= maximumTicks
    ticks = allTicks;
    return
end
indices = unique(round(linspace(1,numel(allTicks),maximumTicks)));
ticks = allTicks(indices);
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

function exportRasterFigure(fig,outputFile,style,resolution)
exportgraphics(fig,outputFile, ...
    "ContentType","image", ...
    "Resolution",resolution, ...
    "BackgroundColor",style.backgroundColor, ...
    "Colorspace","rgb");
end
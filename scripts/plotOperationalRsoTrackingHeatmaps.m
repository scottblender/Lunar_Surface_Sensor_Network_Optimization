function plotInfo = plotOperationalRsoTrackingHeatmaps(operationalResults,userConfig)
% PLOTOPERATIONALRSOTRACKINGHEATMAPS Create one combined operational-RSO figure.
%
% The figure contains RMS position error and epoch observability for the
% information- and coverage-optimized networks. Epoch observability is the
% percentage of tracking epochs during which at least one selected sensor has
% an accepted measurement.

arguments
    operationalResults (1,1) struct
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");
addpath(scriptDirectory);

style = publicationPlotStyle();
config = struct();
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config.networkSizes = [3 5 7 10];
config.objectiveModes = ["information","coverage"];
config.exportResolution = 600;
config = mergeStruct(config,userConfig);
config.outputDirectory = string(config.outputDirectory);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

assert(isfield(operationalResults,"rmsPositionErrorKm") && ...
    isfield(operationalResults,"observabilityPercent") && ...
    isfield(operationalResults,"spacecraftNames"), ...
    "Operational results do not contain the required tracking metrics.");

rmsPositionErrorKm = operationalResults.rmsPositionErrorKm;
observableEpochPercent = operationalResults.observabilityPercent;
spacecraftNames = string(operationalResults.spacecraftNames(:));
numberOfObjectives = numel(config.objectiveModes);
numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjects = numel(spacecraftNames);

assert(size(rmsPositionErrorKm,1) == numberOfObjects && ...
    size(rmsPositionErrorKm,2) == numberOfNetworkSizes && ...
    size(rmsPositionErrorKm,3) == numberOfObjectives, ...
    "Operational RMS array has unexpected dimensions.");
assert(isequal(size(observableEpochPercent),size(rmsPositionErrorKm)), ...
    "Operational observability array has unexpected dimensions.");

positiveErrors = rmsPositionErrorKm(isfinite(rmsPositionErrorKm) & rmsPositionErrorKm > 0);
assert(~isempty(positiveErrors),"No positive operational RMS errors are available.");
logMinimum = floor(log10(min(positiveErrors)));
logMaximum = ceil(log10(max(positiveErrors)));
if logMaximum <= logMinimum, logMaximum = logMinimum + 1; end

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end

fig = figure("Name","Operational RSO tracking performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 style.heatmapWidthInches style.heatmapHeightInches], ...
    "Renderer","opengl");
fig.InvertHardcopy = "off";

axisPositions = [ ...
    0.12 0.57 0.30 0.32; ...
    0.50 0.57 0.30 0.32; ...
    0.12 0.12 0.30 0.32; ...
    0.50 0.12 0.30 0.32];
axesHandles = gobjects(2,numberOfObjectives);

for objectiveIndex = 1:numberOfObjectives
    ax = axes(fig,"Position",axisPositions(objectiveIndex,:));
    axesHandles(1,objectiveIndex) = ax;
    logValues = log10(max(rmsPositionErrorKm(:,:,objectiveIndex),10^logMinimum));
    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects,logValues);
    colormap(ax,turbo(256));
    clim(ax,[logMinimum logMaximum]);
    styleAxes(ax,style,config.networkSizes,spacecraftNames,objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)) + " — RMS error", ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    xlabel(ax,"Number of sensors, N_s");

    ax = axes(fig,"Position",axisPositions(2+objectiveIndex,:));
    axesHandles(2,objectiveIndex) = ax;
    imagesc(ax,1:numberOfNetworkSizes,1:numberOfObjects, ...
        observableEpochPercent(:,:,objectiveIndex));
    colormap(ax,turbo(256));
    clim(ax,[0 100]);
    styleAxes(ax,style,config.networkSizes,spacecraftNames,objectiveIndex == 1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)) + " — observability", ...
        "FontName",style.fontName,"FontSize",style.labelFontSize, ...
        "FontWeight","bold");
    xlabel(ax,"Number of sensors, N_s");
end

annotation(fig,"textbox",[0.18 0.94 0.56 0.045], ...
    "String","Operational-spacecraft tracking performance", ...
    "HorizontalAlignment","center","VerticalAlignment","middle", ...
    "EdgeColor","none","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold", ...
    "Color",style.textColor);

rmsColorbar = colorbar(axesHandles(1,end),"eastoutside");
rmsColorbar.Position = [0.84 0.57 0.022 0.32];
rmsColorbar.Label.String = "RMS position error (km)";
rmsTicks = chooseTicks(logMinimum,logMaximum,6);
rmsColorbar.Ticks = rmsTicks;
rmsColorbar.TickLabels = compose("%.3g",10.^rmsTicks);
styleColorbar(rmsColorbar,style);

obsColorbar = colorbar(axesHandles(2,end),"eastoutside");
obsColorbar.Position = [0.84 0.12 0.022 0.32];
obsColorbar.Label.String = "Observable epochs (%)";
obsColorbar.Ticks = 0:20:100;
styleColorbar(obsColorbar,style);

for objectiveIndex = 1:numberOfObjectives
    axesHandles(1,objectiveIndex).Position = axisPositions(objectiveIndex,:);
    axesHandles(2,objectiveIndex).Position = axisPositions(2+objectiveIndex,:);
end

drawnow;
outputFile = fullfile(config.outputDirectory, ...
    "operational_rso_tracking_heatmaps.eps");
exportgraphics(fig,outputFile,"ContentType","image", ...
    "Resolution",config.exportResolution, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.rmsPositionErrorKm = rmsPositionErrorKm;
plotInfo.observableEpochPercent = observableEpochPercent;
plotInfo.spacecraftNames = spacecraftNames;

fprintf("Operational-RSO combined tracking figure:\n  %s\n",outputFile);
end

function styleAxes(ax,style,networkSizes,spacecraftNames,showLabels)
ax.YDir = "reverse";
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.XColor = style.textColor;
ax.YColor = style.textColor;
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.Layer = "top";
ax.Box = "on";
ax.XTick = 1:numel(networkSizes);
ax.XTickLabel = string(networkSizes);
ax.YTick = 1:numel(spacecraftNames);
if showLabels
    ax.YTickLabel = spacecraftNames;
else
    ax.YTickLabel = strings(numel(spacecraftNames),1);
end
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
end

function titleText = objectiveTitle(objectiveMode)
if objectiveMode == "information"
    titleText = "Information";
else
    titleText = "Coverage";
end
end

function ticks = chooseTicks(minimumValue,maximumValue,maximumTicks)
allTicks = minimumValue:maximumValue;
if numel(allTicks) <= maximumTicks
    ticks = allTicks;
else
    index = unique(round(linspace(1,numel(allTicks),maximumTicks)));
    ticks = allTicks(index);
end
end

function styleColorbar(cb,style)
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";
cb.Label.FontName = style.fontName;
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end

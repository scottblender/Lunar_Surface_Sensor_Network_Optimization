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

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end

fig = plotOperationalTrackingHeatmaps(rmsPositionErrorKm, ...
    observableEpochPercent,spacecraftNames,config.networkSizes, ...
    config.objectiveModes);

outputFile = fullfile(config.outputDirectory,"operational_rso_tracking_heatmaps.eps");
% Preserve the operational figure's local typography increase during export.
setappdata(fig,"ManuscriptTypographyFinalized",true);
exportManuscriptFigure(fig,string(outputFile),fig.Position(3),fig.Position(4));

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.rmsPositionErrorKm = rmsPositionErrorKm;
plotInfo.observableEpochPercent = observableEpochPercent;
plotInfo.spacecraftNames = spacecraftNames;

fprintf("Operational-RSO combined tracking figure:\n  %s\n",outputFile);
end

function fig = plotOperationalTrackingHeatmaps( ...
    rms,observable,names,networkSizes,modes)

style = publicationPlotStyle();
numberOfObjects = numel(names);
numberOfModes = numel(modes);
assert(numberOfModes==2, ...
    "Operational manuscript layout expects information and coverage columns.");

figureWidth = style.heatmapWidthInches;
figureHeight = style.heatmapHeightInches + 1.0;
fig = figure("Name","Operational RSO tracking performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 figureWidth figureHeight], ...
    "Renderer","opengl");

positive = rms(isfinite(rms) & rms>0);
assert(~isempty(positive),"No positive tracking errors are available.");
rmsLimits = [floor(log10(min(positive))) ceil(log10(max(positive)))];
if rmsLimits(2)<=rmsLimits(1)
    rmsLimits(2)=rmsLimits(1)+1;
end

% Fixed normalized geometry. This deliberately avoids nested tiledlayout
% because MATLAB can reflow tile decorations during EPS printing.
xPositions = [0.11 0.50];
axesWidth = 0.28;
rowHeight = 0.25;
rowBottom = [0.59 0.19];
colorbarX = 0.84;
colorbarWidth = 0.018;

axisFontSize = 30;
colorbarFontSize = 28;
colorbarLabelFontSize = 32;
sharedLabelFontSize = 42;

for row = 1:2
    for column = 1:numberOfModes
        ax = axes(fig,"Units","normalized", ...
            "Position",[xPositions(column) rowBottom(row) axesWidth rowHeight]);
        ax.Tag = "operationalTrackingHeatmap";

        if row==1
            values = log10(max(rms(:,:,column),10^rmsLimits(1)));
            colorLimits = rmsLimits;
        else
            values = observable(:,:,column);
            colorLimits = [0 100];
        end

        imagesc(ax,1:numel(networkSizes),1:numberOfObjects,values);
        colormap(ax,turbo(256));
        clim(ax,colorLimits);

        ax.YDir = "reverse";
        ax.FontName = style.fontName;
        ax.FontSize = axisFontSize;
        ax.FontWeight = "bold";
        ax.TickDir = "out";
        ax.Box = "on";
        ax.XTick = 1:numel(networkSizes);
        ax.XTickLabel = string(networkSizes);
        ax.YTick = 1:numberOfObjects;
        ax.TickLabelInterpreter = "none";

        % Give the first and last sensor-count labels real physical room
        % inside the axes instead of placing them on the image boundaries.
        xlim(ax,[0.20 numel(networkSizes)+0.80]);
        ylim(ax,[0.5 numberOfObjects+0.5]);

        if column==1
            ax.YTickLabel = names;
        else
            ax.YTickLabel = strings(numberOfObjects,1);
        end
    end

    % Independent colorbar axes keep the right-hand scale from shrinking
    % either heatmap axis.
    cax = axes(fig,"Visible","off","Units","normalized", ...
        "Position",[colorbarX rowBottom(row) 0.01 rowHeight]);
    colormap(cax,turbo(256));
    if row==1
        clim(cax,rmsLimits);
    else
        clim(cax,[0 100]);
    end
    cb = colorbar(cax);
    cb.Units = "normalized";
    cb.Position = [colorbarX rowBottom(row) colorbarWidth rowHeight];
    cb.FontName = style.fontName;
    cb.FontSize = colorbarFontSize;
    cb.FontWeight = "bold";
    cb.Label.FontSize = colorbarLabelFontSize;
    cb.Label.FontWeight = "bold";

    if row==1
        ticks = unique(round(linspace( ...
            rmsLimits(1),rmsLimits(2),min(6,diff(rmsLimits)+1))));
        cb.Ticks = ticks;
        cb.TickLabels = compose("%.3g",10.^ticks);
        cb.Label.String = "RMS position error (km)";
    else
        cb.Ticks = 0:20:100;
        cb.Label.String = "Observable epochs (%)";
    end
end

% Fixed figure-level label: it is not owned by a layout, so its size and
% placement cannot be reset when the EPS renderer resolves axes decorations.
annotation(fig,"textbox",[0.18 0.055 0.64 0.060], ...
    "String","Number of sensors, N_s", ...
    "EdgeColor","none", ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "FontName",style.fontName, ...
    "FontSize",sharedLabelFontSize, ...
    "FontWeight","bold", ...
    "Interpreter","tex");

drawnow;
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end
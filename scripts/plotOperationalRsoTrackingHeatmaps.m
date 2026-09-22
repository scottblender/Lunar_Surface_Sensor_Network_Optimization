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

% Use fixed axes positions rather than nested tiled layouts. The geometry is
% deliberately compact, but the left margin is wide enough for the complete
% spacecraft names and the right margin is reserved for the two colorbars.
figureWidth = style.heatmapWidthInches;
figureHeight = 9.5;
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

% Explicit normalized positions prevent MATLAB from reflowing labels at EPS
% print time. The x limits place the first and last sensor-count ticks well
% inside the axes box rather than directly on its boundary.
xPositions = [0.22 0.53];
axesWidth = 0.23;
rowBottom = [0.58 0.20];
rowHeight = 0.25;
colorbarX = 0.80;
colorbarWidth = 0.015;

axisFontSize = 22;
colorbarFontSize = 20;
colorbarLabelFontSize = 22;
sharedLabelFontSize = 26;

for row = 1:2
    for column = 1:numberOfModes
        axesPosition = [xPositions(column) rowBottom(row) axesWidth rowHeight];
        ax = axes(fig,"Units","normalized", ...
            "Position",axesPosition, ...
            "PositionConstraint","innerposition");
        hold(ax,"on");

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
        xlim(ax,[0.25 numel(networkSizes)+0.75]);
        ylim(ax,[0.5 numberOfObjects+0.5]);

        if column==1
            ax.YTickLabel = names;
        else
            ax.YTickLabel = strings(numberOfObjects,1);
        end

        if column==numberOfModes
            cb = colorbar(ax);
            cb.Units = "normalized";
            cb.Position = [colorbarX rowBottom(row) colorbarWidth rowHeight];
            cb.FontName = style.fontName;
            cb.FontSize = colorbarFontSize;
            cb.FontWeight = "bold";
            cb.Label.FontName = style.fontName;
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

            % Colorbar creation can resize its peer axes; restore the fixed
            % heatmap box after the colorbar has been positioned.
            ax.Position = axesPosition;
        end
    end
end

annotation(fig,"textbox",[0.30 0.060 0.42 0.055], ...
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
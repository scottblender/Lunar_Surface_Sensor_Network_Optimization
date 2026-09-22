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

fig = plotManuscriptTrackingHeatmaps(rmsPositionErrorKm, ...
    observableEpochPercent,spacecraftNames,config.networkSizes, ...
    config.objectiveModes,"Operational RSO tracking performance");

% Figure 26 is reduced substantially in the manuscript. Increase only this
% operational/legacy figure's typography so the shared design-RSO heatmap
% styling remains unchanged.
increaseFigureTypography(fig,1.25);
finalizeOperationalFigure(fig);

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

function increaseFigureTypography(fig,scaleFactor)
objects = findall(fig,"-property","FontSize");
for objectIndex = 1:numel(objects)
    objects(objectIndex).FontSize = objects(objectIndex).FontSize*scaleFactor;
    if isprop(objects(objectIndex),"FontWeight")
        objects(objectIndex).FontWeight = "bold";
    end
end

% Re-evaluate text extents after the local size increase so EPS export keeps
% the spacecraft names and colorbar labels inside each axes decoration box.
drawnow;
axesHandles = findall(fig,"Type","axes");
for ax = axesHandles.'
    ax.Units = "normalized";
    ax.LooseInset = max(ax.LooseInset,ax.TightInset + [0.015 0.015 0.015 0.015]);
end
drawnow;
end

function finalizeOperationalFigure(fig)
style = publicationPlotStyle();

% Shift the full nested heatmap layout inward so long spacecraft names and
% right-side colorbar labels remain inside the EPS page without changing the
% compact 2-by-2 visual structure.
layouts = findall(fig,"Type","tiledlayout");
for layoutIndex = 1:numel(layouts)
    layout = layouts(layoutIndex);

    if isequal(layout.Parent,fig)
        layout.Units = "normalized";
        layout.OuterPosition = [0.085 0.055 0.83 0.90];

        layout.XLabel.FontName = style.fontName;
        layout.XLabel.FontSize = 30;
        layout.XLabel.FontWeight = "bold";
    end
end

% Keep endpoint sensor-count labels away from the exact heatmap boundaries.
axesHandles = findall(fig,"Type","axes");
for ax = axesHandles.'
    if numel(ax.XTick)==4 && isequal(double(ax.XTick(:).'),1:4)
        xlim(ax,[0.35 4.65]);
    end
end

drawnow;
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end
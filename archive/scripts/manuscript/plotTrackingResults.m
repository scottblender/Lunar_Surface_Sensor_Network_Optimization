function plotInfo = plotTrackingResults(metrics,userConfig)
% PLOTTRACKINGRESULTS - Export tracking metrics for a named spacecraft population.
% Metrics contain rmsPositionErrorKm, observabilityPercent, and spacecraftNames.
% Supply networkSizes/objectiveModes in the metrics or configuration.

arguments
    metrics (1,1) struct
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(fileparts(scriptDirectory));
resultsDirectory = fullfile(projectRoot,"results");
addpath(genpath(fullfile(projectRoot,"scripts")));

config = struct();
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config.networkSizes = [3 5 7 10];
config.objectiveModes = ["information","coverage"];
config.outputName = "tracking_performance.eps";
config.figureName = "Tracking performance";
config.layout = "tiled";
for field = ["networkSizes","objectiveModes"]
    if isfield(metrics,field), config.(field) = metrics.(field); end
end
config = utilities.overrideConfig(config,userConfig);
config.outputDirectory = string(config.outputDirectory);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

assert(isfield(metrics,"rmsPositionErrorKm") && ...
    isfield(metrics,"observabilityPercent") && ...
    isfield(metrics,"spacecraftNames"), ...
    "Tracking results do not contain the required tracking metrics.");

rmsPositionErrorKm = metrics.rmsPositionErrorKm;
observableEpochPercent = metrics.observabilityPercent;
spacecraftNames = string(metrics.spacecraftNames(:));
numberOfObjectives = numel(config.objectiveModes);
numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjects = numel(spacecraftNames);

assert(size(rmsPositionErrorKm,1) == numberOfObjects && ...
    size(rmsPositionErrorKm,2) == numberOfNetworkSizes && ...
    size(rmsPositionErrorKm,3) == numberOfObjectives, ...
    "Tracking RMS array has unexpected dimensions.");
assert(isequal(size(observableEpochPercent),size(rmsPositionErrorKm)), ...
    "Tracking observability array has unexpected dimensions.");

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end

fig = plotTrackingPerformance(rmsPositionErrorKm,observableEpochPercent, ...
    spacecraftNames,config.networkSizes,config.objectiveModes,config);

outputFile = fullfile(config.outputDirectory,config.outputName);
exportManuscriptFigure(fig,string(outputFile),fig.Position(3),fig.Position(4));

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.rmsPositionErrorKm = rmsPositionErrorKm;
plotInfo.observableEpochPercent = observableEpochPercent;
plotInfo.spacecraftNames = spacecraftNames;

fprintf("Tracking figure:\n  %s\n",outputFile);
end

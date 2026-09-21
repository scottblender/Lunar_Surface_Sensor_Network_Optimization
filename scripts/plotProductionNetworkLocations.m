function plotInfo = plotProductionNetworkLocations(campaign,userConfig)
% PLOTPRODUCTIONNETWORKLOCATIONS Geographic selection-frequency heatmaps.
arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end
style = publicationPlotStyle();
config = campaign.configuration;
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory"), outputDirectory=string(userConfig.outputDirectory); end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
latitudeEdges = -90:10:0;
longitudeEdges = 0:30:360;
latitudeCenters = (latitudeEdges(1:end-1)+latitudeEdges(2:end))/2;
longitudeCenters = (longitudeEdges(1:end-1)+longitudeEdges(2:end))/2;
projectRoot = fileparts(fileparts(mfilename("fullpath")));
demFile = string(fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat"));
if isfield(userConfig,"syntheticDemFile"), demFile=string(userConfig.syntheticDemFile); end
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,campaign.database.config.moon.radiusKm,24,48);
plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    mode = config.objectiveModes(objectiveIndex);
    columns = min(2,numel(config.networkSizes));
    rows = ceil(numel(config.networkSizes)/columns);
    width = 10; height = 4.0*rows+0.5;
    fig = figure("Name",mode+" sensor selection by latitude/longitude", ...
        "Color","white","Units","inches","Position",[1 1 width height]);
    layout = tiledlayout(fig,rows,columns,"TileSpacing","compact","Padding","compact");
    frequency = zeros(numel(latitudeCenters),numel(longitudeCenters),numel(config.networkSizes));
    for networkIndex = 1:numel(config.networkSizes)
        study = campaign.studies{networkIndex,objectiveIndex};
        runs = study.runStates(1:config.numberOfRuns);
        frequency(:,:,networkIndex) = binNetworkSelectionFrequency( ...
            runs,campaign.database,latitudeEdges,longitudeEdges);
        ax = nexttile(layout,networkIndex);
        plotPolarSelectionMap(ax,frequency(:,:,networkIndex), ...
            latitudeEdges,longitudeEdges,dem,style);
    end
    cb = colorbar(ax); cb.Layout.Tile = "east";
    cb.Label.String = "Selection frequency (%)";
    cb.Ticks = 0:20:100;
    cb.FontSize = max(16,style.axisFontSize-2); cb.FontWeight = "bold";
    cb.Label.FontSize = max(18,style.labelFontSize-2); cb.Label.FontWeight = "bold";
    outputFile = fullfile(outputDirectory,sprintf("network_locations_vs_ns_%s.eps",mode));
    exportManuscriptFigure(fig,string(outputFile),width,height);
    plotInfo.(char(mode)) = struct("figure",fig,"outputFile",string(outputFile), ...
        "selectionPercent",frequency,"latitudeEdges",latitudeEdges,"longitudeEdges",longitudeEdges);
end
end

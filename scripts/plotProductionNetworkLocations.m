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
plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    mode = config.objectiveModes(objectiveIndex);
    columns = min(2,numel(config.networkSizes));
    rows = ceil(numel(config.networkSizes)/columns);
    width = 10; height = 3.1*rows+1.2;
    fig = figure("Name",mode+" sensor selection by latitude/longitude", ...
        "Color","white","Units","inches","Position",[1 1 width height]);
    layout = tiledlayout(fig,rows,columns,"TileSpacing","loose","Padding","loose");
    frequency = zeros(numel(latitudeCenters),numel(longitudeCenters),numel(config.networkSizes));
    for networkIndex = 1:numel(config.networkSizes)
        study = campaign.studies{networkIndex,objectiveIndex};
        runs = study.runStates(1:config.numberOfRuns);
        frequency(:,:,networkIndex) = binNetworkSelectionFrequency( ...
            runs,campaign.database,latitudeEdges,longitudeEdges);
        ax = nexttile(layout,networkIndex);
        imagesc(ax,longitudeCenters,latitudeCenters,frequency(:,:,networkIndex));
        ax.YDir = "normal";
        xlim(ax,[0 360]); ylim(ax,[-90 0]);
        xticks(ax,0:90:360); yticks(ax,-90:30:0);
        clim(ax,[0 100]); colormap(ax,[1 1 1;turbo(255)]);
        ax.FontName = style.fontName; ax.FontSize = 12; ax.FontWeight = "bold";
        ax.TickDir = "out";
    end
    cb = colorbar(ax); cb.Layout.Tile = "east";
    cb.Label.String = "Runs selecting bin (%)";
    cb.FontSize = 12; cb.FontWeight = "bold";
    cb.Label.FontSize = 14; cb.Label.FontWeight = "bold";
    xlabel(layout,"East longitude (deg)", ...
        "FontSize",14,"FontWeight","bold");
    ylabel(layout,"Latitude (deg)","FontSize",14,"FontWeight","bold");
    outputFile = fullfile(outputDirectory,sprintf("network_locations_vs_ns_%s.eps",mode));
    exportManuscriptFigure(fig,string(outputFile),width,height);
    plotInfo.(char(mode)) = struct("figure",fig,"outputFile",string(outputFile), ...
        "selectionPercent",frequency,"latitudeEdges",latitudeEdges,"longitudeEdges",longitudeEdges);
end
end

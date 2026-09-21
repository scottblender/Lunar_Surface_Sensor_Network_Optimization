function plotInfo = plotDemProducts(userConfig)
% PLOTDEMPRODUCTS Generate original and reduced DEM manuscript figures.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
dataDirectory = fullfile(projectRoot,"data");

defaults = struct();
defaults.outputDirectory = fullfile(projectRoot,"results","manuscript_artifacts");
defaults.fullDemFile = fullfile(dataDirectory,"Full_Resolution_DEM.mat");
defaults.syntheticDemFile = fullfile(dataDirectory,"Synthetic_Lunar_DEM.mat");
defaults.moonRadiusKm = 1737.4;
config = mergeStruct(defaults,userConfig);

style = publicationPlotStyle();
files = [string(config.fullDemFile),string(config.syntheticDemFile)];
names = ["Original LOLA DEM","Synthetic DEM"];
stems = ["LOLA_Global_DEM","Synthetic_Lunar_DEM"];
plotInfo = struct();

for k = 1:2
    assert(isfile(files(k)),"DEM file was not found: %s",files(k));
    [dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
        files(k),config.moonRadiusKm,24,48);

    lonDeg = linspace(0,360,721);
    latDeg = linspace(-90,90,361);
    [lonMesh,latMesh] = meshgrid(lonDeg,latDeg);
    elevation = double(dem(deg2rad(latMesh),deg2rad(lonMesh)));

    fig = figure("Name",names(k),"Color",style.backgroundColor, ...
        "Units","inches","Position",[1 1 9.0 4.6],"Renderer","opengl");
    layout = tiledlayout(fig,1,1,"Padding","loose");
    ax = nexttile(layout);
    imagesc(ax,lonDeg,latDeg,elevation);
    set(ax,"YDir","normal");
    axis(ax,"tight");
    colormap(ax,turbo(256));
    cb = colorbar(ax); cb.Layout.Tile = "east";
    cb.Label.String = "Elevation (km)";
    cb.Label.FontWeight = "bold";
    cb.Label.FontSize = style.labelFontSize;
    cb.FontName = style.fontName;
    cb.FontSize = style.axisFontSize;
    cb.FontWeight = "bold";

    xlabel(ax,"East longitude (deg)");
    ylabel(ax,"Latitude (deg)");
    ax.FontName = style.fontName;
    ax.FontSize = style.axisFontSize;
    ax.FontWeight = "bold";
    ax.LineWidth = 0.9;
    ax.TickDir = "out";
    ax.XTick = 0:60:360;
    ax.YTick = -90:30:90;
    ax.XLabel.FontSize = style.labelFontSize;
    ax.YLabel.FontSize = style.labelFontSize;
    ax.XLabel.FontWeight = "bold";
    ax.YLabel.FontWeight = "bold";

    outputFile = fullfile(config.outputDirectory,stems(k)+".eps");
    applyManuscriptTypography(fig,string(outputFile),9.0);
    layout.Units = "normalized";
    % Preserve the same top edge while reserving more room beneath the x-axis
% label in the EPS export.
layout.OuterPosition = [0.02 0.075 0.90 0.89];
    setappdata(fig,"ManuscriptTypographyFinalized",true);
    exportManuscriptFigure(fig,string(outputFile),9.0,4.6);
    plotInfo.(char(stems(k))) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end
end

function out = mergeStruct(defaults,override)
out = defaults;
fields = fieldnames(override);
for k = 1:numel(fields), out.(fields{k}) = override.(fields{k}); end
end

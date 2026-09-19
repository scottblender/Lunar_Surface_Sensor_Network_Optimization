function plotInfo = plotClpsDesignDomain(userConfig)
% PLOTCLPSDESIGNDOMAIN Generate southern-hemisphere CLPS/design-domain figure.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
dataDirectory = fullfile(projectRoot,"data");

defaults = struct();
defaults.outputDirectory = fullfile(projectRoot,"results","manuscript_artifacts");
defaults.demFile = fullfile(dataDirectory,"Full_Resolution_DEM.mat");
defaults.moonRadiusKm = 1737.4;
config = mergeStruct(defaults,userConfig);
style = publicationPlotStyle();

assert(isfile(config.demFile),"Full DEM was not found: %s",config.demFile);
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(config.demFile),config.moonRadiusKm,24,48);

lonDeg = linspace(0,360,721);
latDeg = linspace(-90,0,361);
[lonMesh,latMesh] = meshgrid(lonDeg,latDeg);
elevation = double(dem(deg2rad(latMesh),deg2rad(lonMesh)));

fig = figure("Name","CLPS deployment context and design domain", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 10.0 5.5],"Renderer","opengl");
ax = axes(fig);
hold(ax,"on");
imagesc(ax,lonDeg,latDeg,elevation);
set(ax,"YDir","normal");
colormap(ax,turbo(256));
axis(ax,[0 360 -90 0]);

% Restricted comparison band.
patch(ax,[0 360 360 0],[-90 -90 -75 -75], ...
    style.boundaryColor,"FaceAlpha",0.10,"EdgeColor","none");
plot(ax,[0 360],[-75 -75],"-","Color",style.boundaryColor,"LineWidth",2.4);

% Completed south-polar CLPS landings.
completedLat = [-80.1277 -84.7754];
completedLon = [1.4357 29.1264];
scatter(ax,completedLon,completedLat,90,"o", ...
    "MarkerFaceColor",style.redColor,"MarkerEdgeColor",[1 1 1], ...
    "LineWidth",1.1,"DisplayName","Completed CLPS");

% Planned south-polar / regional anchors used in the manuscript context.
plannedLat = [-84.6 -75 -75 -75];
plannedLon = [31 120 240 315];
scatter(ax,plannedLon,plannedLat,92,"d", ...
    "MarkerFaceColor",style.magentaColor,"MarkerEdgeColor",[1 1 1], ...
    "LineWidth",1.1,"DisplayName","Planned / regional context");

text(ax,8,-78.4,"IM-1","FontName",style.fontName, ...
    "FontSize",style.annotationFontSize,"FontWeight","bold", ...
    "Color",style.textColor,"BackgroundColor",[1 1 1],"Margin",1);
text(ax,34,-83.2,"IM-2 / Mons Mouton","FontName",style.fontName, ...
    "FontSize",style.annotationFontSize,"FontWeight","bold", ...
    "Color",style.textColor,"BackgroundColor",[1 1 1],"Margin",1);
text(ax,355,-73.2,"Restricted comparison boundary", ...
    "HorizontalAlignment","right","FontName",style.fontName, ...
    "FontSize",style.annotationFontSize,"FontWeight","bold", ...
    "Color",style.boundaryColor,"BackgroundColor",[1 1 1],"Margin",1);

xlabel(ax,"East longitude (deg)");
ylabel(ax,"Latitude (deg)");
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.XTick = 0:60:360;
ax.YTick = -90:15:0;
ax.XLabel.FontSize = style.labelFontSize;
ax.YLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontWeight = "bold";

lgd = legend(ax,"Location","northoutside","Orientation","horizontal");
lgd.FontName = style.fontName;
lgd.FontSize = style.legendFontSize;
lgd.FontWeight = "bold";

cb = colorbar(ax);
cb.Label.String = "Elevation (km)";
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";

outputFile = fullfile(config.outputDirectory, ...
    "CLPS_Southern_Hemisphere_Design_Domain.eps");
exportManuscriptFigure(fig,string(outputFile),10.0,5.5);

plotInfo = struct("figure",fig,"outputFile",string(outputFile));
end

function out = mergeStruct(defaults,override)
out = defaults;
fields = fieldnames(override);
for k = 1:numel(fields), out.(fields{k}) = override.(fields{k}); end
end

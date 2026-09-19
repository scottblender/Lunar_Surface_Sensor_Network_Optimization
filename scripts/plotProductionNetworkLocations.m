function plotInfo = plotProductionNetworkLocations(campaign,userConfig)
% PLOTPRODUCTIONNETWORKLOCATIONS Plot sensor-selection frequency by N_s.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = campaign.configuration;
database = campaign.database;
projectRoot = string(campaign.projectRoot);
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory"), outputDirectory = string(userConfig.outputDirectory); end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

demFile = "";
if isfield(userConfig,"demFile"), demFile = string(userConfig.demFile); end
if strlength(demFile)==0
    candidates = [ ...
        fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat"); ...
        fullfile(projectRoot,"data","Full_Resolution_DEM.mat")];
    for k=1:numel(candidates)
        if isfile(candidates(k)), demFile=candidates(k); break, end
    end
end
assert(strlength(demFile)>0 && isfile(demFile),"No manuscript DEM could be resolved.");

moonRadiusKm = database.config.moon.radiusKm;
[dem,~] = digitalElevationModel.loadTriaxialLunarDem(demFile,moonRadiusKm,24,48);
background = buildSouthernHemisphereBackground(dem,moonRadiusKm);

plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    objectiveMode = config.objectiveModes(objectiveIndex);
    fieldName = char(objectiveMode);
    objectiveColor = style.blueColor;
    if objectiveMode=="coverage", objectiveColor=style.redColor; end

    fig = figure("Name",objectiveMode+" network locations", ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 7.0 6.8],"Renderer","opengl");
    layout = tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
    axesHandles = gobjects(numel(config.networkSizes),1);

    for networkIndex = 1:numel(config.networkSizes)
        ax = nexttile(layout,networkIndex);
        axesHandles(networkIndex)=ax;
        drawBackground(ax,background,style);

        studyState = campaign.studies{networkIndex,objectiveIndex};
        counts = zeros(database.meta.numberOfCandidates,1);
        for runIndex=1:config.numberOfRuns
            indices=double(studyState.runStates{runIndex}.bestSensorIndices(:));
            counts(indices)=counts(indices)+1;
        end
        selected=find(counts>0);
        [xKm,yKm]=candidateXY(selected,database,moonRadiusKm);
        markerArea=18+145*(counts(selected)/config.numberOfRuns);
        scatter(ax,xKm,yKm,markerArea,"o", ...
            "MarkerFaceColor",objectiveColor, ...
            "MarkerEdgeColor",[1 1 1],"LineWidth",0.8);

        title(ax,sprintf("N_s = %d",config.networkSizes(networkIndex)), ...
            "FontName",style.fontName,"FontSize",style.labelFontSize, ...
            "FontWeight","bold");
    end

    cb=colorbar(axesHandles(end));
    cb.Layout.Tile="east";
    cb.Label.String="Elevation (km)";
    cb.Label.FontWeight="bold";
    cb.Label.FontSize=style.labelFontSize;
    cb.FontName=style.fontName;
    cb.FontSize=style.axisFontSize;
    cb.FontWeight="bold";

    annotation(fig,"textbox",[0.08 0.012 0.84 0.045], ...
        "String",sprintf("Marker area scales with selection frequency across %d runs", ...
        config.numberOfRuns), ...
        "HorizontalAlignment","center","VerticalAlignment","middle", ...
        "EdgeColor","none","FontName",style.fontName, ...
        "FontSize",style.annotationFontSize,"FontWeight","bold", ...
        "Interpreter","none");

    outputFile=fullfile(outputDirectory, ...
        sprintf("network_locations_vs_ns_%s.eps",objectiveMode));
    exportManuscriptFigure(fig,string(outputFile),7.0,6.8);
    plotInfo.(fieldName)=struct("figure",fig,"outputFile",string(outputFile));
end
end

function b=buildSouthernHemisphereBackground(dem,moonRadiusKm)
lon=linspace(0,360,721); lat=linspace(-90,0,361);
[lonM,latM]=meshgrid(lon,lat);
elev=double(dem(deg2rad(latM),deg2rad(lonM)));
r=moonRadiusKm.*deg2rad(90+latM);
b=struct("x",r.*sind(lonM),"y",r.*cosd(lonM),"elevation",elev, ...
    "limits",[min(elev,[],"all") max(elev,[],"all")], ...
    "radius",moonRadiusKm*pi/2,"moonRadiusKm",moonRadiusKm);
end

function drawBackground(ax,b,style)
hold(ax,"on");
surf(ax,b.x,b.y,zeros(size(b.x)),b.elevation, ...
    "EdgeColor","none","FaceColor","interp");
view(ax,2); colormap(ax,turbo(256)); clim(ax,b.limits);
% No grid/reference lines are drawn in manuscript figures.
axis(ax,"equal"); axis(ax,"off");
lim=b.radius+70; xlim(ax,[-lim lim]); ylim(ax,[-lim lim]);
ax.FontName=style.fontName; ax.FontWeight="bold";
end

function [x,y]=candidateXY(indices,database,moonRadiusKm)
lat=rad2deg(database.candidates.latitudesRad(indices));
lon=rad2deg(database.candidates.longitudesRad(indices));
r=moonRadiusKm.*deg2rad(90+lat);
x=r.*sind(lon); y=r.*cosd(lon);
x=x(:); y=y(:);
end
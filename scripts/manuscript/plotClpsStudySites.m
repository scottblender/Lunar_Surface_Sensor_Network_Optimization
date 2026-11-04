function report = plotClpsStudySites(repoRoot,demFile,outputDirectory)
% PLOTCLPSSTUDYSITES Export separate, untitled polar maps over a global DEM.
% Example from the repository root after setupProject:
% plotClpsStudySites(pwd,"data/Full_Resolution_DEM.mat","figures/clps_sites")
arguments
    repoRoot (1,1) string
    demFile (1,1) string
    outputDirectory (1,1) string = "clps_site_figures"
end
assert(strlength(demFile)>0 && isfile(demFile), ...
    "Supply the global DEM MAT-file used by the study. No flat-background fallback is used.");
shared = fullfile(repoRoot,"scripts","shared");
assert(isfolder(shared),"Cannot find repository scripts/shared folder.");
oldPath = path;
restorePath = onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(shared,fullfile(repoRoot,"src"));
sites = readtable(fullfile(repoRoot,"config","paper_clps_sites.csv"), ...
    "TextType","string");
sites = sites(sites.Enabled==1,:);
assert(~isempty(sites),"No enabled study sites found.");
assert(all(isfinite(sites.LatitudeDeg) & abs(sites.LatitudeDeg)<=90 & ...
    isfinite(sites.LongitudeDeg)),"Invalid study coordinates.");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem(demFile);
% Check both hemispheres before exporting either plot. A regional DEM must
% not silently produce a blank background in the other hemisphere.
[lon,lat] = meshgrid(deg2rad(0:1:360),deg2rad(-90:0.5:90));
z = double(dem(lat,lon));
assert(all(isfinite(z),"all"),"The DEM must cover both lunar hemispheres.");
assert(max(z,[],"all")>min(z,[],"all"),"The DEM contains no elevation variation.");
elevationLimits = [min(z,[],"all") max(z,[],"all")];
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
style = publicationPlotStyle();
style.axisFontSize = 17;
report = struct("sites",sites,"demFile",demFile,"hasTerrainBackdrop",true, ...
    "elevationLimitsKm",elevationLimits);
for hemisphere = ["south","north"]
    fig = figure("Color","white","Units","inches", ...
        "Position",[0.5 0.5 6.3 6.3],"Visible","off");
    closeFigure = onCleanup(@()close(fig));
    ax = axes(fig,"Position",[0.10 0.25 0.80 0.66]);
    latitudeEdges = -90:10:0;
    selected = sites.LatitudeDeg<0;
    if hemisphere=="north"
        latitudeEdges = 0:10:90;
        selected = sites.LatitudeDeg>=0;
    end
    plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
    % Replace the helper's independently normalized RGB terrain with scalar
    % elevations. Both maps and colorbars now use one global elevation scale.
    [mapLon,mapLat] = meshgrid(deg2rad(0:360),deg2rad(latitudeEdges(1):0.5:latitudeEdges(end)));
    % The shared helper hides terrain handles from legends and findobj.
    terrain = findall(ax,"Type","surface");
    assert(isscalar(terrain),"Expected one DEM surface.");
    terrain.CData = double(dem(mapLat,mapLon));
    terrain.CDataMapping = "scaled";
    colormap(ax,repmat(linspace(0.30,0.96,256).',1,3));
    clim(ax,elevationLimits);
    elevationBar = colorbar(ax,"southoutside");
    elevationBar.Units = "normalized";
    elevationBar.Position = [0.22 0.12 0.56 0.025];
    elevationBar.Ticks = linspace(elevationLimits(1),elevationLimits(2),5);
    elevationBar.TickLabels = compose("%.1f",elevationBar.Ticks);
    elevationBar.Label.String = "Elevation (km)";
    % Lock the map position after colorbar creation reserves its own space.
    ax.Position = [0.10 0.25 0.80 0.66];
    % Use the shared font family and bold labels throughout.
    set(findall(ax,"Type","text"),"FontName",style.fontName,"FontWeight","bold");
    current = sites(selected,:);
    radius = (90-abs(current.LatitudeDeg))/90;
    x = radius.*sind(current.LongitudeDeg);
    y = radius.*cosd(current.LongitudeDeg);
    representative = current.Role=="south_pole_option";
    for k = 1:height(current)
        color = style.sensorColor;
        if representative(k), color = style.orangeColor; end
        scatter3(ax,x(k),y(k),4,115,color,"p","filled", ...
            "MarkerEdgeColor","white","LineWidth",0.9,"HandleVisibility","off");
        label = strrep(current.SiteId(k),"BGM","BG-");
        if label=="IM3", label="IM-3"; end
        tx = x(k)+0.04; ty = y(k)+0.06; align = "left";
        switch current.SiteId(k)
            case "POLE_MOUTON"
                label="Mons Mouton"; tx=-0.10; ty=0.23; align="right";
            case "POLE_SCHRODINGER"
                label="Schr"+string(char(246))+"dinger Basin";
                tx=0.18; ty=-0.23;
            case "BGM1"
                tx=0.67; ty=0.51; align="right";
            case "BGM3"
                tx=-0.30; ty=0.37;
            case "IM3"
                tx=-0.75; ty=0.63;
        end
        plot3(ax,[x(k) tx],[y(k) ty],[4.5 4.5], ...
            "-","Color",[0.30 0.30 0.30],"LineWidth",0.65,"HandleVisibility","off");
        text(ax,tx,ty,5,label,"Interpreter","none", ...
            "HorizontalAlignment",align,"VerticalAlignment","middle", ...
            "FontSize",17,"FontName",style.fontName,"FontWeight","bold", ...
            "BackgroundColor","white","Margin",1.3,"Clipping","off");
    end
    % The LaTeX caption explains marker colors. No panel titles or legend.
    % Match reference-frame and measurement figures at half manuscript width.
    setappdata(fig,"ManuscriptPlacementWidthInches",style.manuscriptHalfWidthInches);
    applyManuscriptTypography(fig,"clps_study_sites_"+hemisphere+".eps",6.3);
    fitTextInsideFigure(fig,ax,style.exportPaddingInches);
    setappdata(fig,"ManuscriptTypographyFinalized",true);
    stem = fullfile(outputDirectory,"clps_study_sites_"+hemisphere);
    files = struct("pngFile",stem+".png","pdfFile",stem+".pdf","epsFile",stem+".eps");
    exportManuscriptFigure(fig,files.epsFile,6.3,6.3);
    exportgraphics(fig,files.pngFile,"Resolution",400);
    exportgraphics(fig,files.pdfFile,"ContentType","image","Resolution",400);
    report.(hemisphere) = files;
    clear closeFigure
end
end

function fitTextInsideFigure(fig,ax,paddingInches)
% Measure rendered text after typography is final, including exterior labels.
% Shrink the map symmetrically until every text box fits the export canvas.
fig.Units = "pixels";
figSize = fig.Position(3:4);
padding = paddingInches*get(groot,"ScreenPixelsPerInch");
ax.Units = "normalized";
for attempt = 1:40
    drawnow;
    origin = getpixelposition(ax,true);
    labels = findall(ax,"Type","text");
    fits = true;
    for n = 1:numel(labels)
        if isempty(labels(n).String), continue, end
        originalUnits = labels(n).Units;
        labels(n).Units = "pixels";
        box = labels(n).Extent;
        labels(n).Units = originalUnits;
        % Include a small allowance for background margins and font metrics.
        lower = origin(1:2)+box(1:2)-4;
        upper = origin(1:2)+box(1:2)+box(3:4)+4;
        fits = fits && all(lower>=[padding 0.23*figSize(2)]) && ...
            all(upper<=figSize-padding);
    end
    if fits, return, end
    position = ax.Position;
    sizeNew = position(3:4)*0.94;
    center = position(1:2)+position(3:4)/2;
    ax.Position = [center-sizeNew/2 sizeNew];
end
error("plotClpsStudySites:TextClipping", ...
    "Text does not fit the export canvas. Increase figure size or shorten labels.");
end

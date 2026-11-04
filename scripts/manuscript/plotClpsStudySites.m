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
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
style = publicationPlotStyle();
style.axisFontSize = 17;
report = struct("sites",sites,"demFile",demFile,"hasTerrainBackdrop",true);
for hemisphere = ["south","north"]
    fig = figure("Color","white","Units","inches", ...
        "Position",[0.5 0.5 6.3 6.3],"Visible","off");
    closeFigure = onCleanup(@()close(fig));
    ax = axes(fig,"Position",[0.04 0.04 0.92 0.92]);
    latitudeEdges = -90:10:0;
    selected = sites.LatitudeDeg<0;
    if hemisphere=="north"
        latitudeEdges = 0:10:90;
        selected = sites.LatitudeDeg>=0;
    end
    plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
    % Keep the original geographic projection with lighter, smaller labels.
    set(findall(ax,"Type","text"),"FontName",style.fontName,"FontWeight","normal");
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
            "FontSize",17,"FontName",style.fontName,"FontWeight","normal", ...
            "BackgroundColor","white","Margin",1.3,"Clipping","off");
    end
    % The LaTeX caption explains marker colors. No panel titles or legend.
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

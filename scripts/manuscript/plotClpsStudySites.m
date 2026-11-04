function report = plotClpsStudySites(repoRoot,demFile,outputDirectory)
% PLOTCLPSSTUDYSITES Plot the current study's CLPS anchors and polar proxies.
% Example (run from the repository root, with this function on the path):
%   plotClpsStudySites(pwd,"","figures/clps_sites")
% Supply the same DEM MAT-file used by the selection-frequency plots to
% reproduce their terrain backdrop. An empty DEM path gives a neutral disk.
% Reuses scripts/shared helpers; does not modify the repository or its data.
arguments
    repoRoot (1,1) string
    demFile (1,1) string = ""
    outputDirectory (1,1) string = "clps_site_figures"
end
shared = fullfile(repoRoot,"scripts","shared");
assert(isfolder(shared),"Cannot find repository scripts/shared folder.");
oldPath = path; restorePath = onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(shared,fullfile(repoRoot,"src"));
sites = readtable(fullfile(repoRoot,"config","paper_clps_sites.csv"), ...
    "TextType","string");
sites = sites(sites.Enabled==1,:);
assert(~isempty(sites),"No enabled study sites found.");
assert(all(isfinite(sites.LatitudeDeg) & abs(sites.LatitudeDeg)<=90 & ...
    isfinite(sites.LongitudeDeg)),"Invalid study coordinates.");
dem = @(lat,lon)zeros(size(lat));
if strlength(demFile)>0
    [dem,~] = digitalElevationModel.loadTriaxialLunarDem(demFile);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
style = publicationPlotStyle(); style.axisFontSize = 11;
fig = figure("Color","white","Units","inches", ...
    "Position",[0.5 0.5 12 7],"Visible","off");
closeFigure = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
for hemisphere = ["south","north"]
    ax = nexttile(layout);
    latitudeEdges = -90:10:0;
    selected = sites.LatitudeDeg<0;
    if hemisphere=="north"
        latitudeEdges = 0:10:90;
        selected = sites.LatitudeDeg>=0;
    end
    % Zero frequencies retain terrain and graticules without frequency bins.
    plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
    current = sites(selected,:);
    radius = (90-abs(current.LatitudeDeg))/90;
    x = radius.*sind(current.LongitudeDeg);
    y = radius.*cosd(current.LongitudeDeg);
    proxy = current.CoordinateType=="regional_study_proxy";
    % Five-point filled stars match the best-site markers in the repo.
    anchors = scatter3(ax,x(~proxy),y(~proxy),4*ones(nnz(~proxy),1), ...
        160,style.sensorColor,"p","filled","MarkerEdgeColor","white", ...
        "LineWidth",0.8,"DisplayName","Mission anchor");
    proxies = scatter3(ax,x(proxy),y(proxy),4*ones(nnz(proxy),1), ...
        160,style.orangeColor,"p","filled","MarkerEdgeColor","white", ...
        "LineWidth",0.8,"DisplayName","South-polar study proxy");
    for k = 1:height(current)
        label = current.SiteId(k);
        % Separate the two nearby south-polar labels with leader lines.
        dx = 0.035; dy = 0.055; align = "left";
        if label=="POLE_MOUTON"
            label = "Mons Mouton proxy"; dx = -0.20; dy = 0.12; align = "right";
        elseif label=="POLE_SCHRODINGER"
            label = "Schrodinger proxy"; dx = 0.18; dy = -0.12;
        end
        plot3(ax,[x(k) x(k)+dx],[y(k) y(k)+dy],[4.5 4.5], ...
            "-","Color",style.mutedTextColor,"LineWidth",0.7);
        text(ax,x(k)+dx,y(k)+dy,5,label,"Interpreter","none", ...
            "HorizontalAlignment",align,"FontSize",11,"FontName",style.fontName, ...
            "FontWeight","bold","BackgroundColor","white","Margin",1);
    end
    title(ax,upper(extractBefore(hemisphere,2))+extractAfter(hemisphere,1)+ ...
        " polar view","FontName",style.fontName,"FontSize",13,"FontWeight","bold");
    if hemisphere=="south"
        key = legend(ax,[anchors proxies],"Location","southoutside", ...
            "Orientation","horizontal","FontSize",11,"FontName",style.fontName);
        key.Layout.Tile = "south";
    end
end
report.pngFile = fullfile(outputDirectory,"clps_study_sites.png");
report.pdfFile = fullfile(outputDirectory,"clps_study_sites.pdf");
report.epsFile = fullfile(outputDirectory,"clps_study_sites.eps");
exportManuscriptFigure(fig,report.epsFile,12,7);
exportgraphics(fig,report.pngFile,"Resolution",300);
exportgraphics(fig,report.pdfFile,"ContentType","image","Resolution",300);
report.sites = sites;
report.hasTerrainBackdrop = strlength(demFile)>0;
end

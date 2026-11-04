function report = plotGeographicDesignDomains(databaseFile,demFile,outputDirectory)
% PLOTGEOGRAPHICDESIGNDOMAINS Three rows: fixed CLPS, nearby, and global.
% Uses the built paper_shared database, including its active polar-site choice.
% Run setupProject first. No optimization or database rebuild is performed.
arguments
    databaseFile (1,1) string = ""
    demFile (1,1) string = ""
    outputDirectory (1,1) string = "figures/design_domains"
end
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
databaseFile = resolvePlotInput(databaseFile, ...
    "Select the paper_shared optimization_database.mat",fullfile(repoRoot,"results"),repoRoot);
demFile = resolvePlotInput(demFile, ...
    "Select the global DEM MAT-file",fullfile(repoRoot,"data"),repoRoot);
saved = load(databaseFile,"database");
assert(isfield(saved,"database"),"plotGeographicDesignDomains:DatabaseVariable", ...
    "The selected file must contain the saved database structure: %s",databaseFile);
database = saved.database;
assert(isfield(database,"config") && isfield(database.config,"domainComparison") && ...
    database.config.domainComparison.domain=="paper_shared", ...
    "plotGeographicDesignDomains:DatabaseDomain", ...
    "Select the paper_shared master database, not a domain view or study result.");
[views,polar] = derivePaperDomains(database);
[dem,~] = digitalElevationModel.loadTriaxialLunarDem(demFile);
style = publicationPlotStyle();
sites = polar.activeSites;
siteLon = wrapLongitude(sites.LongitudeDeg);
siteLat = sites.LatitudeDeg;
[terrainLon,terrainLat] = meshgrid(-180:0.5:180,-90:0.5:90);
elevation = double(dem(deg2rad(terrainLat),deg2rad(mod(terrainLon,360))));
assert(all(isfinite(elevation),"all"),"The DEM must cover the full lunar surface.");
elevationLimits = [min(elevation,[],"all") max(elevation,[],"all")];
assert(diff(elevationLimits)>0,"The DEM has no elevation variation.");
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
width = 8.5; height = 13;
fig = figure("Visible","off","Color","white","Units","inches", ...
    "Position",[0.5 0.5 width height]);
closeFigure = onCleanup(@()close(fig)); %#ok<NASGU>
layout = tiledlayout(fig,3,1,"TileSpacing","loose","Padding","loose");
domains = ["clps_fixed","clps","global"];
titles = ["(a) Fixed CLPS sites","(b) CLPS-constrained placement","(c) Global placement"];
counts = zeros(3,1); shown = zeros(3,1);
sampleIds = cell(3,1);
axesHandles = gobjects(3,1);
for panel = 1:3
    ax = nexttile(layout); axesHandles(panel) = ax;
    hold(ax,"on");
    surface(ax,terrainLon,terrainLat,zeros(size(elevation)),elevation, ...
        "FaceColor","texturemap","EdgeColor","none");
    colormap(ax,repmat(linspace(0.30,0.96,256).',1,3));
    clim(ax,elevationLimits); view(ax,2);
    current = views.(domains(panel));
    lat = rad2deg(current.candidates.latitudesRad(:));
    lon = wrapLongitude(rad2deg(current.candidates.longitudesRad(:)));
    counts(panel) = numel(lat);
    if panel>1
        % Only the displayed global points are thinned. The domain is unchanged.
        ids = (1:numel(lat)).';
        if panel==3 && numel(ids)>4000
            ids = unique(round(linspace(1,numel(lat),4000))).';
        end
        sampleIds{panel} = current.meta.sharedSourceCandidateIds(ids);
        shown(panel) = numel(ids);
        scatter3(ax,lon(ids),lat(ids),ones(numel(ids),1),3, ...
            style.blueColor,"filled","MarkerEdgeColor","none");
    else
        shown(panel) = counts(panel);
        sampleIds{panel} = current.meta.sharedSourceCandidateIds;
    end
    if panel==2
        for k = 1:heightTable(sites)
            [boundaryLat,boundaryLon] = circleCoordinates(siteLat(k),siteLon(k), ...
                100,database.config.moon.radiusKm);
            % Break longitude discontinuities instead of drawing across the map.
            jumps = [false abs(diff(boundaryLon))>180];
            boundaryLon(jumps) = NaN; boundaryLat(jumps) = NaN;
            plot3(ax,boundaryLon,boundaryLat,2*ones(size(boundaryLon)), ...
                "Color",style.blueColor,"LineWidth",1.1);
        end
    end
    for k = 1:heightTable(sites)
        color = style.sensorColor;
        if sites.Role(k)=="south_pole_option", color=style.blueColor; end
        scatter3(ax,siteLon(k),siteLat(k),3,90,color,"p","filled", ...
            "MarkerEdgeColor","white","LineWidth",0.8);
        if panel==1
            label = strrep(sites.SiteId(k),"BGM","BG-");
            if label=="IM3", label="IM-3"; end
            if label=="POLE_MOUTON", label="Mons Mouton"; end
            if label=="POLE_SCHRODINGER", label="Schr"+string(char(246))+"dinger Basin"; end
            tx = siteLon(k)+5; ty=siteLat(k)+7; align="left";
            if siteLon(k)<-150, tx=-165; ty=siteLat(k)+10; end
            if siteLat(k)<-65, ty=siteLat(k)+12; end
            if siteLon(k)>100, tx=siteLon(k)-5; align="right"; end
            text(ax,tx,ty,4,label,"HorizontalAlignment",align, ...
                "BackgroundColor","white","Margin",1,"Interpreter","none");
        end
    end
    xlim(ax,[-180 180]); ylim(ax,[-90 90]);
    xticks(ax,-180:60:180); yticks(ax,-90:30:90);
    xlabel(ax,"East longitude (deg)"); ylabel(ax,"Latitude (deg)");
    title(ax,titles(panel)); box(ax,"on"); grid(ax,"on");
    ax.Layer="top"; ax.GridColor=[0.35 0.35 0.35]; ax.GridAlpha=0.20;
end
cb = colorbar(axesHandles(3),"southoutside");
cb.Layout.Tile = "south"; cb.Label.String="Elevation (km)";
cb.Ticks = linspace(elevationLimits(1),elevationLimits(2),5);
cb.TickLabels = compose("%.1f",cb.Ticks);
setappdata(fig,"ManuscriptPlacementWidthInches",style.manuscriptWidthInches);
applyManuscriptTypography(fig,"geographic_design_domains.eps",width);
drawnow;
% Magnify one actual 100-km domain without changing the global map extent.
% Keep the inset labels clear of the BG-1 site marker to its left.
position = axesHandles(2).Position;
% A single opaque panel reserves room for every tick, label, and title.
insetBounds = [position(1)+0.70*position(3),position(2)+0.32*position(4), ...
    0.29*position(3),0.66*position(4)];
insetBackdrop = axes(fig,"Units","normalized","Position",insetBounds);
rectangle(insetBackdrop,"Position",[0 0 1 1],"FaceColor","white", ...
    "EdgeColor",[0.65 0.65 0.65],"LineWidth",0.5);
xlim(insetBackdrop,[0 1]); ylim(insetBackdrop,[0 1]); axis(insetBackdrop,"off");
inset = axes(fig,"Units","normalized","Position", ...
    [insetBounds(1)+0.27*insetBounds(3),insetBounds(2)+0.23*insetBounds(4), ...
    0.66*insetBounds(3),0.65*insetBounds(4)]);
hold(inset,"on");
anchor = 1;
membership = views.clps.config.domainComparison.anchorMembership(:,anchor);
lat = views.clps.candidates.latitudesRad(membership);
lon = views.clps.candidates.longitudesRad(membership);
phi = deg2rad(siteLat(anchor)); lambda = deg2rad(siteLon(anchor));
delta = lon-lambda;
a = sin((lat-phi)/2).^2+cos(lat).*cos(phi).*sin(delta/2).^2;
distance = 2*database.config.moon.radiusKm*asin(sqrt(min(1,max(0,a))));
bearing = atan2(sin(delta).*cos(lat),cos(phi).*sin(lat)-sin(phi).*cos(lat).*cos(delta));
scatter(inset,distance.*sin(bearing),distance.*cos(bearing),8,style.blueColor,"filled");
angle = linspace(0,2*pi,361);
plot(inset,100*sin(angle),100*cos(angle),"Color",style.blueColor,"LineWidth",1);
scatter(inset,0,0,55,style.sensorColor,"p","filled","MarkerEdgeColor","white");
axis(inset,"equal"); xlim(inset,[-115 115]); ylim(inset,[-115 115]);
xticks(inset,[-100 0 100]); yticks(inset,[-100 0 100]); box(inset,"on");
insetLabel = strrep(sites.SiteId(anchor),"IM3","IM-3");
title(inset,insetLabel+": 100-km region","FontSize",9);
xlabel(inset,"East (km)");
ylabel(inset,"North (km)");
set(findall(inset,"-property","FontName"),"FontName",style.fontName);
set(findall(inset,"-property","FontWeight"),"FontWeight","bold");
set(findall(inset,"-property","FontSize"),"FontSize",9);
setappdata(fig,"ManuscriptTypographyFinalized",true);
report = struct("pngFile",fullfile(outputDirectory,"geographic_design_domains.png"), ...
    "pdfFile",fullfile(outputDirectory,"geographic_design_domains.pdf"), ...
    "epsFile",fullfile(outputDirectory,"geographic_design_domains.eps"), ...
    "candidateCounts",counts,"displayedCounts",shown, ...
    "displayedMasterIds",{sampleIds},"activeSites",sites, ...
    "elevationLimitsKm",elevationLimits);
exportManuscriptFigure(fig,report.epsFile,width,height);
exportgraphics(fig,report.pngFile,"Resolution",300);
exportgraphics(fig,report.pdfFile,"ContentType","image","Resolution",300);
summary = table(domains.',counts,shown, ...
    'VariableNames',{'Domain','CandidateCount','DisplayedCount'});
writetable(summary,fullfile(outputDirectory,"domain_candidate_counts.csv"));
end

function longitude = wrapLongitude(longitude)
longitude = mod(longitude+180,360)-180;
end

function n = heightTable(t)
% Avoid collision with the figure-height variable in the main function.
n = size(t,1);
end

function [latitude,longitude] = circleCoordinates(lat,lon,radius,moonRadius)
bearing = linspace(0,2*pi,361);
phi = deg2rad(lat); lambda = deg2rad(lon); delta = radius/moonRadius;
p = asin(sin(phi)*cos(delta)+cos(phi)*sin(delta)*cos(bearing));
l = lambda+atan2(sin(bearing)*sin(delta)*cos(phi),cos(delta)-sin(phi)*sin(p));
latitude = rad2deg(p); longitude = wrapLongitude(rad2deg(l));
end

function file = resolvePlotInput(file,prompt,startFolder,repoRoot)
% Resolve relative paths from the current folder or repository root.
if strlength(file)>0
    if isfile(file), return, end
    rooted = fullfile(repoRoot,file);
    if isfile(rooted), file=rooted; return, end
end
if ~usejava("desktop")
    error("plotGeographicDesignDomains:MissingInput", ...
        "%s. File not found: '%s'. Current folder: %s. Supply an existing absolute path.", ...
        prompt,file,pwd);
end
if strlength(file)>0
    warning("plotGeographicDesignDomains:SelectInput", ...
        "File not found: %s. Select the actual file in the dialog.",file);
end
if ~isfolder(startFolder), startFolder=repoRoot; end
[name,folder] = uigetfile({'*.mat','MAT-files (*.mat)'},char(prompt), ...
    char(startFolder+filesep));
if isequal(name,0)
    error("plotGeographicDesignDomains:SelectionCancelled", ...
        "%s. File selection was cancelled.",prompt);
end
file = string(fullfile(folder,name));
end

function plotInfo = plotDesignRsoFamilyMcrf(campaign,userConfig)
% PLOTDESIGNRSOFAMILYMCRF Plot separated design RSO trajectories in MCRF.
%
% The complete propagated design population is transformed from MCI into the
% Moon-centered rotating frame (MCRF). Each RSO is shown in its own 3D tile
% so individual trajectory geometry remains visible instead of being obscured
% by an overlaid 20-trajectory plot.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
database = campaign.database;
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

times = double(database.truth.times(:));
statesMci = double(database.truth.stateHistories);
numberOfObjects = size(statesMci,3);
assert(size(statesMci,1)==6 && size(statesMci,2)==numel(times), ...
    "Truth-state history dimensions are inconsistent.");

moonRadiusKm = double(database.config.moon.radiusKm);
theta0Rad = double(database.config.moon.theta0Rad);
angularRateRadS = 2*pi/double(database.config.moon.siderealPeriodSeconds);

maximumSamples = 300;
sampleIndices = unique(round(linspace(1,numel(times), ...
    min(maximumSamples,numel(times)))));
sampleTimes = times(sampleIndices);
numberOfSamples = numel(sampleIndices);

positionsMcrfKm = zeros(3,numberOfSamples,numberOfObjects);
for objectIndex = 1:numberOfObjects
    for sampleIndex = 1:numberOfSamples
        stateMcrf = referenceFrames.moonRotating( ...
            statesMci(:,sampleIndices(sampleIndex),objectIndex), ...
            sampleTimes(sampleIndex),theta0Rad,angularRateRadS, ...
            "fromInertial");
        positionsMcrfKm(:,sampleIndex,objectIndex) = stateMcrf(1:3);
    end
end

scaleKm = 1e3;
positions = positionsMcrfKm/scaleKm;
moonRadius = moonRadiusKm/scaleKm;

numberOfColumns = 4;
numberOfRows = ceil(numberOfObjects/numberOfColumns);

fig = figure("Name","Design RSO family in MCRF", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 10.0 9.4],"Renderer","opengl");
layout = tiledlayout(fig,numberOfRows,numberOfColumns, ...
    "Padding","compact","TileSpacing","compact");

[sx,sy,sz] = sphere(36);

for objectIndex = 1:numberOfObjects
    ax = nexttile(layout,objectIndex);
    hold(ax,"on");

    surf(ax,moonRadius*sx,moonRadius*sy,moonRadius*sz, ...
        "FaceColor",style.moonColor,"EdgeColor","none", ...
        "FaceAlpha",0.82);

    trajectory = positions(:,:,objectIndex);
    plot3(ax,trajectory(1,:),trajectory(2,:),trajectory(3,:), ...
        "-","Color",style.blueColor,"LineWidth",1.35);
    scatter3(ax,trajectory(1,1),trajectory(2,1),trajectory(3,1),24, ...
        style.redColor,"filled","MarkerEdgeColor",[1 1 1], ...
        "LineWidth",0.45);

    localExtent = max(abs(trajectory),[],"all");
    plotLimit = 1.07*max(localExtent,1.25*moonRadius);
    xlim(ax,[-plotLimit plotLimit]);
    ylim(ax,[-plotLimit plotLimit]);
    zlim(ax,[-plotLimit plotLimit]);

    axis(ax,"equal");
    axis(ax,"vis3d");
    grid(ax,"off");
    box(ax,"on");
    view(ax,38,24);

    title(ax,sprintf("RSO %02d",objectIndex), ...
        "FontName",style.fontName,"FontSize",10, ...
        "FontWeight","bold");

    ax.FontName = style.fontName;
    ax.FontSize = 7;
    ax.FontWeight = "bold";
    ax.LineWidth = 0.75;
    ax.TickDir = "out";
end

title(layout,"Design RSO trajectories in MCRF (coordinates in 10^3 km)", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");

outputFile = fullfile(outputDirectory,"design_rso_family_mcrf_3d.eps");
exportManuscriptFigure(fig,string(outputFile),10.0,9.4);

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.numberOfObjects = numberOfObjects;
plotInfo.frame = "MCRF";
plotInfo.timeSpanHours = (times(end)-times(1))/3600;
plotInfo.layout = [numberOfRows numberOfColumns];

fprintf("Design-RSO MCRF family subplot figure:\n  %s\n",outputFile);
end

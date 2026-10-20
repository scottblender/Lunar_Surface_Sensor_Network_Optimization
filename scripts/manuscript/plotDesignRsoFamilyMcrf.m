function plotInfo = plotDesignRsoFamilyMcrf(campaign,userConfig)
% PLOTDESIGNRSOFAMILYMCRF Plot separated design RSO trajectories in MCRF.
%
% One period of each design orbit is transformed from MCI into the
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

% Follow tests/testRsoGeneration.m: one smoothly sampled orbital period
% per object, rather than overlapping revolutions across the full campaign.
moonMu = double(database.config.moon.muKm3S2);
numberOfSamples = 501;
positionsMcrfKm = zeros(3,numberOfSamples,numberOfObjects);
periods = zeros(numberOfObjects,1);
for objectIndex = 1:numberOfObjects
    initialState = statesMci(:,1,objectIndex);
    radius = norm(initialState(1:3));
    energy = dot(initialState(4:6),initialState(4:6))/2-moonMu/radius;
    assert(energy<0,"The orbit-family display requires bound lunar orbits.");
    semiMajorAxis = -moonMu/(2*energy);
    periods(objectIndex) = 2*pi*sqrt(semiMajorAxis^3/moonMu);
    elapsedTimes = linspace(0,periods(objectIndex),numberOfSamples).';
    [~,states] = orbitDynamics.propagateLunarOrbit( ...
        initialState,elapsedTimes,"moonMu",moonMu);
    for sampleIndex = 1:numberOfSamples
        rotatingState = referenceFrames.moonRotating(states(sampleIndex,:).', ...
            times(1)+elapsedTimes(sampleIndex),theta0Rad,angularRateRadS,"fromInertial");
        positionsMcrfKm(:,sampleIndex,objectIndex) = rotatingState(1:3);
    end
end

scaleKm = 1e3;
positions = positionsMcrfKm/scaleKm;
moonRadius = moonRadiusKm/scaleKm;

numberOfColumns = min(4,numberOfObjects);
numberOfRows = ceil(numberOfObjects/numberOfColumns);

outerMargin = 0.6;
figureWidth = 2.9*numberOfColumns+2*outerMargin;
figureHeight = 3.2*numberOfRows+2*outerMargin;
fig = figure("Name","Design RSO family in MCRF", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 figureWidth figureHeight],"Renderer","opengl");
% Fixed inner boxes preserve the trajectory area independently of tick extents.
% The physical cell geometry is identical for every object.
cellWidth = (figureWidth-2*outerMargin)/numberOfColumns;
cellHeight = (figureHeight-2*outerMargin)/numberOfRows;
plotSide = 0.65*min(cellWidth,cellHeight);

[sx,sy,sz] = sphere(36);

% Use the bottom-left tile as the single labeled coordinate reference.
representativeObjectIndex = (numberOfRows-1)*numberOfColumns+1;

for objectIndex = 1:numberOfObjects
    column = mod(objectIndex-1,numberOfColumns);
    row = floor((objectIndex-1)/numberOfColumns);
    left = outerMargin + column*cellWidth + (cellWidth-plotSide)/2;
    bottom = outerMargin + (numberOfRows-row-1)*cellHeight + 0.22*cellHeight;
    ax = axes(fig,"Units","inches", ...
        "Position",[left bottom plotSide plotSide], ...
        "PositionConstraint","innerposition");
    ax.Tag = "designRsoTrajectory";
    hold(ax,"on");

    surf(ax,moonRadius*sx,moonRadius*sy,moonRadius*sz, ...
        "FaceColor",style.moonColor,"EdgeColor","none", ...
        "FaceAlpha",0.82);

    trajectory = positions(:,:,objectIndex);
    plot3(ax,trajectory(1,:),trajectory(2,:),trajectory(3,:), ...
        "-","Color",style.blueColor,"LineWidth",1.8);
    scatter3(ax,trajectory(1,1),trajectory(2,1),trajectory(3,1),24, ...
        style.redColor,"filled","MarkerEdgeColor",[1 1 1], ...
        "LineWidth",0.45);

    % Equal-sized plot boxes, with independent limits to reveal each orbit.
    localLimit = 1.08*max(moonRadius,max(abs(trajectory),[],"all"));
    xlim(ax,[-localLimit localLimit]);
    ylim(ax,[-localLimit localLimit]);
    zlim(ax,[-localLimit localLimit]);
    daspect(ax,[1 1 1]);
    pbaspect(ax,[1 1 1]);
    ax.CameraViewAngleMode = "auto";
    ax.Projection = "orthographic";
    grid(ax,"off");
    box(ax,"off");
    view(ax,35,25);


    ax.FontName = style.fontName;
    ax.FontSize = style.manuscriptFontSize*figureWidth/style.manuscriptWidthInches;
    ax.FontWeight = "bold";
    ax.LineWidth = 0.75;
    ax.TickDir = "out";

    % A positive scale tick on each axis is sufficient for the symmetric
    % cube; avoid six repeated, rotated numbers surrounding every orbit.
    tickLimit = 0.80*localLimit;
    xticks(ax,tickLimit);
    yticks(ax,tickLimit);
    zticks(ax,tickLimit);
    ax.XTickLabelRotation = 0;
    ax.YTickLabelRotation = 0;
    ax.ZTickLabelRotation = 0;
    xtickformat(ax,"%.1f");
    ytickformat(ax,"%.1f");
    ztickformat(ax,"%.1f");
    ax.XAxis.Exponent = 0;
    ax.YAxis.Exponent = 0;
    ax.ZAxis.Exponent = 0;

    if objectIndex == representativeObjectIndex
        xlabel(ax,"x_R");
        ylabel(ax,"y_R");
        zlabel(ax,"z_R");
        ax.XLabel.FontSize = 30;
        ax.YLabel.FontSize = 30;
        ax.ZLabel.FontSize = 30;
        ax.XLabel.FontWeight = "bold";
        ax.YLabel.FontWeight = "bold";
        ax.ZLabel.FontWeight = "bold";
    else
        xlabel(ax,"");
        ylabel(ax,"");
        zlabel(ax,"");
    end

    if ~isempty(ax.Toolbar), ax.Toolbar.Visible = "off"; end
end

outputFile = fullfile(outputDirectory,"design_rso_family_mcrf_3d.eps");
% Preserve the explicitly tuned RSO-family typography during EPS export.
setappdata(fig,"ManuscriptTypographyFinalized",true);
exportManuscriptFigure(fig,string(outputFile),figureWidth,figureHeight);

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.numberOfObjects = numberOfObjects;
plotInfo.frame = "MCRF";
plotInfo.periodHours = periods/3600;
plotInfo.displayInterval = "one orbital period per RSO";
plotInfo.layout = [numberOfRows numberOfColumns];

fprintf("Design-RSO MCRF family subplot figure:\n  %s\n",outputFile);
end

function plotInfo = plotDesignRsoFamilyMcrf(campaign,userConfig)
% PLOTDESIGNRSOFAMILYMCRF Plot the complete design RSO population in MCRF.
%
% The full three-day propagated design population is transformed from the
% Moon-centered inertial frame to the Moon-centered rotating frame (MCRF).
% This figure is the manuscript-facing geometric summary of the 20-object
% optimization population; the exact orbital elements remain available in
% campaign.database.rso.catalog.

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
orbitColors = turbo(numberOfObjects);

fig = figure("Name","Design RSO family in MCRF", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 8.5 7.2],"Renderer","opengl");
ax = axes(fig,"Units","normalized","Position",[0.11 0.12 0.73 0.82]);
hold(ax,"on");

[sx,sy,sz] = sphere(64);
surf(ax,moonRadius*sx,moonRadius*sy,moonRadius*sz, ...
    "FaceColor",style.moonColor,"EdgeColor","none","FaceAlpha",0.80);

for objectIndex = 1:numberOfObjects
    trajectory = positions(:,:,objectIndex);
    plot3(ax,trajectory(1,:),trajectory(2,:),trajectory(3,:), ...
        "-","Color",orbitColors(objectIndex,:),"LineWidth",1.35);
    scatter3(ax,trajectory(1,1),trajectory(2,1),trajectory(3,1),22, ...
        orbitColors(objectIndex,:),"filled","MarkerEdgeColor",[1 1 1], ...
        "LineWidth",0.45);
end

axis(ax,"equal");
axis(ax,"vis3d");
grid(ax,"off");
box(ax,"on");
view(ax,38,24);
xlabel(ax,"x_{MCRF} (10^3 km)","Interpreter","tex");
ylabel(ax,"y_{MCRF} (10^3 km)","Interpreter","tex");
zlabel(ax,"z_{MCRF} (10^3 km)","Interpreter","tex");
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 1.0;
ax.TickDir = "out";
ax.XLabel.FontSize = style.labelFontSize;
ax.YLabel.FontSize = style.labelFontSize;
ax.ZLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontWeight = "bold";
ax.ZLabel.FontWeight = "bold";

maximumExtent = max(abs(positions),[],"all");
plotLimit = 1.05*maximumExtent;
xlim(ax,[-plotLimit plotLimit]);
ylim(ax,[-plotLimit plotLimit]);
zlim(ax,[-plotLimit plotLimit]);

colormap(ax,orbitColors);
clim(ax,[0.5 numberOfObjects+0.5]);
cb = colorbar(ax);
cb.FontName = style.fontName;
cb.FontSize = style.axisFontSize;
cb.FontWeight = "bold";
cb.Label.String = "RSO index";
cb.Label.FontSize = style.labelFontSize;
cb.Label.FontWeight = "bold";
cb.Ticks = unique([1,5:5:numberOfObjects,numberOfObjects]);

outputFile = fullfile(outputDirectory,"design_rso_family_mcrf_3d.eps");
exportManuscriptFigure(fig,string(outputFile),8.5,7.2);

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.numberOfObjects = numberOfObjects;
plotInfo.frame = "MCRF";
plotInfo.timeSpanHours = (times(end)-times(1))/3600;

fprintf("Design-RSO MCRF family figure:\n  %s\n",outputFile);
end

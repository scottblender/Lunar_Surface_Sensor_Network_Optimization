function outputs = generateStudyDefinitionFigures(userConfig)
% GENERATESTUDYDEFINITIONFIGURES - Export reference-frame, measurement, and exclusion schematics.
% Set definitionPlots to any subset of ["frames","measurements","exclusion"].

arguments
    userConfig (1,1) struct = struct()
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
defaults = struct("outputDirectory",fullfile(root,"results","manuscript_artifacts"), ...
    "definitionPlots",["frames","measurements","exclusion"]);
config = utilities.overrideConfig(defaults,userConfig);
selection = string(config.definitionPlots);
assert(all(ismember(selection,["frames","measurements","exclusion"])), ...
    "generateStudyDefinitionFigures:UnknownPlot","Unknown definition plot group.");
outputDirectory = string(config.outputDirectory);
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
style = publicationPlotStyle();
outputs = strings(0,1);
for group = selection(:).'
    switch group
        case "frames"
            files = drawReferenceFrames(outputDirectory,style);
        case "measurements"
            files = drawMeasurementGeometry(outputDirectory,style);
        case "exclusion"
            files = drawExclusionGeometry(outputDirectory,style);
    end
    outputs = [outputs;files(:)]; %#ok<AGROW>
end
end

function files = drawReferenceFrames(outputDirectory,style)
fontName = style.fontName;
axisLabelFontSize = 16;
annotationFontSize = 13;
rsoMarkerArea = 360;
backgroundColor = style.backgroundColor;
textColor = style.textColor;
labelBackgroundColor = style.labelBackgroundColor;
moonColor = style.moonColor;
moonEdgeColor = style.moonEdgeColor;
mciColor = style.blueColor;
mrColor = style.orangeColor;
angleColor = [0.66 0.45 0.00];
eastColor = style.greenColor;
northColor = style.blueColor;
upColor = style.orangeColor;
relativePositionColor = style.magentaColor;
sensorColor = style.redColor;

exportWidthInches = 6.50;
exportHeightInches = 6.50;

moonCenteredFile = fullfile(outputDirectory,"reference_frame_moon_centered.eps");
sensorCenteredFile = fullfile(outputDirectory,"reference_frame_sensor_centered.eps");

circleAngle = linspace(0,2*pi,500);
theta = deg2rad(35);

%% Moon-centered MCI / MR figure

figMoon = figure("Name","Reference frames: MCI and MR", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 exportWidthInches exportHeightInches],"Renderer","opengl");
axMoon = axes(figMoon,"Position",[0.06 0.06 0.88 0.88]);
hold(axMoon,"on");
axis(axMoon,"equal");
axis(axMoon,"off");
axMoon.Color = backgroundColor;
xlim(axMoon,[-1.35 1.35]);
ylim(axMoon,[-1.35 1.35]);

origin = [0;-0.05];
moonRadius = 0.72;
fill(axMoon,origin(1)+moonRadius*cos(circleAngle), ...
    origin(2)+moonRadius*sin(circleAngle),moonColor, ...
    "EdgeColor",moonEdgeColor,"LineWidth",1.0);

axisLength = 1.08;
xI = [1;0];
yI = [0;1];
xR = [cos(theta);sin(theta)];
yR = [-sin(theta);cos(theta)];

drawArrow2D(axMoon,origin,origin+axisLength*xI,mciColor,2.2,0.085,0.065,"-");
drawArrow2D(axMoon,origin,origin+axisLength*yI,mciColor,2.2,0.085,0.065,"-");
drawArrow2D(axMoon,origin,origin+axisLength*xR,mrColor,2.2,0.085,0.065,"--");
drawArrow2D(axMoon,origin,origin+axisLength*yR,mrColor,2.2,0.085,0.065,"--");

text(axMoon,origin(1)+1.20,origin(2),"x_I", ...
    "Interpreter","tex","Color",mciColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");
text(axMoon,origin(1),origin(2)+1.20,"y_I", ...
    "Interpreter","tex","Color",mciColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");
text(axMoon,origin(1)+1.21*xR(1),origin(2)+1.21*xR(2),"x_R", ...
    "Interpreter","tex","Color",mrColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");
text(axMoon,origin(1)+1.21*yR(1),origin(2)+1.21*yR(2),"y_R", ...
    "Interpreter","tex","Color",mrColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");

plot(axMoon,origin(1),origin(2),"o","MarkerSize",9, ...
    "MarkerFaceColor",backgroundColor,"MarkerEdgeColor",textColor,"LineWidth",1.1);
plot(axMoon,origin(1),origin(2),".","Color",textColor,"MarkerSize",11);
text(axMoon,origin(1)-0.08,origin(2)-0.13,"z_I=z_R", ...
    "Interpreter","tex","Color",textColor,"FontName",fontName, ...
    "FontSize",annotationFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

angleRadius = 0.37;
angleValues = linspace(0,theta,100);
anglePoints = origin + angleRadius*[cos(angleValues);sin(angleValues)];
plot(axMoon,anglePoints(1,:),anglePoints(2,:),"Color",angleColor,"LineWidth",2.0);
drawArrowHead2D(axMoon,anglePoints(:,end),[-sin(theta);cos(theta)],angleColor,0.065,0.055);
angleLabel = origin + 0.49*[cos(theta/2);sin(theta/2)] + [0.16;0];
text(axMoon,angleLabel(1),angleLabel(2),"\theta(t)", ...
    "Interpreter","tex","Color",angleColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

%% Sensor-centered ENU figure

figSensor = figure("Name","Reference frames: local ENU", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[8 1 exportWidthInches exportHeightInches],"Renderer","opengl");
axSensor = axes(figSensor,"Position",[0.06 0.06 0.88 0.88]);
hold(axSensor,"on");
axis(axSensor,"equal");
axis(axSensor,"off");
axSensor.Color = backgroundColor;
xlim(axSensor,[-1.35 1.35]);
ylim(axSensor,[-0.55 1.55]);

localMoonRadius = 1.22;
localMoonCenter = [0;-1.14];
fill(axSensor,localMoonCenter(1)+localMoonRadius*cos(circleAngle), ...
    localMoonCenter(2)+localMoonRadius*sin(circleAngle),moonColor, ...
    "EdgeColor",moonEdgeColor,"LineWidth",1.0);

sensorPosition = [0;localMoonCenter(2)+localMoonRadius];
scatter(axSensor,sensorPosition(1),sensorPosition(2),62,"o", ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
text(axSensor,sensorPosition(1)-0.12,sensorPosition(2)-0.16,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

plot(axSensor,[localMoonCenter(1),sensorPosition(1)], ...
    [localMoonCenter(2),sensorPosition(2)],":", ...
    "Color",style.grayColor,"LineWidth",1.1);
text(axSensor,sensorPosition(1)+0.08,sensorPosition(2)-0.43,"r_{s,R}", ...
    "Interpreter","tex","Color",style.grayColor,"FontName",fontName, ...
    "FontSize",annotationFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin);

E = [1;0];
N = [-0.72;0.55]; N = N/norm(N);
U = [0;1];
localAxisLength = 0.58;

drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*E, ...
    eastColor,2.2,0.070,0.058,"-");
drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*N, ...
    northColor,2.2,0.070,0.058,"-");
drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*U, ...
    upColor,2.2,0.070,0.058,"-");

text(axSensor,sensorPosition(1)+0.70,sensorPosition(2),"E", ...
    "Color",eastColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold");
text(axSensor,sensorPosition(1)+0.70*N(1),sensorPosition(2)+0.70*N(2),"N", ...
    "Color",northColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold");
text(axSensor,sensorPosition(1),sensorPosition(2)+0.70,"U", ...
    "Color",upColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "HorizontalAlignment","center");

rsoPosition = [0.95;1.15];
drawArrow2D(axSensor,sensorPosition,rsoPosition,relativePositionColor,2.4,0.095,0.065,"-");
scatter(axSensor,rsoPosition(1),rsoPosition(2),rsoMarkerArea,"p", ...
    "MarkerFaceColor",relativePositionColor,"MarkerEdgeColor",relativePositionColor,"LineWidth",1.2);
text(axSensor,rsoPosition(1)+0.12,rsoPosition(2)+0.04,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin);

rho = rsoPosition-sensorPosition;
rhoNormal = [-rho(2);rho(1)]/norm(rho);
rhoLabel = sensorPosition + 0.58*rho + 0.10*rhoNormal;
text(axSensor,rhoLabel(1),rhoLabel(2),"\rho_R", ...
    "Interpreter","tex","Color",relativePositionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

%% Export

moonFig = ancestor(axMoon,"figure"); moonFig.Units = "inches";
sensorFig = ancestor(axSensor,"figure"); sensorFig.Units = "inches";
exportManuscriptFigure(moonFig,string(moonCenteredFile),moonFig.Position(3),moonFig.Position(4));
exportManuscriptFigure(sensorFig,string(sensorCenteredFile),sensorFig.Position(3),sensorFig.Position(4));

fprintf("Saved reference-frame figures.\n");

%% Local helpers
files = [string(moonCenteredFile);string(sensorCenteredFile)];
end

function files = drawMeasurementGeometry(outputDirectory,style)
fontName = style.fontName;
axisLabelFontSize = style.labelFontSize;
annotationFontSize = style.annotationFontSize;
rsoMarkerArea = 360;

backgroundColor = style.backgroundColor;
moonColor = style.moonColor;
moonEdgeColor = style.moonEdgeColor;
axisColor = style.blueColor;
projectionColor = style.grayColor;
losColor = style.magentaColor;
raColor = style.orangeColor;
decColor = style.greenColor;
sensorColor = style.redColor;
textColor = style.textColor;
labelBackgroundColor = style.labelBackgroundColor;

exportWidthInches = 6.80;
exportHeightInches = 6.80;

rightAscensionFile = fullfile(outputDirectory,"angles_only_right_ascension_geometry.eps");
declinationFile = fullfile(outputDirectory,"angles_only_declination_geometry.eps");

alpha = deg2rad(38);
delta = deg2rad(32);

%% Right ascension

figRa = figure("Name","Angles-only: right ascension", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 exportWidthInches exportHeightInches],"Renderer","opengl");
axRa = axes(figRa,"Position",[0.06 0.06 0.88 0.88]);
hold(axRa,"on");
axis(axRa,"equal");
axis(axRa,"off");
axRa.Color = backgroundColor;
axRa.FontName = fontName;
xlim(axRa,[-1.25 1.55]);
ylim(axRa,[-1.10 1.55]);

sensor = [-0.58;-0.48];
axisLength = 1.35;
projectionLength = 2.05;
projectionEnd = sensor + projectionLength*[cos(alpha);sin(alpha)];

scatter(axRa,sensor(1),sensor(2),70,"o", ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor, ...
    "LineWidth",1.0);
text(axRa,sensor(1)-0.10,sensor(2)-0.24,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","center","VerticalAlignment","top", ...
    "Clipping","off");

drawArrow2D(axRa,sensor,sensor+[axisLength;0],axisColor,2.1,0.095,0.070,"-");
drawArrow2D(axRa,sensor,sensor+[0;axisLength],axisColor,2.1,0.095,0.070,"-");
text(axRa,sensor(1)+axisLength+0.15,sensor(2),"x_I", ...
    "Interpreter","tex","Color",axisColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold");
text(axRa,sensor(1),sensor(2)+axisLength+0.15,"y_I", ...
    "Interpreter","tex","Color",axisColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "HorizontalAlignment","center");

drawArrow2D(axRa,sensor,projectionEnd,projectionColor,2.6,0.12,0.085,"-");
normal = [-sin(alpha);cos(alpha)];
labelPosition = sensor + 0.54*projectionLength*[cos(alpha);sin(alpha)] + 0.36*normal;
text(axRa,labelPosition(1),labelPosition(2),"\rho_{xy,k}", ...
    "Interpreter","tex","Color",projectionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

scatter(axRa,projectionEnd(1),projectionEnd(2),rsoMarkerArea,"p", ...
    "MarkerFaceColor",losColor,"MarkerEdgeColor",losColor,"LineWidth",1.2);
text(axRa,projectionEnd(1),projectionEnd(2)+0.19,"RSO projection", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","center","VerticalAlignment","bottom");

arcRadius = 0.67;
arcValues = linspace(0,alpha,100);
arcPoints = sensor + arcRadius*[cos(arcValues);sin(arcValues)];
plot(axRa,arcPoints(1,:),arcPoints(2,:),"Color",raColor,"LineWidth",2.5);
drawArrowHead2D(axRa,arcPoints(:,end),[-sin(alpha);cos(alpha)],raColor,0.075,0.060);
angleLabel = sensor + 0.94*[cos(alpha/2);sin(alpha/2)];
text(axRa,angleLabel(1),angleLabel(2),"\alpha_k", ...
    "Interpreter","tex","Color",raColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

%% Declination

figDec = figure("Name","Angles-only: declination", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[8 1 exportWidthInches exportHeightInches],"Renderer","opengl");
axDec = axes(figDec,"Position",[0.06 0.06 0.88 0.88]);
hold(axDec,"on");
axis(axDec,"equal");
axis(axDec,"off");
axDec.Color = backgroundColor;
axDec.FontName = fontName;
xlim(axDec,[-1.90 1.90]);
ylim(axDec,[-1.82 1.98]);

moonRadius = 1.03;
moonCenter = [-0.72;-0.66];
sensor = moonCenter + [0;moonRadius];
projectionLength = 2.18;
projectionEnd = sensor + [projectionLength;0];
rsoPosition = projectionEnd + [0;projectionLength*tan(delta)];

circleValues = linspace(0,2*pi,500);
fill(axDec,moonCenter(1)+moonRadius*cos(circleValues), ...
    moonCenter(2)+moonRadius*sin(circleValues),moonColor, ...
    "EdgeColor",moonEdgeColor,"LineWidth",1.1);

scatter(axDec,sensor(1),sensor(2),72,"o", ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
text(axDec,sensor(1)-0.06,sensor(2)-0.18,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","top", ...
    "Clipping","off");

drawArrow2D(axDec,sensor,sensor+[0;0.92],axisColor,2.1,0.095,0.070,"-");
text(axDec,sensor(1),sensor(2)+1.08,"z_I", ...
    "Interpreter","tex","Color",axisColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");

plot(axDec,[sensor(1),projectionEnd(1)+0.09],[sensor(2),projectionEnd(2)], ...
    "--","Color",projectionColor,"LineWidth",1.6);
plot(axDec,[projectionEnd(1),rsoPosition(1)],[projectionEnd(2)-0.09,rsoPosition(2)], ...
    ":","Color",projectionColor,"LineWidth",1.4);
text(axDec,sensor(1)+0.50*projectionLength,sensor(2)-0.24,"\rho_{xy,k}", ...
    "Interpreter","tex","Color",projectionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

drawArrow2D(axDec,sensor,rsoPosition,losColor,2.8,0.12,0.085,"-");
losVector = rsoPosition-sensor;
losNormal = [-losVector(2);losVector(1)]/norm(losVector);
losLabelPosition = sensor + 0.56*losVector + 0.34*losNormal;
text(axDec,losLabelPosition(1),losLabelPosition(2),"\rho_{I,k}", ...
    "Interpreter","tex","Color",losColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

scatter(axDec,rsoPosition(1),rsoPosition(2),rsoMarkerArea,"p", ...
    "MarkerFaceColor",losColor,"MarkerEdgeColor",losColor,"LineWidth",1.2);
text(axDec,rsoPosition(1)-0.42,rsoPosition(2)+0.04,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","middle");

arcRadius = 0.78;
arcValues = linspace(0,delta,100);
arcPoints = sensor + arcRadius*[cos(arcValues);sin(arcValues)];
plot(axDec,arcPoints(1,:),arcPoints(2,:),"Color",decColor,"LineWidth",2.5);
drawArrowHead2D(axDec,arcPoints(:,end),[-sin(delta);cos(delta)],decColor,0.075,0.060);
angleLabel = sensor + 1.08*[cos(delta/2);sin(delta/2)];
text(axDec,angleLabel(1),angleLabel(2),"\delta_k", ...
    "Interpreter","tex","Color",decColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

%% Export

exportImageEps(axRa,rightAscensionFile,backgroundColor);
exportImageEps(axDec,declinationFile,backgroundColor);

fprintf("Saved angles-only geometry figures.\n");

%% Local helpers
files = [string(rightAscensionFile);string(declinationFile)];
end

function files = drawExclusionGeometry(outputDirectory,style)
% DRAWEXCLUSIONGEOMETRY - Plot Sun/Earth occultation and sensor keep-out geometry.
% The shaded gray cone shows physical occultation; pale orange adds the
% prescribed keep-out region. Angles are measured from the body-center ray.
fontName = style.fontName;
objectFontSize = 15;
angleFontSize = 15;
labelBackgroundColor = [1 1 1];
labelMargin = 2.0;
backgroundColor = style.backgroundColor;
textColor = style.textColor;

sensorColor = style.redColor;
targetColor = style.magentaColor;
bodyColor = [0.83 0.84 0.86];
occultationColor = style.grayColor;
minimumAngleColor = style.orangeColor;
targetAngleColor = style.blueColor;
lineOfSightColor = style.blueColor;
bodyDirectionColor = [0.62 0.62 0.64];
% Use opaque, print-safe pale fills instead of alpha-dependent EPS fills.
occultationShade = [0.94 0.94 0.95];
exclusionShade = [0.99 0.95 0.89];

sensor = [-2.20,-0.05];
body = [0.85,-0.05];
bodyRadius = 0.58;
bodyRange = norm(body-sensor);
thetaOcc = asin(bodyRadius/bodyRange);
thetaMin = deg2rad(20);
thetaRequired = max(thetaOcc,thetaMin);
thetaTarget = thetaRequired + deg2rad(10);
targetRange = 3.75;
target = sensor + targetRange*[cos(thetaTarget),sin(thetaTarget)];

figureWidth = 7.0;
figureHeight = 4.4;
fig = figure("Name","Celestial-body exclusion constraint", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 figureWidth figureHeight],"Renderer","opengl");
ax = axes(fig,"Units","normalized","Position",[0.045 0.07 0.91 0.87]);
hold(ax,"on");
axis(ax,"equal");
axis(ax,"off");
ax.Color = backgroundColor;

% Draw exclusion regions first so boundaries and the LOS remain crisp.
sectorRadius = 3.75;
occultationAngles = linspace(-thetaOcc,thetaOcc,240);
patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(occultationAngles),sensor(1)], ...
    [sensor(2),sensor(2)+sectorRadius*sin(occultationAngles),sensor(2)], ...
    occultationShade,"EdgeColor","none");
if thetaRequired > thetaOcc
    for signValue = [-1 1]
        excludedAngles = linspace(signValue*thetaOcc, ...
            signValue*thetaRequired,160);
        patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(excludedAngles),sensor(1)], ...
            [sensor(2),sensor(2)+sectorRadius*sin(excludedAngles),sensor(2)], ...
            exclusionShade,"EdgeColor","none");
    end
end

% Body, center ray, occultation tangents, and keep-out boundaries.
bodyAngle = linspace(0,2*pi,300);
fill(ax,body(1)+bodyRadius*cos(bodyAngle), ...
    body(2)+bodyRadius*sin(bodyAngle),bodyColor, ...
    "EdgeColor",style.moonEdgeColor,"LineWidth",1.0);
plot(ax,[sensor(1),body(1)],[sensor(2),body(2)], ...
    ":","Color",bodyDirectionColor,"LineWidth",1.0);

boundaryLength = 3.75;
for signValue = [-1 1]
    pointOcc = sensor + boundaryLength* ...
        [cos(signValue*thetaOcc),sin(signValue*thetaOcc)];
    plot(ax,[sensor(1),pointOcc(1)],[sensor(2),pointOcc(2)], ...
        ":","Color",occultationColor,"LineWidth",1.0);
    pointMin = sensor + boundaryLength* ...
        [cos(signValue*thetaRequired),sin(signValue*thetaRequired)];
    plot(ax,[sensor(1),pointMin(1)],[sensor(2),pointMin(2)], ...
        "--","Color",minimumAngleColor,"LineWidth",1.5);
end

% An unobstructed target LOS is the primary line in the schematic.
plot(ax,[sensor(1),target(1)],[sensor(2),target(2)], ...
    "-","Color",lineOfSightColor,"LineWidth",2.0);
plot(ax,sensor(1),sensor(2),"o","MarkerSize",8, ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor, ...
    "LineWidth",0.8);
plot(ax,target(1),target(2),"p","MarkerSize",11, ...
    "MarkerFaceColor",targetColor,"MarkerEdgeColor",targetColor, ...
    "LineWidth",0.9);

% Disjoint annotation arcs measured from the body-center reference ray.
drawAngleArc(ax,sensor,0,thetaOcc,0.77,occultationColor,1.3);
drawAngleArc(ax,sensor,0,thetaRequired,1.44,minimumAngleColor,1.5);
drawAngleArc(ax,sensor,0,thetaTarget,2.05,targetAngleColor,1.7);

% Use consistent object-label typography and unobstructed placements.
text(ax,-2.66,-0.61,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","normal","HorizontalAlignment","left", ...
    "VerticalAlignment","top", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);
text(ax,target(1)+0.13,target(2)+0.02,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","normal","HorizontalAlignment","left", ...
    "VerticalAlignment","middle", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);
text(ax,body(1),body(2)-bodyRadius-0.27,"Celestial body {\it b}", ...
    "Interpreter","tex","Color",textColor,"FontName",fontName, ...
    "FontSize",objectFontSize,"FontWeight","normal", ...
    "HorizontalAlignment","center","VerticalAlignment","middle", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);

% Separate mathematical labels from both one another and the plotted rays.
text(ax,-1.42,-0.47,"$\theta_{\mathrm{occ},b}$", ...
    "Interpreter","latex","Color",occultationColor, ...
    "FontSize",angleFontSize,"HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);
text(ax,-1.18,0.84,"$\theta_{\min,b}$", ...
    "Interpreter","latex","Color",minimumAngleColor, ...
    "FontSize",angleFontSize,"HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);
text(ax,-0.35,1.48,"$\theta_b$", ...
    "Interpreter","latex","Color",targetAngleColor, ...
    "FontSize",angleFontSize,"HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "BackgroundColor",labelBackgroundColor,"Margin",labelMargin);

xlim(ax,[-3.00 2.65]);
ylim(ax,[-1.50 2.35]);
ax.LooseInset = max(ax.TightInset,0.005);

outputFile = fullfile(outputDirectory,"Exclusion_Constraint_Schematic.eps");
fig.InvertHardcopy = "off";
fig.PaperUnits = "inches";
fig.PaperSize = [figureWidth figureHeight];
fig.PaperPosition = [0 0 figureWidth figureHeight];
fig.PaperPositionMode = "manual";
drawnow;
setappdata(fig,"ManuscriptTypographyFinalized",true);
exportManuscriptFigure(fig,string(outputFile),figureWidth,figureHeight);

fprintf("Saved exclusion-constraint schematic:\n  %s\n",outputFile);
files = string(outputFile);
end

function exportImageEps(ax,outputFile,backgroundColor)
fig = ancestor(ax,"figure");
fig.Color = backgroundColor;
fig.Units = "inches";
exportManuscriptFigure(fig,string(outputFile),fig.Position(3),fig.Position(4));
end

function drawArrow2D(ax,startPoint,endPoint,color,lineWidth,headLength,headWidth,lineStyle)
vector = endPoint-startPoint;
unitVector = vector/norm(vector);
normalVector = [-unitVector(2);unitVector(1)];
shaftEnd = endPoint-headLength*unitVector;
plot(ax,[startPoint(1) shaftEnd(1)],[startPoint(2) shaftEnd(2)], ...
    "LineStyle",lineStyle,"Color",color,"LineWidth",lineWidth);
headPoints = [endPoint,shaftEnd+headWidth*normalVector,shaftEnd-headWidth*normalVector];
patch(ax,headPoints(1,:),headPoints(2,:),color,"EdgeColor",color);
end

function drawArrowHead2D(ax,tip,tangent,color,headLength,headWidth)
tangent = tangent/norm(tangent);
normalVector = [-tangent(2);tangent(1)];
base = tip-headLength*tangent;
headPoints = [tip,base+headWidth*normalVector,base-headWidth*normalVector];
patch(ax,headPoints(1,:),headPoints(2,:),color,"EdgeColor",color);
end

function drawAngleArc(ax,origin,startAngle,endAngle,radius,lineColor,lineWidth)
angleSamples = linspace(startAngle,endAngle,120);
plot(ax,origin(1)+radius*cos(angleSamples),origin(2)+radius*sin(angleSamples), ...
    "-","Color",lineColor,"LineWidth",lineWidth);
end

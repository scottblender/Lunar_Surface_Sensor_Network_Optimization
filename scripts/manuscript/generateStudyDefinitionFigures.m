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
fontName = style.fontName;
objectFontSize = style.annotationFontSize;
angleFontSize = style.labelFontSize;
rsoMarkerArea = 360;
backgroundColor = style.backgroundColor;
textColor = style.textColor;

sensorColor = style.redColor;
targetColor = style.magentaColor;
bodyColor = style.moonColor;
occultationColor = style.grayColor;
minimumAngleColor = style.orangeColor;
targetAngleColor = style.blueColor;
lineOfSightColor = style.textColor;
bodyDirectionColor = style.grayColor;
occultationShade = [0.92 0.92 0.93];
exclusionShade = [0.98 0.91 0.80];

sensor = [-2.20,0.00];
body = [0.95,0.00];
bodyRadius = 0.66;
bodyRange = norm(body-sensor);
thetaOcc = asin(bodyRadius/bodyRange);
thetaMin = deg2rad(20);
thetaRequired = max(thetaOcc,thetaMin);
thetaTarget = thetaRequired + deg2rad(14);
targetRange = 4.15;
target = sensor + targetRange*[cos(thetaTarget),sin(thetaTarget)];

fig = figure("Name","Celestial-body exclusion constraint", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 5.8 4.4],"Renderer","opengl");
ax = axes(fig,"Units","normalized","Position",[0.03 0.04 0.94 0.92]);
hold(ax,"on");
axis(ax,"equal");
axis(ax,"off");
ax.Color = backgroundColor;

sectorRadius = 3.35;
occultationAngles = linspace(-thetaOcc,thetaOcc,240);
patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(occultationAngles),sensor(1)], ...
    [sensor(2),sensor(2)+sectorRadius*sin(occultationAngles),sensor(2)], ...
    occultationShade,"EdgeColor","none","FaceAlpha",1.0);

if thetaRequired > thetaOcc
    upperAngles = linspace(thetaOcc,thetaRequired,160);
    lowerAngles = linspace(-thetaRequired,-thetaOcc,160);
    patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(upperAngles),sensor(1)], ...
        [sensor(2),sensor(2)+sectorRadius*sin(upperAngles),sensor(2)], ...
        exclusionShade,"EdgeColor","none","FaceAlpha",1.0);
    patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(lowerAngles),sensor(1)], ...
        [sensor(2),sensor(2)+sectorRadius*sin(lowerAngles),sensor(2)], ...
        exclusionShade,"EdgeColor","none","FaceAlpha",1.0);
end

bodyAngle = linspace(0,2*pi,300);
fill(ax,body(1)+bodyRadius*cos(bodyAngle),body(2)+bodyRadius*sin(bodyAngle), ...
    bodyColor,"EdgeColor",style.moonEdgeColor,"LineWidth",1.5);

plot(ax,[sensor(1),body(1)],[sensor(2),body(2)],"--", ...
    "Color",bodyDirectionColor,"LineWidth",1.7);

boundaryLength = 3.52;
for signValue = [-1 1]
    pointOcc = sensor + boundaryLength*[cos(signValue*thetaOcc),sin(signValue*thetaOcc)];
    plot(ax,[sensor(1),pointOcc(1)],[sensor(2),pointOcc(2)],":", ...
        "Color",occultationColor,"LineWidth",2.0);

    pointMin = sensor + boundaryLength*[cos(signValue*thetaRequired),sin(signValue*thetaRequired)];
    plot(ax,[sensor(1),pointMin(1)],[sensor(2),pointMin(2)],"--", ...
        "Color",minimumAngleColor,"LineWidth",2.3);
end

plot(ax,[sensor(1),target(1)],[sensor(2),target(2)],"-", ...
    "Color",lineOfSightColor,"LineWidth",2.4);

plot(ax,sensor(1),sensor(2),"o","MarkerSize",10, ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
scatter(ax,target(1),target(2),rsoMarkerArea,"p", ...
    "MarkerFaceColor",targetColor,"MarkerEdgeColor",targetColor,"LineWidth",1.2);

occultationArcRadius = 0.88;
minimumArcRadius = 1.30;
targetArcRadius = 1.72;
drawAngleArc(ax,sensor,0,thetaOcc,occultationArcRadius,occultationColor,2.2);
drawAngleArc(ax,sensor,0,thetaRequired,minimumArcRadius,minimumAngleColor,2.4);
drawAngleArc(ax,sensor,0,thetaTarget,targetArcRadius,targetAngleColor,2.4);

text(ax,sensor(1)+0.04,sensor(2)-0.34,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","bold","BackgroundColor",backgroundColor,"Margin",1.5, ...
    "HorizontalAlignment","center","VerticalAlignment","top");
text(ax,target(1)+0.13,target(2)-0.04,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","bold","BackgroundColor",backgroundColor,"Margin",1.5, ...
    "HorizontalAlignment","left","VerticalAlignment","middle");
text(ax,body(1),body(2)-0.94,"Celestial body $b$", ...
    "Interpreter","latex","Color",textColor,"FontName",fontName, ...
    "FontSize",objectFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",1.8, ...
    "HorizontalAlignment","center");

occLabel = sensor + 1.02*[cos(0.55*thetaOcc),sin(0.55*thetaOcc)];
minLabel = sensor + 1.48*[cos(0.72*thetaRequired),sin(0.72*thetaRequired)];
targetLabel = sensor + 1.92*[cos(0.84*thetaTarget),sin(0.84*thetaTarget)];

text(ax,occLabel(1)+0.22,occLabel(2)-0.27,"$\theta_{\mathrm{occ},b}$", ...
    "Interpreter","latex","Color",occultationColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",1.4, ...
    "HorizontalAlignment","center");
text(ax,minLabel(1)-0.03,minLabel(2)+0.20,"$\theta_{\min}$", ...
    "Interpreter","latex","Color",minimumAngleColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",1.4, ...
    "HorizontalAlignment","center");
text(ax,targetLabel(1)+0.02,targetLabel(2)+0.19,"$\theta_b$", ...
    "Interpreter","latex","Color",targetAngleColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",1.4, ...
    "HorizontalAlignment","center");

xlim(ax,[-2.90 1.90]);
ylim(ax,[-1.32 2.48]);
ax.LooseInset = max(ax.TightInset,0.005);

outputFile = fullfile(outputDirectory,"Exclusion_Constraint_Schematic.eps");
fig.InvertHardcopy = "off";
fig.PaperUnits = "inches";
fig.PaperSize = [5.8 4.4];
fig.PaperPosition = [0 0 5.8 4.4];
fig.PaperPositionMode = "manual";
drawnow;
% Preserve the schematic's original 19/22 pt object/angle typography.
setappdata(fig,"ManuscriptTypographyFinalized",true);
exportManuscriptFigure(fig,string(outputFile),5.8,4.4);

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

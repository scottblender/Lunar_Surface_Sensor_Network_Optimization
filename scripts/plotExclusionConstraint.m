%% plotExclusionConstraint
% Generate a white-background celestial-body exclusion schematic.
%
% Output:
%   Exclusion_Constraint_Schematic.eps

clear;
clc;

scriptDirectory = fileparts(mfilename("fullpath"));
addpath(scriptDirectory);
style = publicationPlotStyle();

fontName = style.fontName;
objectFontSize = 15;
angleFontSize = 17;
backgroundColor = style.backgroundColor;
textColor = style.textColor;

sensorColor = style.redColor;
targetColor = style.blueColor;
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
    "Position",[1 1 5.4 4.1],"Renderer","painters");
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
plot(ax,target(1),target(2),"o","MarkerSize",10, ...
    "MarkerFaceColor",targetColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);

occultationArcRadius = 0.88;
minimumArcRadius = 1.30;
targetArcRadius = 1.72;
drawAngleArc(ax,sensor,0,thetaOcc,occultationArcRadius,occultationColor,2.2);
drawAngleArc(ax,sensor,0,thetaRequired,minimumArcRadius,minimumAngleColor,2.4);
drawAngleArc(ax,sensor,0,thetaTarget,targetArcRadius,targetAngleColor,2.4);

% White label backings keep text readable where rays, boundaries, and shaded
% sectors pass beneath the annotations.
text(ax,sensor(1)+0.04,sensor(2)-0.34,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","bold","BackgroundColor",backgroundColor,"Margin",1.5, ...
    "HorizontalAlignment","center","VerticalAlignment","top");
text(ax,target(1)+0.11,target(2)-0.04,"RSO", ...
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

text(ax,occLabel(1)-0.05,occLabel(2)-0.27,"$\theta_{\mathrm{occ},b}$", ...
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

outputFile = fullfile(scriptDirectory,"Exclusion_Constraint_Schematic.eps");
exportgraphics(ax,outputFile,"ContentType","vector", ...
    "BackgroundColor",backgroundColor,"Colorspace","rgb");

fprintf("Saved exclusion-constraint schematic:\n  %s\n",outputFile);

function drawAngleArc(ax,origin,startAngle,endAngle,radius,lineColor,lineWidth)
angleSamples = linspace(startAngle,endAngle,120);
plot(ax,origin(1)+radius*cos(angleSamples),origin(2)+radius*sin(angleSamples), ...
    "-","Color",lineColor,"LineWidth",lineWidth);
end

%% plotExclusionConstraint
% Generate the compact manuscript celestial-body exclusion schematic.
%
% Output:
%   Exclusion_Constraint_Schematic.eps
%
% The natural canvas is intentionally compact because the current TeX places
% this figure at 0.50\columnwidth. Large source typography and a two-row
% in-canvas legend keep the reduced Figure 6 readable. The geometry follows
% the visibility/keep-out schematic used in the companion space-based paper.

clear;
clc;

scriptDirectory = fileparts(mfilename("fullpath"));
addpath(scriptDirectory);
style = publicationPlotStyle();

fontName = style.fontName;
backgroundColor = style.backgroundColor;
textColor = style.textColor;

sensorColor = style.redColor;
targetColor = style.blueColor;
bodyColor = style.moonColor;
occultationColor = style.grayColor;
minimumAngleColor = style.orangeColor;
lineOfSightColor = style.textColor;
occultationShade = [0.86 0.86 0.87];
exclusionShade = [0.98 0.91 0.76];

sensor = [-2.20,0.00];
body = [1.05,0.00];
bodyRadius = 0.66;
bodyRange = norm(body-sensor);
thetaOcc = asin(bodyRadius/bodyRange);
thetaMin = deg2rad(20);
thetaRequired = max(thetaOcc,thetaMin);
thetaTarget = thetaRequired + deg2rad(13);
targetRange = 4.75;
target = sensor + targetRange*[cos(thetaTarget),sin(thetaTarget)];

% Compact natural size: this avoids excessive down-scaling when the EPS is
% placed at half-column width in the manuscript.
figureWidth = 4.00;
figureHeight = 3.60;

fig = figure("Name","Celestial-body exclusion constraint", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 figureWidth figureHeight], ...
    "Renderer","opengl","InvertHardcopy","off");

% Reserve the upper strip for a guaranteed in-canvas legend.
ax = axes(fig,"Units","normalized","Position",[0.055 0.075 0.89 0.70]);
hold(ax,"on");
axis(ax,"equal");
axis(ax,"off");
ax.Color = backgroundColor;

sectorRadius = 3.45;
occultationAngles = linspace(-thetaOcc,thetaOcc,240);
patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(occultationAngles),sensor(1)], ...
    [sensor(2),sensor(2)+sectorRadius*sin(occultationAngles),sensor(2)], ...
    occultationShade,"EdgeColor","none","HandleVisibility","off");

if thetaRequired > thetaOcc
    upperAngles = linspace(thetaOcc,thetaRequired,160);
    lowerAngles = linspace(-thetaRequired,-thetaOcc,160);
    patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(upperAngles),sensor(1)], ...
        [sensor(2),sensor(2)+sectorRadius*sin(upperAngles),sensor(2)], ...
        exclusionShade,"EdgeColor","none","HandleVisibility","off");
    patch(ax,[sensor(1),sensor(1)+sectorRadius*cos(lowerAngles),sensor(1)], ...
        [sensor(2),sensor(2)+sectorRadius*sin(lowerAngles),sensor(2)], ...
        exclusionShade,"EdgeColor","none","HandleVisibility","off");
end

bodyAngle = linspace(0,2*pi,300);
fill(ax,body(1)+bodyRadius*cos(bodyAngle),body(2)+bodyRadius*sin(bodyAngle), ...
    bodyColor,"EdgeColor",style.moonEdgeColor,"LineWidth",1.4, ...
    "HandleVisibility","off");

plot(ax,[sensor(1),body(1)],[sensor(2),body(2)],"--", ...
    "Color",occultationColor,"LineWidth",1.3,"HandleVisibility","off");

boundaryLength = 3.65;
occUpper = sensor + boundaryLength*[cos(thetaOcc),sin(thetaOcc)];
keepUpper = sensor + boundaryLength*[cos(thetaRequired),sin(thetaRequired)];
occLower = sensor + boundaryLength*[cos(-thetaOcc),sin(-thetaOcc)];
keepLower = sensor + boundaryLength*[cos(-thetaRequired),sin(-thetaRequired)];

hOcc = plot(ax,[sensor(1),occUpper(1)],[sensor(2),occUpper(2)],":", ...
    "Color",occultationColor,"LineWidth",2.0, ...
    "DisplayName","Occultation boundary");
plot(ax,[sensor(1),occLower(1)],[sensor(2),occLower(2)],":", ...
    "Color",occultationColor,"LineWidth",2.0,"HandleVisibility","off");

hKeep = plot(ax,[sensor(1),keepUpper(1)],[sensor(2),keepUpper(2)],"--", ...
    "Color",minimumAngleColor,"LineWidth",2.3, ...
    "DisplayName","Minimum separation");
plot(ax,[sensor(1),keepLower(1)],[sensor(2),keepLower(2)],"--", ...
    "Color",minimumAngleColor,"LineWidth",2.3,"HandleVisibility","off");

hLos = plot(ax,[sensor(1),target(1)],[sensor(2),target(2)],"-", ...
    "Color",lineOfSightColor,"LineWidth",2.5,"DisplayName","RSO LOS");

plot(ax,sensor(1),sensor(2),"o","MarkerSize",10, ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",textColor, ...
    "LineWidth",1.0,"HandleVisibility","off");
plot(ax,target(1),target(2),"o","MarkerSize",10, ...
    "MarkerFaceColor",targetColor,"MarkerEdgeColor",textColor, ...
    "LineWidth",1.0,"HandleVisibility","off");

drawAngleArc(ax,sensor,0,thetaOcc,0.95,occultationColor,2.0);
drawAngleArc(ax,sensor,0,thetaRequired,1.48,minimumAngleColor,2.2);
drawAngleArc(ax,sensor,0,thetaTarget,2.08,targetColor,2.2);

% Large source text is deliberate because the TeX scales the figure down.
objectFontSize = 18;
angleFontSize = 17;

text(ax,sensor(1)-0.02,sensor(2)-0.44,"Surface sensor", ...
    "Color",sensorColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","bold","HorizontalAlignment","center");
text(ax,target(1)+0.08,target(2)-0.03,"RSO", ...
    "Color",targetColor,"FontName",fontName,"FontSize",objectFontSize, ...
    "FontWeight","bold","HorizontalAlignment","left");
text(ax,body(1),body(2)-1.08,"Celestial body $b$", ...
    "Interpreter","latex","Color",textColor,"FontName",fontName, ...
    "FontSize",objectFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",0.6, ...
    "HorizontalAlignment","center");

occPoint = sensor + 0.95*[cos(0.5*thetaOcc),sin(0.5*thetaOcc)];
keepPoint = sensor + 1.48*[cos(0.5*thetaRequired),sin(0.5*thetaRequired)];
targetPoint = sensor + 2.08*[cos(0.5*thetaTarget),sin(0.5*thetaTarget)];

text(ax,occPoint(1)+0.48,occPoint(2)-0.34,"\theta_{\mathrm{occ},b}", ...
    "Interpreter","tex","Color",occultationColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",0.4);
text(ax,keepPoint(1)-0.45,keepPoint(2)+0.42,"\theta_{\min,b}", ...
    "Interpreter","tex","Color",minimumAngleColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",0.4);
text(ax,targetPoint(1)+0.28,targetPoint(2)+0.34,"\theta_b", ...
    "Interpreter","tex","Color",targetColor,"FontName",fontName, ...
    "FontSize",angleFontSize,"FontWeight","bold", ...
    "BackgroundColor",backgroundColor,"Margin",0.4);

xlim(ax,[-3.10 3.28]);
ylim(ax,[-1.78 3.30]);

% Two-row true legend. Its normalized position is fixed inside the canvas
% so the EPS export cannot drop it.
lgd = legend(ax,[hLos hOcc hKeep], ...
    ["RSO LOS","Occultation boundary","Minimum separation"], ...
    "Location","none","Orientation","horizontal", ...
    "NumColumns",2,"Box","off");
lgd.FontName = fontName;
lgd.FontSize = 16;
lgd.FontWeight = "bold";
lgd.TextColor = textColor;
drawnow;
lgd.Units = "normalized";
lgd.Position = [0.08 0.855 0.84 0.12];

outputFile = fullfile(scriptDirectory,"Exclusion_Constraint_Schematic.eps");
exportManuscriptFigure(fig,string(outputFile),figureWidth,figureHeight);

fprintf("Saved exclusion-constraint schematic:\n  %s\n",outputFile);

function drawAngleArc(ax,origin,startAngle,endAngle,radius,lineColor,lineWidth)
angleSamples = linspace(startAngle,endAngle,120);
plot(ax,origin(1)+radius*cos(angleSamples), ...
    origin(2)+radius*sin(angleSamples), ...
    "-","Color",lineColor,"LineWidth",lineWidth, ...
    "HandleVisibility","off");
end

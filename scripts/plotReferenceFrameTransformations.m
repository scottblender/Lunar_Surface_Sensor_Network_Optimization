%% plotReferenceFrameTransformations
% Create white-background publication figures for the lunar reference frames.
%
% Outputs:
%   reference_frame_moon_centered.eps
%   reference_frame_sensor_centered.eps

clear;
close all;
clc;

scriptDirectory = fileparts(mfilename("fullpath"));
addpath(scriptDirectory);
style = publicationPlotStyle();

fontName = style.fontName;
axisLabelFontSize = 13;
annotationFontSize = 11;
backgroundColor = style.backgroundColor;
textColor = style.textColor;
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
exportPaddingInches = 0.25;

moonCenteredFile = fullfile(scriptDirectory,"reference_frame_moon_centered.eps");
sensorCenteredFile = fullfile(scriptDirectory,"reference_frame_sensor_centered.eps");

circleAngle = linspace(0,2*pi,500);
theta = deg2rad(35);

%% Moon-centered MCI / MR figure

figMoon = figure("Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 exportWidthInches exportHeightInches],"Renderer","painters");
axMoon = axes(figMoon,"Position",[0.05 0.05 0.90 0.90]);
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

drawArrow2D(axMoon,origin,origin+axisLength*xI,mciColor,2.0,0.085,0.065,"-");
drawArrow2D(axMoon,origin,origin+axisLength*yI,mciColor,2.0,0.085,0.065,"-");
drawArrow2D(axMoon,origin,origin+axisLength*xR,mrColor,2.0,0.085,0.065,"--");
drawArrow2D(axMoon,origin,origin+axisLength*yR,mrColor,2.0,0.085,0.065,"--");

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
    "FontSize",annotationFontSize,"HorizontalAlignment","right","VerticalAlignment","top");

angleRadius = 0.37;
angleValues = linspace(0,theta,100);
anglePoints = origin + angleRadius*[cos(angleValues);sin(angleValues)];
plot(axMoon,anglePoints(1,:),anglePoints(2,:),"Color",angleColor,"LineWidth",1.8);
drawArrowHead2D(axMoon,anglePoints(:,end),[-sin(theta);cos(theta)],angleColor,0.065,0.055);
angleLabel = origin + 0.49*[cos(theta/2);sin(theta/2)];
text(axMoon,angleLabel(1),angleLabel(2),"\theta(t)", ...
    "Interpreter","tex","Color",angleColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");

%% Sensor-centered ENU figure

figSensor = figure("Color",backgroundColor,"Units","inches", ...
    "Position",[8 1 exportWidthInches exportHeightInches],"Renderer","painters");
axSensor = axes(figSensor,"Position",[0.05 0.05 0.90 0.90]);
hold(axSensor,"on");
axis(axSensor,"equal");
axis(axSensor,"off");
axSensor.Color = backgroundColor;
xlim(axSensor,[-1.35 1.35]);
ylim(axSensor,[-0.55 2.15]);

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
    "HorizontalAlignment","right","VerticalAlignment","top");

plot(axSensor,[localMoonCenter(1),sensorPosition(1)], ...
    [localMoonCenter(2),sensorPosition(2)],":", ...
    "Color",style.grayColor,"LineWidth",1.1);
text(axSensor,sensorPosition(1)+0.08,sensorPosition(2)-0.43,"r_{s,R}", ...
    "Interpreter","tex","Color",style.grayColor,"FontName",fontName, ...
    "FontSize",annotationFontSize);

E = [1;0];
N = [-0.72;0.55]; N = N/norm(N);
U = [0;1];
localAxisLength = 0.58;

drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*E, ...
    eastColor,2.0,0.070,0.058,"-");
drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*N, ...
    northColor,2.0,0.070,0.058,"-");
drawArrow2D(axSensor,sensorPosition,sensorPosition+localAxisLength*U, ...
    upColor,2.0,0.070,0.058,"-");

text(axSensor,sensorPosition(1)+0.70,sensorPosition(2),"E", ...
    "Color",eastColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold");
text(axSensor,sensorPosition(1)+0.70*N(1),sensorPosition(2)+0.70*N(2),"N", ...
    "Color",northColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold");
text(axSensor,sensorPosition(1),sensorPosition(2)+0.70,"U", ...
    "Color",upColor,"FontName",fontName,"FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "HorizontalAlignment","center");

rsoPosition = [0.80;1.50];
drawArrow2D(axSensor,sensorPosition,rsoPosition,relativePositionColor,2.2,0.095,0.065,"-");
scatter(axSensor,rsoPosition(1),rsoPosition(2),80,"p", ...
    "MarkerFaceColor",relativePositionColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
text(axSensor,rsoPosition(1)+0.12,rsoPosition(2)+0.04,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize);

rho = rsoPosition-sensorPosition;
rhoNormal = [-rho(2);rho(1)]/norm(rho);
rhoLabel = sensorPosition + 0.58*rho + 0.10*rhoNormal;
text(axSensor,rhoLabel(1),rhoLabel(2),"\rho_R", ...
    "Interpreter","tex","Color",relativePositionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");

%% Export

exportgraphics(figMoon,moonCenteredFile,"ContentType","vector", ...
    "BackgroundColor",backgroundColor,"Colorspace","rgb", ...
    "Units","inches","Width",exportWidthInches,"Height",exportHeightInches, ...
    "Padding",exportPaddingInches,"PreserveAspectRatio","on");

exportgraphics(figSensor,sensorCenteredFile,"ContentType","vector", ...
    "BackgroundColor",backgroundColor,"Colorspace","rgb", ...
    "Units","inches","Width",exportWidthInches,"Height",exportHeightInches, ...
    "Padding",exportPaddingInches,"PreserveAspectRatio","on");

fprintf("Saved reference-frame figures.\n");

%% Local helpers

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

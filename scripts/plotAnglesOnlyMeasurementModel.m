%% plotAnglesOnlyMeasurementModel
% Create white-background publication schematics for the angles-only model.
%
% Outputs:
%   angles_only_right_ascension_geometry.eps
%   angles_only_declination_geometry.eps

clear;
clc;

scriptDirectory = fileparts(mfilename("fullpath"));
addpath(scriptDirectory);
style = publicationPlotStyle();

fontName = style.fontName;
axisLabelFontSize = 20;
annotationFontSize = 16;

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

exportWidthInches = 6.50;
exportHeightInches = 6.50;
exportPaddingInches = 0.25;

rightAscensionFile = fullfile(scriptDirectory,"angles_only_right_ascension_geometry.eps");
declinationFile = fullfile(scriptDirectory,"angles_only_declination_geometry.eps");

alpha = deg2rad(38);
delta = deg2rad(32);

%% Right ascension

figRa = figure("Name","Angles-only: right ascension", ...
    "Color",backgroundColor,"Units","inches", ...
    "Position",[1 1 exportWidthInches exportHeightInches],"Renderer","painters");
axRa = axes(figRa,"Position",[0.055 0.055 0.89 0.89]);
hold(axRa,"on");
axis(axRa,"equal");
axis(axRa,"off");
axRa.Color = backgroundColor;
axRa.FontName = fontName;
xlim(axRa,[-2.35 2.35]);
ylim(axRa,[-2.35 2.35]);

sensor = [-0.58;-0.48];
axisLength = 1.35;
projectionLength = 2.05;
projectionEnd = sensor + projectionLength*[cos(alpha);sin(alpha)];

scatter(axRa,sensor(1),sensor(2),70,"o", ...
    "MarkerFaceColor",sensorColor,"MarkerEdgeColor",backgroundColor, ...
    "LineWidth",1.0);
text(axRa,sensor(1)-0.18,sensor(2)-0.28,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

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
labelPosition = sensor + 0.68*projectionLength*[cos(alpha);sin(alpha)] + 0.20*normal;
text(axRa,labelPosition(1),labelPosition(2),"\rho_{xy,k}", ...
    "Interpreter","tex","Color",projectionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

scatter(axRa,projectionEnd(1),projectionEnd(2),105,"p", ...
    "MarkerFaceColor",losColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
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
    "Position",[8 1 exportWidthInches exportHeightInches],"Renderer","painters");
axDec = axes(figDec,"Position",[0.055 0.055 0.89 0.89]);
hold(axDec,"on");
axis(axDec,"equal");
axis(axDec,"off");
axDec.Color = backgroundColor;
axDec.FontName = fontName;
xlim(axDec,[-2.60 2.60]);
ylim(axDec,[-2.60 2.60]);

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
text(axDec,sensor(1)-0.36,sensor(2)-0.20,"Surface sensor", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

drawArrow2D(axDec,sensor,sensor+[0;0.92],axisColor,2.1,0.095,0.070,"-");
text(axDec,sensor(1),sensor(2)+1.08,"z_I", ...
    "Interpreter","tex","Color",axisColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold","HorizontalAlignment","center");

plot(axDec,[sensor(1),projectionEnd(1)+0.09],[sensor(2),projectionEnd(2)], ...
    "--","Color",projectionColor,"LineWidth",1.6);
plot(axDec,[projectionEnd(1),rsoPosition(1)],[projectionEnd(2)-0.09,rsoPosition(2)], ...
    ":","Color",projectionColor,"LineWidth",1.4);
text(axDec,sensor(1)+0.60*projectionLength,sensor(2)-0.22,"\rho_{xy,k}", ...
    "Interpreter","tex","Color",projectionColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

drawArrow2D(axDec,sensor,rsoPosition,losColor,2.8,0.12,0.085,"-");
losVector = rsoPosition-sensor;
losNormal = [-losVector(2);losVector(1)]/norm(losVector);
losLabelPosition = sensor + 0.61*losVector + 0.18*losNormal;
text(axDec,losLabelPosition(1),losLabelPosition(2),"\rho_{I,k}", ...
    "Interpreter","tex","Color",losColor,"FontName",fontName, ...
    "FontSize",axisLabelFontSize,"FontWeight","bold", ...
    "BackgroundColor",labelBackgroundColor,"Margin",style.labelMargin, ...
    "HorizontalAlignment","center");

scatter(axDec,rsoPosition(1),rsoPosition(2),112,"p", ...
    "MarkerFaceColor",losColor,"MarkerEdgeColor",backgroundColor,"LineWidth",1.0);
text(axDec,rsoPosition(1)+0.16,rsoPosition(2)+0.04,"RSO", ...
    "Color",textColor,"FontName",fontName,"FontSize",annotationFontSize, ...
    "FontWeight","bold","BackgroundColor",labelBackgroundColor, ...
    "Margin",style.labelMargin, ...
    "HorizontalAlignment","left","VerticalAlignment","middle");

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

exportgraphics(figRa,rightAscensionFile,"ContentType","vector", ...
    "BackgroundColor",backgroundColor,"Colorspace","rgb", ...
    "Units","inches","Width",exportWidthInches,"Height",exportHeightInches, ...
    "Padding",exportPaddingInches,"PreserveAspectRatio","on");

exportgraphics(figDec,declinationFile,"ContentType","vector", ...
    "BackgroundColor",backgroundColor,"Colorspace","rgb", ...
    "Units","inches","Width",exportWidthInches,"Height",exportHeightInches, ...
    "Padding",exportPaddingInches,"PreserveAspectRatio","on");

fprintf("Saved angles-only geometry figures.\n");

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

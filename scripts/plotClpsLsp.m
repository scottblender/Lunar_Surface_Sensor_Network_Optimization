%% plotClpsLsp
% Generate a white-background CLPS lunar south-polar manuscript figure.
%
% Output:
%   CLPS_LSP_Detail.eps

clear;
close all;
clc;

scriptDirectory = fileparts(mfilename("fullpath"));
repositoryRoot = fileparts(scriptDirectory);
addpath(scriptDirectory);
style = publicationPlotStyle();

fontName = style.fontName;
siteFontSize = 11;
gridFontSize = 11;
legendFontSize = 10.5;
colorbarFontSize = 10.5;

completedColor = style.redColor;
plannedColor = style.magentaColor;
optionalColor = style.orangeColor;
boundaryColor = style.boundaryColor;
gridColor = [0.28 0.28 0.30];
textColor = style.textColor;
boxColor = style.backgroundColor;
boxEdgeColor = [0.70 0.70 0.70];

%% Load DEM

demFile = fullfile(repositoryRoot,"data","new_lunar_interpolant_model.mat");
assert(isfile(demFile),"DEM file was not found: %s",demFile);

loadedData = load(demFile);
variableNames = fieldnames(loadedData);
demInterpolant = [];
for variableIndex = 1:numel(variableNames)
    currentVariable = loadedData.(variableNames{variableIndex});
    if isa(currentVariable,"griddedInterpolant")
        demInterpolant = currentVariable;
        break
    end
end
assert(~isempty(demInterpolant), ...
    "No griddedInterpolant was found in %s.",demFile);

moonRadiusKm = 1737.4;
domainSouthDeg = -90;
domainNorthDeg = -75;

longitudeDeg = linspace(0,360,721);
latitudeDeg = linspace(domainSouthDeg,domainNorthDeg,301);
[longitudeMeshDeg,latitudeMeshDeg] = meshgrid(longitudeDeg,latitudeDeg);
elevationKm = double(demInterpolant(latitudeMeshDeg,longitudeMeshDeg));
finiteElevationKm = elevationKm(isfinite(elevationKm));
elevationLimitsKm = [min(finiteElevationKm),max(finiteElevationKm)];

% Completed CLPS landings: IM-1 and IM-2.
completedLatitudeDeg = [-80.1277;-84.7754];
completedLongitudeDeg = [1.4357;29.1264];

% Mons Mouton planned region.
monsLatitudeSouthDeg = -86.22;
monsLatitudeNorthDeg = -83.30;
monsLongitudeWestDeg = 11.67;
monsLongitudeEastDeg = 53.03;

% Schrodinger Basin overlap with the optimization domain.
schrodingerLatitudeSouthDeg = -79.95;
schrodingerLatitudeNorthDeg = domainNorthDeg;
schrodingerLongitudeWestDeg = 112.33;
schrodingerLongitudeEastDeg = 153.44;

%% Polar map

fig = figure("Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 10.5 6.8],"Renderer","painters");
ax = axes(fig,"Position",[0.055 0.115 0.80 0.83]);
hold(ax,"on");
ax.Color = style.backgroundColor;
ax.FontName = fontName;
ax.SortMethod = "childorder";

polarDistanceKm = moonRadiusKm .* deg2rad(90 + latitudeMeshDeg);
xKm = polarDistanceKm .* sind(longitudeMeshDeg);
yKm = polarDistanceKm .* cosd(longitudeMeshDeg);
outerRadiusKm = moonRadiusKm*deg2rad(15);

surf(ax,xKm,yKm,zeros(size(xKm)),elevationKm, ...
    "EdgeColor","none","FaceColor","interp");
view(ax,2);
colormap(ax,turbo(256));
clim(ax,elevationLimitsKm);

circleAngleDeg = linspace(0,360,721);
latitudeGridDeg = [-85 -80 -75];
for latitudeValue = latitudeGridDeg
    radiusKm = moonRadiusKm*deg2rad(90 + latitudeValue);
    xGrid = radiusKm*sind(circleAngleDeg);
    yGrid = radiusKm*cosd(circleAngleDeg);
    if latitudeValue == domainNorthDeg
        plot(ax,xGrid,yGrid,"Color",boundaryColor,"LineWidth",2.2);
    else
        plot(ax,xGrid,yGrid,"--","Color",gridColor,"LineWidth",0.9);
    end
end

longitudeGridDeg = [0 90 180 270];
for longitudeValue = longitudeGridDeg
    radialDistanceKm = [0 outerRadiusKm];
    plot(ax,radialDistanceKm*sind(longitudeValue), ...
        radialDistanceKm*cosd(longitudeValue),"--", ...
        "Color",gridColor,"LineWidth",0.9);
end

longitudeLabelRadiusKm = outerRadiusKm + 38;
longitudeLabelText = ["0^{\circ}E","90^{\circ}E","180^{\circ}E","270^{\circ}E"];
for longitudeIndex = 1:numel(longitudeGridDeg)
    longitudeValue = longitudeGridDeg(longitudeIndex);
    text(ax,longitudeLabelRadiusKm*sind(longitudeValue), ...
        longitudeLabelRadiusKm*cosd(longitudeValue), ...
        longitudeLabelText(longitudeIndex), ...
        "Interpreter","tex","Color",textColor,"FontName",fontName, ...
        "FontSize",gridFontSize,"FontWeight","bold", ...
        "BackgroundColor",boxColor,"Margin",1.5, ...
        "HorizontalAlignment","center","VerticalAlignment","middle");
end

latitudeLabelLongitudeDeg = 225;
for latitudeValue = latitudeGridDeg(1:2)
    radiusKm = moonRadiusKm*deg2rad(90 + latitudeValue);
    text(ax,radiusKm*sind(latitudeLabelLongitudeDeg)-8, ...
        radiusKm*cosd(latitudeLabelLongitudeDeg)+7, ...
        sprintf("%d^{\\circ}S",abs(latitudeValue)), ...
        "Interpreter","tex","Color",textColor,"FontName",fontName, ...
        "FontSize",gridFontSize,"FontWeight","bold", ...
        "BackgroundColor",boxColor,"Margin",1.5, ...
        "HorizontalAlignment","right","VerticalAlignment","middle");
end

plot(ax,0,0,".","Color",textColor,"MarkerSize",13);
text(ax,-18,-18,"South Pole","Color",textColor,"FontName",fontName, ...
    "FontSize",gridFontSize,"FontWeight","bold", ...
    "BackgroundColor",boxColor,"Margin",1.5, ...
    "HorizontalAlignment","right","VerticalAlignment","top");

%% Regions and completed sites

[monsX,monsY] = rectangularPolarRegion( ...
    monsLatitudeSouthDeg,monsLatitudeNorthDeg, ...
    monsLongitudeWestDeg,monsLongitudeEastDeg,moonRadiusKm);
monsHandle = patch(ax,monsX,monsY,plannedColor, ...
    "FaceAlpha",0.18,"EdgeColor",plannedColor,"LineWidth",2.4, ...
    "DisplayName","Planned Mons Mouton region");

[schX,schY] = rectangularPolarRegion( ...
    schrodingerLatitudeSouthDeg,schrodingerLatitudeNorthDeg, ...
    schrodingerLongitudeWestDeg,schrodingerLongitudeEastDeg,moonRadiusKm);
schHandle = patch(ax,schX,schY,optionalColor, ...
    "FaceAlpha",0.16,"EdgeColor",optionalColor,"LineWidth",2.1, ...
    "DisplayName","Schrodinger overlap");

[completedX,completedY] = polarCoordinates( ...
    completedLatitudeDeg,completedLongitudeDeg,moonRadiusKm);
completedHandle = scatter(ax,completedX,completedY,80,"o", ...
    "MarkerFaceColor",style.backgroundColor, ...
    "MarkerEdgeColor",completedColor,"LineWidth",2.0, ...
    "DisplayName","Completed landing");

text(ax,completedX(1)+15,completedY(1)+15,"IM-1", ...
    "Color",textColor,"FontName",fontName,"FontSize",siteFontSize, ...
    "FontWeight","bold","BackgroundColor",boxColor,"Margin",1.5);
text(ax,completedX(2)+15,completedY(2)-18,"IM-2", ...
    "Color",textColor,"FontName",fontName,"FontSize",siteFontSize, ...
    "FontWeight","bold","BackgroundColor",boxColor,"Margin",1.5);

text(ax,mean(monsX),mean(monsY),"Mons Mouton", ...
    "Color",textColor,"FontName",fontName,"FontSize",siteFontSize, ...
    "FontWeight","bold","BackgroundColor",boxColor,"EdgeColor",boxEdgeColor, ...
    "Margin",2.0,"HorizontalAlignment","center");

%% Final formatting

axis(ax,"equal");
axis(ax,"off");
mapLimitKm = outerRadiusKm + 100;
xlim(ax,[-mapLimitKm mapLimitKm]);
ylim(ax,[-mapLimitKm mapLimitKm]);

colorbarHandle = colorbar(ax,"eastoutside");
colorbarHandle.FontName = fontName;
colorbarHandle.FontSize = colorbarFontSize;
colorbarHandle.Color = textColor;
colorbarHandle.Label.String = "Elevation (km)";
colorbarHandle.Label.FontName = fontName;
colorbarHandle.Label.FontSize = colorbarFontSize;
colorbarHandle.Label.Color = textColor;

legendHandle = legend(ax,[completedHandle monsHandle schHandle], ...
    "Completed landing","Planned Mons Mouton region","Schrodinger overlap", ...
    "Location","southoutside","Orientation","horizontal");
legendHandle.FontName = fontName;
legendHandle.FontSize = legendFontSize;
legendHandle.TextColor = textColor;
legendHandle.Color = style.backgroundColor;
legendHandle.EdgeColor = boxEdgeColor;

outputFile = fullfile(scriptDirectory,"CLPS_LSP_Detail.eps");
exportgraphics(fig,outputFile,"ContentType","image","Resolution",600, ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");

fprintf("Saved CLPS south-polar figure:\n  %s\n",outputFile);

%% Local helpers

function [xKm,yKm] = polarCoordinates(latitudeDeg,longitudeDeg,moonRadiusKm)
radiusKm = moonRadiusKm.*deg2rad(90+latitudeDeg);
xKm = radiusKm.*sind(longitudeDeg);
yKm = radiusKm.*cosd(longitudeDeg);
end

function [xKm,yKm] = rectangularPolarRegion( ...
    latitudeSouthDeg,latitudeNorthDeg,longitudeWestDeg,longitudeEastDeg,moonRadiusKm)
numberOfSamples = 120;
longitudeSouth = linspace(longitudeWestDeg,longitudeEastDeg,numberOfSamples);
latitudeEast = linspace(latitudeSouthDeg,latitudeNorthDeg,numberOfSamples);
longitudeNorth = linspace(longitudeEastDeg,longitudeWestDeg,numberOfSamples);
latitudeWest = linspace(latitudeNorthDeg,latitudeSouthDeg,numberOfSamples);
latitudeBoundary = [ ...
    latitudeSouthDeg*ones(1,numberOfSamples), ...
    latitudeEast, ...
    latitudeNorthDeg*ones(1,numberOfSamples), ...
    latitudeWest];
longitudeBoundary = [ ...
    longitudeSouth, ...
    longitudeEastDeg*ones(1,numberOfSamples), ...
    longitudeNorth, ...
    longitudeWestDeg*ones(1,numberOfSamples)];
[xKm,yKm] = polarCoordinates(latitudeBoundary,longitudeBoundary,moonRadiusKm);
end

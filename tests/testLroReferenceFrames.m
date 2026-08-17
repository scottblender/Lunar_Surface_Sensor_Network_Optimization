%% testLroReferenceFrames
% Propagate an LRO-like lunar orbit and create two views:
%   1. The physical trajectory in the Moon-rotating frame
%   2. The above-horizon trajectory as seen from a surface sensor
%
% Expected project layout:
%   project/
%     data/new_lunar_interpolant_model.mat
%     src/+orbitDynamics/...
%     src/+referenceFrames/...
%     tests/testLroReferenceFrames.m

% The MAT-file must contain the griddedInterpolant F. Its grid is assumed
% to be latitude/longitude in degrees and its elevation values in km.

% Required functions:
%   orbitDynamics.propagateLunarOrbit
%   referenceFrames.moonRotating
%   referenceFrames.topographic


clear;
close all;
clc;

%% Project paths and DEM
testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
addpath(fullfile(projectRoot, "src"));

demPath = fullfile(projectRoot, "data", ...
    "new_lunar_interpolant_model.mat");

% This fallback also allows the script to run when it is placed beside the
% supplied DEM during development.
if ~isfile(demPath)
    demPath = fullfile(testDirectory, "new_lunar_interpolant_model.mat");
end

assert(isfile(demPath), ...
    "DEM file not found. Put new_lunar_interpolant_model.mat in project/data.");

demData = load(demPath, "F");
assert(isfield(demData, "F") && isa(demData.F, "griddedInterpolant"), ...
    "The DEM file must contain a griddedInterpolant named F.");

% Convert the supplied degree-based DEM grid into the radian-based
% interpolant expected by referenceFrames.topographic. Add a periodic seam
% at 2*pi so longitude remains continuous across 0/360 degrees.
sourceDem = demData.F;
latitudeGrid = deg2rad(sourceDem.GridVectors{1}(:));
longitudeGrid = deg2rad(sourceDem.GridVectors{2}(:));
elevationGrid = sourceDem.Values;

longitudeGrid = [longitudeGrid; 2*pi];
elevationGrid = [elevationGrid, elevationGrid(:,1)];

dem = griddedInterpolant( ...
    {latitudeGrid, longitudeGrid}, elevationGrid, "linear", "nearest");

%% Lunar orbit and frame constants
moonRadius = 1737.4;             % km
moonMu = 4902.800066;            % km^3/s^2
moonSiderealPeriod = 27.321661*86400; % s
moonAngularRate = 2*pi/moonSiderealPeriod; % rad/s
theta0 = 0;                      % MR angle relative to MCI at t = 0, rad

orbitAltitude = 50;              % km, representative low LRO-like orbit
orbitRadius = moonRadius + orbitAltitude;
orbitInclination = deg2rad(90);  % polar orbit

% Arbitrary south-polar sensor near the IM-4 landing region.
sensorLatitude = deg2rad(-84);    % rad
sensorLongitude = deg2rad(37);   % rad, east-positive

% Align the test orbit's ascending-node longitude with the sensor longitude
% at the initial epoch so the trajectory passes through the same meridian.
rightAscensionAscendingNode = sensorLongitude;

%% Initial circular MCI state
rotationZ = [cos(rightAscensionAscendingNode), ...
            -sin(rightAscensionAscendingNode), 0; ...
             sin(rightAscensionAscendingNode), ...
             cos(rightAscensionAscendingNode), 0; ...
             0, 0, 1];

rotationX = [1, 0, 0; ...
             0, cos(orbitInclination), -sin(orbitInclination); ...
             0, sin(orbitInclination),  cos(orbitInclination)];

perifocalToMci = rotationZ*rotationX;
circularSpeed = sqrt(moonMu/orbitRadius);

initialPosition = perifocalToMci*[orbitRadius; 0; 0];
initialVelocity = perifocalToMci*[0; circularSpeed; 0];
initialState = [initialPosition; initialVelocity];

orbitPeriod = 2*pi*sqrt(orbitRadius^3/moonMu);
outputStep = 10;                 % s
timeSpan = (0:outputStep:orbitPeriod).';
if timeSpan(end) < orbitPeriod
    timeSpan(end+1,1) = orbitPeriod;
end

%% Propagate in MCI and transform the saved states
[times, statesMoonInertial] = orbitDynamics.propagateLunarOrbit( ...
    initialState, timeSpan, moonMu=moonMu);

statesMoonRotating = zeros(size(statesMoonInertial));
statesTopographic = zeros(size(statesMoonInertial));

for sampleIndex = 1:numel(times)
    inertialState = statesMoonInertial(sampleIndex,:).';

    rotatingState = referenceFrames.moonRotating( ...
        inertialState, times(sampleIndex), theta0, moonAngularRate, ...
        "fromInertial");

    topographicState = referenceFrames.topographic( ...
        rotatingState, sensorLatitude, sensorLongitude, dem, ...
        moonRadius, "fromRotating");

    statesMoonRotating(sampleIndex,:) = rotatingState.';
    statesTopographic(sampleIndex,:) = topographicState.';
end

%% Sensor location in the Moon-rotating frame
sensorElevation = dem(sensorLatitude, mod(sensorLongitude, 2*pi));
sensorUp = [cos(sensorLatitude)*cos(sensorLongitude); ...
            cos(sensorLatitude)*sin(sensorLongitude); ...
            sin(sensorLatitude)];
sensorPositionMoonRotating = (moonRadius + sensorElevation)*sensorUp;

%% Sensor azimuth and elevation
% The topographic position is [East; North; Up] relative to the sensor.
east = statesTopographic(:,1);
north = statesTopographic(:,2);
up = statesTopographic(:,3);

azimuth = mod(atan2(east, north), 2*pi);
elevation = atan2(up, hypot(east, north));

% A sky plot uses zenith angle as its radius: the zenith is at 0 degrees
% and the local horizon is at 90 degrees. NaNs separate portions of the
% orbit that are below the sensor's geometric horizon.
visibleFromSensor = elevation >= 0;
skyRadiusDegrees = 90 - rad2deg(elevation);
skyRadiusDegrees(~visibleFromSensor) = NaN;

%% Two-view orbit visualization
[moonX, moonY, moonZ] = sphere(80);
moonX = moonRadius*moonX;
moonY = moonRadius*moonY;
moonZ = moonRadius*moonZ;

figure("Color", "white", "Name", "LRO-like Orbit and Sensor View");
layout = tiledlayout(1, 2, "TileSpacing", "compact", ...
    "Padding", "compact");

nexttile(layout, 1);
plotMoon(moonX, moonY, moonZ);
hold on;
plot3(statesMoonRotating(:,1), statesMoonRotating(:,2), ...
    statesMoonRotating(:,3), "b", "LineWidth", 1.6);
plot3(sensorPositionMoonRotating(1), sensorPositionMoonRotating(2), ...
    sensorPositionMoonRotating(3), "rp", "MarkerSize", 12, ...
    "MarkerFaceColor", "r");
formatFrameAxes("Orbit in the Moon-Rotating Frame", ...
    "x_{MR}", "y_{MR}", "z_{MR}");
legend("Moon", "Orbit", "Surface sensor", "Location", "southoutside");

skyAxes = polaraxes(layout);
skyAxes.Layout.Tile = 2;
polarplot(skyAxes, azimuth, skyRadiusDegrees, ...
    "b", "LineWidth", 1.8);
skyAxes.ThetaZeroLocation = "top";
skyAxes.ThetaDir = "clockwise";
skyAxes.ThetaTick = 0:45:315;
skyAxes.ThetaTickLabel = {"N", "NE", "E", "SE", ...
    "S", "SW", "W", "NW"};
skyAxes.RLim = [0, 90];
skyAxes.RTick = [0, 30, 60, 90];
skyAxes.RTickLabel = {"90 deg", "60 deg", "30 deg", "0 deg"};
skyAxes.GridAlpha = 0.35;
title(skyAxes, "Orbit as Viewed from the Sensor");
legend(skyAxes, "Visible trajectory", "Location", "southoutside");

figureTitle = sprintf(['LRO-like %.0f km Circular Polar Orbit | ' ...
    'Sensor: %.1f deg lat, %.1f deg lon'], ...
    orbitAltitude, rad2deg(sensorLatitude), rad2deg(sensorLongitude));
title(layout, figureTitle);

%% Local plotting helpers
function plotMoon(moonX, moonY, moonZ)
surf(moonX, moonY, moonZ, ...
    "FaceColor", [0.65, 0.65, 0.65], ...
    "EdgeColor", "none", ...
    "FaceAlpha", 0.8);
end

function formatFrameAxes(frameTitle, xLabelText, yLabelText, zLabelText)
axis equal;
grid on;
box on;
view(3);
xlabel([xLabelText, " (km)"]);
ylabel([yLabelText, " (km)"]);
zlabel([zLabelText, " (km)"]);
title(frameTitle);
end
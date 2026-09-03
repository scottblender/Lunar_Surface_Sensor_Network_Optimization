%% testMultiRsoFilteredVisibility
% Test the fully filtered terrain and celestial visibility database for
% multiple selenocentric RSOs.
%
% Earth and Sun are screened using one center-referenced minimum angular
% separation. For each body, the effective threshold is the larger of the
% configured minimum separation and the physical occultation angle. Thus a
% zero configured angle degenerates exactly to physical occultation.
%
% Lunar obstruction is handled only by the surface terrain/horizon gate.

clear;
close all;
clc;

%% Project paths and required functions

testDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(testDirectory);
sourceDirectory = fullfile(projectRoot,"src");

assert(isfolder(sourceDirectory), ...
    "Source directory not found: %s",sourceDirectory);

addpath(sourceDirectory);
rehash path;

requiredFunctions = [
    "orbitDynamics.propagateLunarOrbit"
    "referenceFrames.moonRotating"
    "referenceFrames.topographic"
    "digitalElevationModel.buildMaximumTerrainHorizonDatabase"
    "optimization.buildTerrainAwareLosDatabase"
    "optimization.buildFilteredVisibilityDatabase"
    "constraints.celestialVisibility"
];

for functionIndex = 1:length(requiredFunctions)
    functionName = requiredFunctions(functionIndex);

    assert(~isempty(which(functionName)), ...
        "%s was not found.",functionName);
end

%% Load and process DEM

demPath = fullfile( ...
    projectRoot,"data","new_lunar_interpolant_model.mat");

if ~isfile(demPath)
    demPath = fullfile( ...
        testDirectory,"new_lunar_interpolant_model.mat");
end

assert(isfile(demPath),"DEM file was not found.");

demData = load(demPath,"F");

assert(isfield(demData,"F"), ...
    "DEM file must contain a variable named F.");

sourceDem = demData.F;

latitudeGrid = deg2rad(sourceDem.GridVectors{1}(:));
longitudeGrid = deg2rad(sourceDem.GridVectors{2}(:));
elevationGrid = sourceDem.Values;

if longitudeGrid(end) < 2*pi
    longitudeGrid = [longitudeGrid;2*pi];
    elevationGrid = [elevationGrid,elevationGrid(:,1)];
end

dem = griddedInterpolant( ...
    {latitudeGrid,longitudeGrid}, ...
    elevationGrid, ...
    "linear", ...
    "nearest");

%% Constants

moonRadius = 1737.4;                  % km
moonMu = 4902.800066;                 % km^3/s^2
earthRadius = 6378.1366;              % km
sunRadius = 695700;                   % km

earthMoonDistance = 384400;           % km
sunMoonDistance = 149597870.7;        % km

moonSiderealPeriod = 27.321661*86400;
moonAngularRate = 2*pi/moonSiderealPeriod;

earthDirectionRate = 2*pi/moonSiderealPeriod;
sunDirectionRate = 2*pi/(365.256363004*86400);

theta0 = 0;

instrumentMinimumElevation = deg2rad(0);
horizonMargin = deg2rad(0);

% One center-referenced keep-out/minimum separation is applied to both
% Earth and Sun. This is a test value, not an instrument requirement.
minimumAngularSeparation = deg2rad(20);

%% Candidate sensor set: 24 locations across the south-polar band

candidateLatitudeDegrees = [ ...
    -89.5
    -85.0
    -80.0
    -75.5
];

candidateLongitudeDegrees = (0:60:300).';

[longitudeMesh,latitudeMesh] = meshgrid( ...
    candidateLongitudeDegrees, ...
    candidateLatitudeDegrees);

candidateLatitudes = deg2rad(latitudeMesh(:));
candidateLongitudes = deg2rad(longitudeMesh(:));

numberOfSensors = length(candidateLatitudes);

assert(numberOfSensors == 24, ...
    "The test should contain 24 candidate sensors.");

%% Terrain horizon database

maximumTerrainRange = 100;            % km
terrainRangeStep = 0.5;               % km
horizonAzimuthStep = deg2rad(2);      % rad

[horizonAzimuths,maximumTerrainElevation] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        candidateLatitudes, ...
        candidateLongitudes, ...
        dem, ...
        maximumTerrainRange, ...
        terrainRangeStep, ...
        horizonAzimuthStep, ...
        moonRadius);

%% Multi-RSO truth set

rsoNames = [
    "LRO-like 50 km polar"
    "Chandrayaan-1-like 100 km polar"
    "200 km, 60 deg inclined"
];

numberOfObjects = length(rsoNames);
truthInitialStates = zeros(6,numberOfObjects);

truthInitialStates(:,1) = circularOrbitState( ...
    moonRadius + 50,deg2rad(90),deg2rad(37),0,moonMu);

truthInitialStates(:,2) = circularOrbitState( ...
    moonRadius + 100,deg2rad(90),deg2rad(120),deg2rad(35),moonMu);

truthInitialStates(:,3) = circularOrbitState( ...
    moonRadius + 200,deg2rad(60),deg2rad(205.2),deg2rad(-90),moonMu);

outputStep = 60;                      % s
finalTime = 8*3600;                   % s
times = (0:outputStep:finalTime).';

numberOfTimes = length(times);

targetStateHistories = ...
    zeros(6,numberOfTimes,numberOfObjects);

for objectIndex = 1:numberOfObjects
    [propagatedTimes,propagatedStates] = ...
        orbitDynamics.propagateLunarOrbit( ...
            truthInitialStates(:,objectIndex), ...
            times, ...
            moonMu=moonMu);

    assert(max(abs(propagatedTimes - times)) < 1e-9, ...
        "The time grid changed for object %d.",objectIndex);

    targetStateHistories(:,:,objectIndex) = propagatedStates.';
end

%% Generic-time Earth and Sun histories in MCI
% These phases define a repeatable geometry test. Replace these histories
% with epoch-dependent ephemerides for a dated mission analysis.

earthPhase0 = deg2rad(20);
sunPhase0 = deg2rad(145);
solarInclination = deg2rad(5.145);

earthPhase = earthPhase0 + earthDirectionRate*times.';

earthPositionsMci = earthMoonDistance*[ ...
    cos(earthPhase)
    sin(earthPhase)
    zeros(1,numberOfTimes)
];

sunPhase = sunPhase0 + sunDirectionRate*times.';

sunPlanarPositions = sunMoonDistance*[ ...
    cos(sunPhase)
    sin(sunPhase)
    zeros(1,numberOfTimes)
];

solarInclinationRotation = [ ...
    1,0,0
    0,cos(solarInclination),-sin(solarInclination)
    0,sin(solarInclination), cos(solarInclination)
];

sunPositionsMci = ...
    solarInclinationRotation*sunPlanarPositions;

%% Build fully filtered database

[filteredAvailability,diagnostics] = ...
    optimization.buildFilteredVisibilityDatabase( ...
        times, ...
        targetStateHistories, ...
        candidateLatitudes, ...
        candidateLongitudes, ...
        dem, ...
        horizonAzimuths, ...
        maximumTerrainElevation, ...
        earthPositionsMci, ...
        sunPositionsMci, ...
        instrumentMinimumElevation, ...
        horizonMargin, ...
        earthRadius, ...
        sunRadius, ...
        minimumAngularSeparation, ...
        moonRadius, ...
        theta0, ...
        moonAngularRate);

assert(isequal(filteredAvailability,diagnostics.accepted), ...
    "The returned database does not match diagnostics.accepted.");

assert(all( ...
    filteredAvailability <= diagnostics.terrainAvailability, ...
    "all"), ...
    "The fully filtered gate exceeds terrain visibility.");

assert(all( ...
    diagnostics.earthMinimumSeparation >= minimumAngularSeparation | ...
    isinf(diagnostics.earthMinimumSeparation), ...
    "all"), ...
    "Earth required separation fell below the configured minimum.");

assert(all( ...
    diagnostics.sunMinimumSeparation >= minimumAngularSeparation | ...
    isinf(diagnostics.sunMinimumSeparation), ...
    "all"), ...
    "Sun required separation fell below the configured minimum.");

%% Count mutually exclusive rejection categories

geometricCounts = zeros(numberOfObjects,1);
terrainRejectedCounts = zeros(numberOfObjects,1);
celestialRejectedCounts = zeros(numberOfObjects,1);
acceptedCounts = zeros(numberOfObjects,1);

earthBlockedRawCounts = zeros(numberOfObjects,1);
sunBlockedRawCounts = zeros(numberOfObjects,1);

for objectIndex = 1:numberOfObjects
    geometricCounts(objectIndex) = sum( ...
        diagnostics.geometricAvailability(:,:,objectIndex),"all");

    terrainRejectedCounts(objectIndex) = sum( ...
        diagnostics.terrainRejected(:,:,objectIndex),"all");

    celestialRejectedCounts(objectIndex) = sum( ...
        diagnostics.celestialRejected(:,:,objectIndex),"all");

    acceptedCounts(objectIndex) = sum( ...
        diagnostics.accepted(:,:,objectIndex),"all");

    terrainGate = diagnostics.terrainAvailability(:,:,objectIndex);

    earthBlockedRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.earthBlocked(:,:,objectIndex),"all");

    sunBlockedRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.sunBlocked(:,:,objectIndex),"all");
end

reconstructedCounts = ...
    terrainRejectedCounts + celestialRejectedCounts + acceptedCounts;

assert(all(reconstructedCounts == geometricCounts), ...
    "The mutually exclusive rejection counts do not reconcile.");

assert(all(acceptedCounts > 0), ...
    "At least one RSO has no fully accepted observations.");

%% Verify zero-angle degeneration to physical occultation

sampleObserver = [moonRadius;0;0];
sampleTarget = [moonRadius + 100;0;0];
sampleEarth = [earthMoonDistance;0;0];
sampleSun = [-sunMoonDistance;0;0];

[visibleZeroAngle,earthBlockedZeroAngle,sunBlockedZeroAngle] = ...
    constraints.celestialVisibility( ...
        sampleObserver, ...
        sampleTarget, ...
        sampleEarth, ...
        sampleSun, ...
        earthRadius, ...
        sunRadius, ...
        0);

assert(visibleZeroAngle, ...
    "A target in front of both bodies should remain visible at zero separation.");
assert(~earthBlockedZeroAngle && ~sunBlockedZeroAngle, ...
    "Zero minimum separation should reduce to physical occultation only.");

%% Print results

fprintf("Fully filtered multi-RSO visibility comparison\n");
fprintf("Minimum angular separation: %.3f deg\n", ...
    rad2deg(minimumAngularSeparation));

for objectIndex = 1:numberOfObjects
    fprintf("\n%s\n",char(rsoNames(objectIndex)));
    fprintf("  Geometric opportunities:       %d\n", ...
        geometricCounts(objectIndex));
    fprintf("  Terrain rejected:              %d\n", ...
        terrainRejectedCounts(objectIndex));
    fprintf("  Celestial rejected:            %d\n", ...
        celestialRejectedCounts(objectIndex));
    fprintf("  Fully accepted:                %d\n", ...
        acceptedCounts(objectIndex));
    fprintf("  Raw Earth blocked:             %d\n", ...
        earthBlockedRawCounts(objectIndex));
    fprintf("  Raw Sun blocked:               %d\n", ...
        sunBlockedRawCounts(objectIndex));
end

fprintf("\nOverall\n");
fprintf("  Geometric opportunities:       %d\n",sum(geometricCounts));
fprintf("  Terrain rejected:              %d\n",sum(terrainRejectedCounts));
fprintf("  Celestial rejected:            %d\n",sum(celestialRejectedCounts));
fprintf("  Fully accepted:                %d\n",sum(acceptedCounts));

fprintf("\ntestMultiRsoFilteredVisibility passed.\n");

%% Plot mutually exclusive outcome split

outcomeCounts = [ ...
    terrainRejectedCounts, ...
    celestialRejectedCounts, ...
    acceptedCounts ...
];

objectCategories = categorical(rsoNames,rsoNames);

figure( ...
    "Color","white", ...
    "Name","Multi-RSO Filtered Visibility Outcomes");

barHandles = bar(objectCategories,outcomeCounts,"stacked");

grid on;
ylabel("Geometric sensor-epochs");
title("Mutually Exclusive Visibility Outcomes");

legend( ...
    barHandles, ...
    "Terrain rejected", ...
    "Celestial rejected", ...
    "Fully accepted", ...
    "Location","bestoutside");

%% Local function

function state = circularOrbitState( ...
    orbitRadius,inclination,raan,trueAnomaly,moonMu)

rotationZ = [ ...
     cos(raan),-sin(raan),0
     sin(raan), cos(raan),0
     0,0,1
];

rotationX = [ ...
    1,0,0
    0,cos(inclination),-sin(inclination)
    0,sin(inclination), cos(inclination)
];

perifocalPosition = orbitRadius*[ ...
    cos(trueAnomaly)
    sin(trueAnomaly)
    0
];

circularSpeed = sqrt(moonMu/orbitRadius);

perifocalVelocity = circularSpeed*[ ...
    -sin(trueAnomaly)
     cos(trueAnomaly)
    0
];

rotation = rotationZ*rotationX;

state = [ ...
    rotation*perifocalPosition
    rotation*perifocalVelocity
];

end

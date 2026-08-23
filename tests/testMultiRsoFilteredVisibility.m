%% testMultiRsoFilteredVisibility
% Test the fully filtered terrain and celestial visibility database for
% multiple selenocentric RSOs.
%
% The reported terrain, occlusion, exclusion, and accepted counts are
% mutually exclusive and sum to the geometric opportunities. Raw Earth
% and Sun failure counts are also printed and may overlap.

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
    "constraints.sphericalBodyOcclusion"
    "constraints.brightBodyExclusion"
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

% These are angular margins beyond the apparent body limbs. They are test
% values, not instrument requirements.
earthLimbMargin = deg2rad(10);
sunLimbMargin = deg2rad(20);

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
        earthLimbMargin, ...
        sunLimbMargin, ...
        moonRadius, ...
        theta0, ...
        moonAngularRate);

assert(isequal(filteredAvailability,diagnostics.accepted), ...
    "The returned database does not match diagnostics.accepted.");

assert(all( ...
    filteredAvailability <= diagnostics.terrainAvailability, ...
    "all"), ...
    "The fully filtered gate exceeds terrain visibility.");

%% Count mutually exclusive rejection categories

geometricCounts = zeros(numberOfObjects,1);
terrainRejectedCounts = zeros(numberOfObjects,1);
occlusionRejectedCounts = zeros(numberOfObjects,1);
exclusionRejectedCounts = zeros(numberOfObjects,1);
acceptedCounts = zeros(numberOfObjects,1);

earthOcclusionRawCounts = zeros(numberOfObjects,1);
sunOcclusionRawCounts = zeros(numberOfObjects,1);
earthExclusionRawCounts = zeros(numberOfObjects,1);
sunExclusionRawCounts = zeros(numberOfObjects,1);

for objectIndex = 1:numberOfObjects
    geometricCounts(objectIndex) = sum( ...
        diagnostics.geometricAvailability(:,:,objectIndex),"all");

    terrainRejectedCounts(objectIndex) = sum( ...
        diagnostics.terrainRejected(:,:,objectIndex),"all");

    occlusionRejectedCounts(objectIndex) = sum( ...
        diagnostics.occlusionRejected(:,:,objectIndex),"all");

    exclusionRejectedCounts(objectIndex) = sum( ...
        diagnostics.exclusionRejected(:,:,objectIndex),"all");

    acceptedCounts(objectIndex) = sum( ...
        diagnostics.accepted(:,:,objectIndex),"all");

    % Raw celestial failures are counted only among terrain-approved
    % opportunities. Earth and Sun masks may overlap.
    terrainGate = diagnostics.terrainAvailability(:,:,objectIndex);

    earthOcclusionRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.earthOccluded(:,:,objectIndex),"all");

    sunOcclusionRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.sunOccluded(:,:,objectIndex),"all");

    earthExclusionRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.earthExcluded(:,:,objectIndex),"all");

    sunExclusionRawCounts(objectIndex) = sum( ...
        terrainGate & diagnostics.sunExcluded(:,:,objectIndex),"all");
end

reconstructedCounts = ...
    terrainRejectedCounts + ...
    occlusionRejectedCounts + ...
    exclusionRejectedCounts + ...
    acceptedCounts;

assert(all(reconstructedCounts == geometricCounts), ...
    "The mutually exclusive rejection counts do not reconcile.");

assert(all(acceptedCounts > 0), ...
    "At least one RSO has no fully accepted observations.");

%% Print results

fprintf("Fully filtered multi-RSO visibility comparison\n");

for objectIndex = 1:numberOfObjects
    fprintf("\n%s\n",char(rsoNames(objectIndex)));
    fprintf("  Geometric opportunities:       %d\n", ...
        geometricCounts(objectIndex));
    fprintf("  Terrain rejected:              %d\n", ...
        terrainRejectedCounts(objectIndex));
    fprintf("  Occlusion rejected:            %d\n", ...
        occlusionRejectedCounts(objectIndex));
    fprintf("  Exclusion rejected:            %d\n", ...
        exclusionRejectedCounts(objectIndex));
    fprintf("  Fully accepted:                %d\n", ...
        acceptedCounts(objectIndex));

    fprintf("  Raw Earth occultations:        %d\n", ...
        earthOcclusionRawCounts(objectIndex));
    fprintf("  Raw Sun occultations:          %d\n", ...
        sunOcclusionRawCounts(objectIndex));
    fprintf("  Raw Earth exclusions:          %d\n", ...
        earthExclusionRawCounts(objectIndex));
    fprintf("  Raw Sun exclusions:            %d\n", ...
        sunExclusionRawCounts(objectIndex));
end

fprintf("\nOverall\n");
fprintf("  Geometric opportunities:       %d\n",sum(geometricCounts));
fprintf("  Terrain rejected:              %d\n",sum(terrainRejectedCounts));
fprintf("  Occlusion rejected:            %d\n",sum(occlusionRejectedCounts));
fprintf("  Exclusion rejected:            %d\n",sum(exclusionRejectedCounts));
fprintf("  Fully accepted:                %d\n",sum(acceptedCounts));

fprintf("\ntestMultiRsoFilteredVisibility passed.\n");

%% Plot mutually exclusive outcome split

outcomeCounts = [ ...
    terrainRejectedCounts, ...
    occlusionRejectedCounts, ...
    exclusionRejectedCounts, ...
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
    "Occlusion rejected", ...
    "Exclusion rejected", ...
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

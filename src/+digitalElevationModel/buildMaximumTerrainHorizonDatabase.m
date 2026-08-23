function [ ...
    horizonAzimuths, ...
    maximumTerrainElevation, ...
    maximumFeatureRange, ...
    sensorElevations, ...
    maximumFeatureElevations ...
] = buildMaximumTerrainHorizonDatabase( ...
    candidateLatitudes, ...
    candidateLongitudes, ...
    dem, ...
    maximumTerrainRange, ...
    terrainRangeStep, ...
    horizonAzimuthStep, ...
    moonRadius)
% BUILDMAXIMUMTERRAINHORIZONDATABASE
% Builds a terrain-horizon profile for every candidate surface sensor.
%
% For each candidate sensor and azimuth, the function searches radially
% through the DEM and identifies the terrain sample having the maximum
% apparent elevation angle.
%
% Inputs:
%   candidateLatitudes       - Sx1 sensor latitudes, rad
%   candidateLongitudes      - Sx1 sensor longitudes, rad
%   dem                      - griddedInterpolant, queried using rad
%   maximumTerrainRange      - maximum surface search distance, km
%   terrainRangeStep         - radial terrain sampling distance, km
%   horizonAzimuthStep       - requested azimuth spacing, rad
%   moonRadius               - lunar reference radius, km
%
% Outputs:
%   horizonAzimuths          - Ax1 azimuth grid, rad
%   maximumTerrainElevation  - SxA maximum apparent terrain angle, rad
%   maximumFeatureRange      - SxA range to horizon-defining feature, km
%   sensorElevations         - Sx1 candidate DEM elevations, km
%   maximumFeatureElevations - SxA DEM elevation of horizon-defining
%                              feature, km
%
% The output maximumTerrainElevation is an angle despite the historical
% variable name. It represents
%
%   max_d atan2(vertical terrain displacement,
%               horizontal terrain displacement).
%
% The first and last azimuth columns correspond to 0 and 2*pi and are
% identical, providing a periodic interpolation boundary.

arguments
    candidateLatitudes (:,1) double
    candidateLongitudes (:,1) double
    dem (1,1) griddedInterpolant
    maximumTerrainRange (1,1) double {mustBePositive}
    terrainRangeStep (1,1) double {mustBePositive}
    horizonAzimuthStep (1,1) double {mustBePositive}
    moonRadius (1,1) double {mustBePositive} = 1737.4
end

numberOfCandidates = numel(candidateLatitudes);

if numel(candidateLongitudes) ~= numberOfCandidates

    error( ...
        "Candidate latitude and longitude arrays must have equal length.");
end

if any(abs(candidateLatitudes) > pi/2)

    error("Candidate latitudes must be between -pi/2 and pi/2.");
end

%% Construct radial distance grid

terrainRanges = ...
    (terrainRangeStep:terrainRangeStep:maximumTerrainRange).';

if isempty(terrainRanges)

    terrainRanges = maximumTerrainRange;

elseif terrainRanges(end) < maximumTerrainRange

    terrainRanges(end + 1,1) = maximumTerrainRange;
end

numberOfRanges = numel(terrainRanges);

centralAngles = terrainRanges / moonRadius;

sinCentralAngles = sin(centralAngles);
cosCentralAngles = cos(centralAngles);

%% Construct periodic azimuth grid

numberOfAzimuthIntervals = max( ...
    1, ...
    ceil(2*pi / horizonAzimuthStep));

activeHorizonAzimuths = ...
    (0:numberOfAzimuthIntervals - 1).' * ...
    (2*pi / numberOfAzimuthIntervals);

% Include 2*pi as a periodic copy of the zero-azimuth column.

horizonAzimuths = [
    activeHorizonAzimuths
    2*pi
];

numberOfActiveAzimuths = ...
    numel(activeHorizonAzimuths);

numberOfAzimuths = ...
    numel(horizonAzimuths);

%% Validate DEM latitude coverage

demLatitudeGrid = dem.GridVectors{1}(:);

maximumCentralAngle = ...
    maximumTerrainRange / moonRadius;

requiredMinimumLatitude = max( ...
    -pi/2, ...
    min(candidateLatitudes) - maximumCentralAngle);

requiredMaximumLatitude = min( ...
    pi/2, ...
    max(candidateLatitudes) + maximumCentralAngle);

latitudeTolerance = 1e-10;

if demLatitudeGrid(1) > ...
        requiredMinimumLatitude + latitudeTolerance || ...
        demLatitudeGrid(end) < ...
        requiredMaximumLatitude - latitudeTolerance

    error( ...
        ["The DEM does not contain enough latitude padding for the " ...
         "requested candidate band and terrain search range."]);
end

%% Query candidate sensor elevations

candidateLongitudesForDem = wrapLongitudeForDem( ...
    candidateLongitudes, ...
    dem.GridVectors{2});

sensorElevations = dem( ...
    candidateLatitudes, ...
    candidateLongitudesForDem);

sensorElevations = sensorElevations(:);

if any(~isfinite(sensorElevations))

    error("One or more candidate sensor elevations are nonfinite.");
end

%% Allocate terrain-horizon database

maximumTerrainElevation = nan( ...
    numberOfCandidates, ...
    numberOfAzimuths);

maximumFeatureRange = nan( ...
    numberOfCandidates, ...
    numberOfAzimuths);

maximumFeatureElevations = nan( ...
    numberOfCandidates, ...
    numberOfAzimuths);

azimuthRow = activeHorizonAzimuths.';

sinAzimuth = sin(azimuthRow);
cosAzimuth = cos(azimuthRow);

columnOffsets = ...
    (0:numberOfActiveAzimuths - 1) * numberOfRanges;

%% Build terrain horizon for each candidate

for sensorIndex = 1:numberOfCandidates

    sensorLatitude = ...
        candidateLatitudes(sensorIndex);

    sensorLongitude = ...
        candidateLongitudes(sensorIndex);

    sensorElevation = ...
        sensorElevations(sensorIndex);

    sensorRadius = ...
        moonRadius + sensorElevation;

    sinSensorLatitude = sin(sensorLatitude);
    cosSensorLatitude = cos(sensorLatitude);

    % Destination latitude along every range and azimuth.
    %
    % Each resulting array is numberOfRanges-by-numberOfActiveAzimuths.

    sinTerrainLatitudes = ...
        sinSensorLatitude .* cosCentralAngles + ...
        cosSensorLatitude .* sinCentralAngles .* cosAzimuth;

    sinTerrainLatitudes = max( ...
        -1, ...
        min(1, sinTerrainLatitudes));

    terrainLatitudes = ...
        asin(sinTerrainLatitudes);

    % Great-circle destination longitude.

    longitudeNumerator = ...
        sinAzimuth .* ...
        sinCentralAngles .* ...
        cosSensorLatitude;

    longitudeDenominator = ...
        cosCentralAngles - ...
        sinSensorLatitude .* sinTerrainLatitudes;

    terrainLongitudes = ...
        sensorLongitude + ...
        atan2( ...
            longitudeNumerator, ...
            longitudeDenominator);

    terrainLongitudesForDem = ...
        wrapLongitudeForDem( ...
            terrainLongitudes, ...
            dem.GridVectors{2});

    terrainElevations = dem( ...
        terrainLatitudes, ...
        terrainLongitudesForDem);

    if any(~isfinite(terrainElevations), "all")

        error( ...
            "The DEM returned a nonfinite terrain elevation.");
    end

    terrainRadii = ...
        moonRadius + terrainElevations;

    % Exact local topographic geometry on a spherical reference body.
    %
    % Horizontal component:
    %
    %   rhoHorizontal = rTerrain sin(delta)
    %
    % Vertical component:
    %
    %   rhoUp = rTerrain cos(delta) - rSensor

    terrainHorizontalDistance = ...
        terrainRadii .* sinCentralAngles;

    terrainVerticalDistance = ...
        terrainRadii .* cosCentralAngles - ...
        sensorRadius;

    apparentTerrainElevation = atan2( ...
        terrainVerticalDistance, ...
        terrainHorizontalDistance);

    % Find the terrain range producing the maximum apparent elevation for
    % every azimuth.

    [ ...
        maximumAngles, ...
        maximumRangeIndices ...
    ] = max(apparentTerrainElevation, [], 1);

    featureLinearIndices = ...
        maximumRangeIndices + columnOffsets;

    maximumTerrainElevation( ...
        sensorIndex, ...
        1:numberOfActiveAzimuths) = maximumAngles;

    maximumFeatureRange( ...
        sensorIndex, ...
        1:numberOfActiveAzimuths) = ...
        terrainRanges(maximumRangeIndices);

    maximumFeatureElevations( ...
        sensorIndex, ...
        1:numberOfActiveAzimuths) = ...
        terrainElevations(featureLinearIndices);

    % Copy the zero-azimuth result to 2*pi.

    maximumTerrainElevation( ...
        sensorIndex, ...
        numberOfAzimuths) = ...
        maximumTerrainElevation(sensorIndex,1);

    maximumFeatureRange( ...
        sensorIndex, ...
        numberOfAzimuths) = ...
        maximumFeatureRange(sensorIndex,1);

    maximumFeatureElevations( ...
        sensorIndex, ...
        numberOfAzimuths) = ...
        maximumFeatureElevations(sensorIndex,1);
end
end

function wrappedLongitudes = wrapLongitudeForDem( ...
    longitudes, ...
    demLongitudeGrid)
% Wraps longitude to match either a 0-to-2*pi or -pi-to-pi DEM.

demLongitudeGrid = demLongitudeGrid(:);

if demLongitudeGrid(1) >= -1e-10 && ...
        demLongitudeGrid(end) > pi

    wrappedLongitudes = mod(longitudes, 2*pi);

else

    wrappedLongitudes = ...
        mod(longitudes + pi, 2*pi) - pi;
end
end
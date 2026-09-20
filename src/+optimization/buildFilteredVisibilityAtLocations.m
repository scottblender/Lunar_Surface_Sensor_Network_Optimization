function filteredAvailability = buildFilteredVisibilityAtLocations( ...
    database,sensorLatitudesRad,sensorLongitudesRad,userConfig)
% BUILDFILTEREDVISIBILITYATLOCATIONS Evaluate the production visibility gate
% at arbitrary lunar-surface coordinates.
%
% Candidate-grid locations reuse the frozen filtered-availability database.
% Off-grid locations (for example, optimized sites from the 20260915
% restricted-domain campaign) retain their original latitude/longitude and
% recompute terrain horizons plus celestial screening using the current
% frozen physical model. No nearest-grid snapping is performed.

arguments
    database (1,1) struct
    sensorLatitudesRad (:,1) double
    sensorLongitudesRad (:,1) double
    userConfig (1,1) struct = struct()
end

sensorLatitudesRad = double(sensorLatitudesRad(:));
sensorLongitudesRad = mod(double(sensorLongitudesRad(:)),2*pi);
assert(~isempty(sensorLatitudesRad), ...
    "buildFilteredVisibilityAtLocations:EmptyNetwork", ...
    "At least one sensor location is required.");
assert(numel(sensorLatitudesRad) == numel(sensorLongitudesRad), ...
    "buildFilteredVisibilityAtLocations:CoordinateSizeMismatch", ...
    "Sensor latitude and longitude arrays must have equal length.");

[candidateIndices,exactMatch] = matchCandidateLocations( ...
    database,sensorLatitudesRad,sensorLongitudesRad);

if exactMatch
    if isfield(database.visibility,"candidateChunks") && ...
            ~isempty(database.visibility.candidateChunks)
        filteredAvailability = optimization.loadChunkedCandidateData( ...
            database,candidateIndices,"filteredAvailability");
    else
        filteredAvailability = ...
            database.visibility.filteredAvailability(candidateIndices,:,:);
    end
    return
end

moonRadiusKm = database.config.moon.radiusKm;
demFile = resolveDemFile(database,userConfig);
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,moonRadiusKm,24,48);

fprintf(['  Recomputing filtered visibility for %d off-grid optimized ' ...
    'sensor locations.\n'],numel(sensorLatitudesRad));

[horizonAzimuthsRad,maximumTerrainElevationRad] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        sensorLatitudesRad,sensorLongitudesRad,dem, ...
        database.config.terrain.maximumRangeKm, ...
        database.config.terrain.rangeStepKm, ...
        database.config.terrain.horizonAzimuthStepRad, ...
        moonRadiusKm);

trackingTimes = double(database.tracking.times(:));
truthStateHistories = double(database.truth.optimizationStateHistories);
[earthPositionsMci,sunPositionsMci] = selectEphemerides( ...
    database,trackingTimes);

filteredAvailability = optimization.buildFilteredVisibilityDatabase( ...
    trackingTimes,truthStateHistories, ...
    sensorLatitudesRad,sensorLongitudesRad, ...
    dem,horizonAzimuthsRad,maximumTerrainElevationRad, ...
    earthPositionsMci,sunPositionsMci, ...
    database.config.visibility.minimumElevationRad, ...
    database.config.terrain.horizonMarginRad, ...
    database.config.visibility.earthRadiusKm, ...
    database.config.visibility.sunRadiusKm, ...
    database.config.visibility.sunMinimumAngularSeparationRad, ...
    moonRadiusKm,database.config.moon.theta0Rad, ...
    2*pi/database.config.moon.siderealPeriodSeconds, ...
    database.config.visibility.earthMinimumAngularSeparationRad);
end

function [indices,exactMatch] = matchCandidateLocations( ...
    database,latitudesRad,longitudesRad)

candidateLatitudesRad = double(database.candidates.latitudesRad(:));
candidateLongitudesRad = mod( ...
    double(database.candidates.longitudesRad(:)),2*pi);

indices = zeros(numel(latitudesRad),1);
exactMatch = true;
for sensorIndex = 1:numel(latitudesRad)
    latitudeDifference = candidateLatitudesRad-latitudesRad(sensorIndex);
    longitudeDifference = atan2( ...
        sin(candidateLongitudesRad-longitudesRad(sensorIndex)), ...
        cos(candidateLongitudesRad-longitudesRad(sensorIndex)));
    [distance,index] = min(hypot(latitudeDifference,longitudeDifference));
    indices(sensorIndex) = index;
    exactMatch = exactMatch && distance < 1e-10;
end
end

function [earthPositionsMci,sunPositionsMci] = ...
    selectEphemerides(database,trackingTimes)

fullTimes = double(database.truth.times(:));
indices = zeros(numel(trackingTimes),1);
for timeIndex = 1:numel(trackingTimes)
    [difference,index] = min(abs(fullTimes-trackingTimes(timeIndex)));
    assert(difference < 1e-8, ...
        sprintf('Could not align ephemerides with tracking time %.6f s.', ...
        trackingTimes(timeIndex)));
    indices(timeIndex) = index;
end

earthPositionsMci = double(database.ephemeris.earthPositionsMci(:,indices));
sunPositionsMci = double(database.ephemeris.sunPositionsMci(:,indices));
end

function demFile = resolveDemFile(database,userConfig)
candidateFiles = strings(0,1);

if isfield(userConfig,"demFile") && ...
        strlength(string(userConfig.demFile)) > 0
    candidateFiles(end+1,1) = string(userConfig.demFile);
end
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateFiles(end+1,1) = string(database.meta.demSource);
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateFiles(end+1,1) = string(database.config.demSource);
end

sourceDirectory = fileparts(fileparts(mfilename("fullpath")));
projectRoot = fileparts(sourceDirectory);
candidateFiles(end+1,1) = ...
    fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat");
candidateFiles(end+1,1) = ...
    fullfile(projectRoot,"data","Full_Resolution_DEM.mat");

for fileIndex = 1:numel(candidateFiles)
    if strlength(candidateFiles(fileIndex)) > 0 && ...
            isfile(candidateFiles(fileIndex))
        demFile = candidateFiles(fileIndex);
        return
    end
end

error("buildFilteredVisibilityAtLocations:DemNotFound", ...
    "No production DEM could be resolved for off-grid visibility.");
end

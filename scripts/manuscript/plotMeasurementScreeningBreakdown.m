function plotInfo = plotMeasurementScreeningBreakdown( ...
    fullCampaign,restrictedCampaign,userConfig)
% PLOTMEASUREMENTSCREENINGBREAKDOWN RSO-specific constraint screening.
%
% Figure 14 shows every design RSO in two aligned horizontal-bar panels,
% one for each domain. Each stack partitions all sensor/epoch opportunities into
% mutually exclusive rejection categories plus accepted measurements.

arguments
    fullCampaign (1,1) struct
    restrictedCampaign (1,1) struct = struct()
    userConfig (1,1) struct = struct()
end

assert(~isempty(fieldnames(restrictedCampaign)), ...
    "The constraint-screening figure requires the matched South Pole campaign.");

style = publicationPlotStyle();
outputDirectory = string(fullCampaign.outputDirectory);
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

objectiveMode = "information";
if isfield(userConfig,"comparisonObjective")
    objectiveMode = lower(string(userConfig.comparisonObjective));
end
networkSize = 10;
if isfield(userConfig,"comparisonNetworkSize")
    networkSize = double(userConfig.comparisonNetworkSize);
end
exportDiagnosticTables = false;
if isfield(userConfig,"exportDiagnosticTables")
    exportDiagnosticTables = logical(userConfig.exportDiagnosticTables);
end

validateattributes(networkSize,{'numeric'},{'scalar','integer','positive'});
assert(any(lower(string(fullCampaign.configuration.objectiveModes))==objectiveMode), ...
    "Requested comparison objective is unavailable in the full campaign.");
assert(any(double(fullCampaign.configuration.networkSizes)==networkSize), ...
    "Requested comparison network size is unavailable in the full campaign.");
assert(any(lower(string(restrictedCampaign.configuration.objectiveModes))==objectiveMode), ...
    "Requested comparison objective is unavailable in the South Pole campaign.");
assert(any(double(restrictedCampaign.configuration.networkSizes)==networkSize), ...
    "Requested comparison network size is unavailable in the South Pole campaign.");

categoryNames = [ ...
    "Below local horizon", ...
    "Terrain blocked", ...
    "Earth blocked", ...
    "Sun blocked", ...
    "Earth + Sun", ...
    "Accepted"];
categoryColors = [ ...
    style.grayColor; ...
    style.orangeColor; ...
    style.blueColor; ...
    style.magentaColor; ...
    0.38 0.24 0.54; ...
    style.greenColor];

[fullPercent,fullCount,fullRows] = computeCampaignAllRsos( ...
    fullCampaign,userConfig,"Southern Hemisphere", ...
    objectiveMode,networkSize);
[polarPercent,polarCount,polarRows] = computeCampaignAllRsos( ...
    restrictedCampaign,userConfig,"South Pole", ...
    objectiveMode,networkSize);

numberOfRsos = size(fullPercent,1);
assert(size(polarPercent,1)==numberOfRsos, ...
    "Full-domain and South Pole campaigns contain different RSO counts.");

fig = plotConstraintScreeningPanels(fullPercent,polarPercent, ...
    categoryNames,categoryColors,networkSize,objectiveMode);
outputFile = fullfile(outputDirectory,"constraint_screening_all_rsos.eps");
exportManuscriptFigure(fig,string(outputFile),fig.Position(3),fig.Position(4));

summaryTable = [fullRows;polarRows];
summaryFile = "";
if exportDiagnosticTables
    tableDirectory = fullfile(outputDirectory,"tables");
    if ~isfolder(tableDirectory), mkdir(tableDirectory); end
    summaryFile = fullfile(tableDirectory,"constraint_screening_all_rsos.csv");
    writetable(summaryTable,summaryFile);
end

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.objectiveMode = objectiveMode;
plotInfo.networkSize = networkSize;
plotInfo.numberOfRsos = numberOfRsos;
plotInfo.fullPercent = fullPercent;
plotInfo.polarPercent = polarPercent;
plotInfo.fullCount = fullCount;
plotInfo.polarCount = polarCount;
plotInfo.summaryTable = summaryTable;
plotInfo.summaryFile = string(summaryFile);

fprintf("All-RSO constraint-screening figure:\n  %s\n",outputFile);
end

function [percentages,counts,rows] = computeCampaignAllRsos( ...
    campaign,userConfig,domainLabel,objectiveMode,networkSize)

database = campaign.database;
config = campaign.configuration;
projectRoot = string(campaign.projectRoot);

objectiveIndex = find(lower(string(config.objectiveModes))==objectiveMode,1);
networkIndex = find(double(config.networkSizes)==networkSize,1);
assert(~isempty(objectiveIndex) && ~isempty(networkIndex), ...
    "Requested objective/network-size case is unavailable.");

truthStates = double(database.truth.optimizationStateHistories);
numberOfRsos = size(truthStates,3);

demFile = resolveDemFile(projectRoot,database,userConfig);
moonRadiusKm = database.config.moon.radiusKm;
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,moonRadiusKm,24,48);

studyState = campaign.studies{networkIndex,objectiveIndex};
runState = studyState.runStates{studyState.overallBestRunIndex};
sensorLatitudesRad = double(runState.bestSensorLatitudesRad(:));
sensorLongitudesRad = double(runState.bestSensorLongitudesRad(:));

trackingTimes = double(database.tracking.times(:));
[earthPositions,sunPositions] = selectEphemerides(database,trackingTimes);
[horizonAzimuthsRad,maximumTerrainElevation] = resolveSelectedTerrain( ...
    database,sensorLatitudesRad,sensorLongitudesRad,dem,moonRadiusKm);

[~,diagnostics] = optimization.buildFilteredVisibilityDatabase( ...
    trackingTimes,truthStates, ...
    sensorLatitudesRad,sensorLongitudesRad, ...
    dem,horizonAzimuthsRad,maximumTerrainElevation, ...
    earthPositions,sunPositions, ...
    database.config.visibility.minimumElevationRad, ...
    database.config.terrain.horizonMarginRad, ...
    database.config.visibility.earthRadiusKm, ...
    database.config.visibility.sunRadiusKm, ...
    database.config.visibility.sunMinimumAngularSeparationRad, ...
    moonRadiusKm,database.config.moon.theta0Rad, ...
    2*pi/database.config.moon.siderealPeriodSeconds, ...
    database.config.visibility.earthMinimumAngularSeparationRad);

counts = zeros(numberOfRsos,6);
percentages = zeros(numberOfRsos,6);
rowCells = cell(numberOfRsos,1);

for rsoIndex = 1:numberOfRsos
    geometric = diagnostics.geometricAvailability(:,:,rsoIndex);
    terrainAvailability = diagnostics.terrainAvailability(:,:,rsoIndex);
    terrainRejected = diagnostics.terrainRejected(:,:,rsoIndex);
    earthBlocked = diagnostics.earthBlocked(:,:,rsoIndex);
    sunBlocked = diagnostics.sunBlocked(:,:,rsoIndex);
    accepted = diagnostics.accepted(:,:,rsoIndex);

    masks = { ...
        ~geometric, ...
        terrainRejected, ...
        terrainAvailability & earthBlocked & ~sunBlocked, ...
        terrainAvailability & sunBlocked & ~earthBlocked, ...
        terrainAvailability & earthBlocked & sunBlocked, ...
        accepted};

    reconstructed = false(size(accepted));
    for categoryIndex = 1:numel(masks)
        reconstructed = reconstructed | masks{categoryIndex};
        counts(rsoIndex,categoryIndex) = nnz(masks{categoryIndex});
    end

    totalOpportunities = numel(accepted);
    assert(nnz(reconstructed)==totalOpportunities, ...
        "Screening categories do not reconstruct all RSO opportunities.");
    assert(sum(counts(rsoIndex,:))==totalOpportunities, ...
        "Screening categories are not mutually exclusive.");

    percentages(rsoIndex,:) = 100*counts(rsoIndex,:)/totalOpportunities;

    rowCells{rsoIndex} = table( ...
        string(domainLabel),objectiveMode,networkSize,rsoIndex,totalOpportunities, ...
        counts(rsoIndex,1),counts(rsoIndex,2),counts(rsoIndex,3), ...
        counts(rsoIndex,4),counts(rsoIndex,5),counts(rsoIndex,6), ...
        percentages(rsoIndex,1),percentages(rsoIndex,2), ...
        percentages(rsoIndex,3),percentages(rsoIndex,4), ...
        percentages(rsoIndex,5),percentages(rsoIndex,6), ...
        'VariableNames',{ ...
        'Domain','Objective','NetworkSize','RsoIndex','TotalOpportunities', ...
        'BelowHorizonCount','TerrainBlockedCount','EarthBlockedCount', ...
        'SunBlockedCount','EarthAndSunCount','AcceptedCount', ...
        'BelowHorizonPercent','TerrainBlockedPercent','EarthBlockedPercent', ...
        'SunBlockedPercent','EarthAndSunPercent','AcceptedPercent'});
end

rows = vertcat(rowCells{:});
end

function demFile = resolveDemFile(projectRoot,database,userConfig)
candidateFiles = strings(0,1);
if isfield(userConfig,"demFile") && strlength(string(userConfig.demFile)) > 0
    candidateFiles(end+1,1) = string(userConfig.demFile);
end
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateFiles(end+1,1) = string(database.meta.demSource);
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateFiles(end+1,1) = string(database.config.demSource);
end
candidateFiles(end+1,1) = fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat");
candidateFiles(end+1,1) = fullfile(projectRoot,"data","Full_Resolution_DEM.mat");

for fileIndex = 1:numel(candidateFiles)
    if strlength(candidateFiles(fileIndex)) > 0 && isfile(candidateFiles(fileIndex))
        demFile = candidateFiles(fileIndex);
        return
    end
end
error("plotMeasurementScreeningBreakdown:DemNotFound", ...
    "No production DEM could be resolved.");
end

function [earthPositions,sunPositions] = selectEphemerides(database,trackingTimes)
fullTimes = double(database.truth.times(:));
indices = zeros(numel(trackingTimes),1);
for timeIndex = 1:numel(trackingTimes)
    [difference,matchIndex] = min(abs(fullTimes-trackingTimes(timeIndex)));
    assert(difference < 1e-8, ...
        "Could not align ephemerides with tracking time %.6f s.", ...
        trackingTimes(timeIndex));
    indices(timeIndex) = matchIndex;
end
earthPositions = double(database.ephemeris.earthPositionsMci(:,indices));
sunPositions = double(database.ephemeris.sunPositionsMci(:,indices));
end

function [horizonAzimuthsRad,maximumTerrainElevationRad] = ...
    resolveSelectedTerrain(database,latitudesRad,longitudesRad,dem,moonRadiusKm)

candidateLat = double(database.candidates.latitudesRad(:));
candidateLon = mod(double(database.candidates.longitudesRad(:)),2*pi);
latitudesRad = double(latitudesRad(:));
longitudesRad = mod(double(longitudesRad(:)),2*pi);

indices = zeros(numel(latitudesRad),1);
exactMatch = true;
for sensorIndex = 1:numel(latitudesRad)
    dLat = candidateLat-latitudesRad(sensorIndex);
    dLon = atan2( ...
        sin(candidateLon-longitudesRad(sensorIndex)), ...
        cos(candidateLon-longitudesRad(sensorIndex)));
    [distance,index] = min(hypot(dLat,dLon));
    indices(sensorIndex) = index;
    exactMatch = exactMatch && distance < 1e-10;
end

if exactMatch
    horizonAzimuthsRad = database.terrain.horizonAzimuthsRad;
    if isfield(database.terrain,"candidateChunks") && ...
            ~isempty(database.terrain.candidateChunks)
        maximumTerrainElevationRad = optimization.loadChunkedCandidateData( ...
            database,indices,"maximumTerrainElevationRad");
    else
        maximumTerrainElevationRad = ...
            database.terrain.maximumTerrainElevationRad(indices,:);
    end
    return
end

fprintf("  Recomputing terrain horizons for %d off-grid optimized sensor locations.\n", ...
    numel(latitudesRad));
[horizonAzimuthsRad,maximumTerrainElevationRad] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        latitudesRad,longitudesRad,dem, ...
        database.config.terrain.maximumRangeKm, ...
        database.config.terrain.rangeStepKm, ...
        database.config.terrain.horizonAzimuthStepRad, ...
        moonRadiusKm);
end

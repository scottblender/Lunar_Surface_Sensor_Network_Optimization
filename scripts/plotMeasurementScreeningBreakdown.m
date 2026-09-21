function plotInfo = plotMeasurementScreeningBreakdown( ...
    fullCampaign,restrictedCampaign,userConfig)
% PLOTMEASUREMENTSCREENINGBREAKDOWN One RSO-specific constraint example.
%
% The manuscript constraint-violation figure compares one selected design RSO
% for the Southern Hemisphere and South Pole networks using adjacent stacked
% bars. Domain identity is carried by the x-axis labels rather than line
% style. Each stack partitions all sensor/epoch opportunities into mutually
% exclusive rejection categories plus accepted measurements.

arguments
    fullCampaign (1,1) struct
    restrictedCampaign (1,1) struct = struct()
    userConfig (1,1) struct = struct()
end

assert(~isempty(fieldnames(restrictedCampaign)), ...
    "The RSO-specific constraint plot requires the matched South Pole campaign.");

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
rsoIndex = 1;
if isfield(userConfig,"constraintExampleRsoIndex")
    rsoIndex = double(userConfig.constraintExampleRsoIndex);
end
exportDiagnosticTables = false;
if isfield(userConfig,"exportDiagnosticTables")
    exportDiagnosticTables = logical(userConfig.exportDiagnosticTables);
end

validateattributes(networkSize,{'numeric'},{'scalar','integer','positive'});
validateattributes(rsoIndex,{'numeric'},{'scalar','integer','positive'});
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

[fullPercent,fullCount,fullRow] = computeCase( ...
    fullCampaign,userConfig,"Southern Hemisphere", ...
    objectiveMode,networkSize,rsoIndex);
[polarPercent,polarCount,polarRow] = computeCase( ...
    restrictedCampaign,userConfig,"South Pole", ...
    objectiveMode,networkSize,rsoIndex);

percentages = [fullPercent;polarPercent];

fig = figure("Name","RSO-specific constraint screening", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 7.6 5.7],"Renderer","opengl");
layout = tiledlayout(fig,1,1,"Padding","loose","TileSpacing","loose");
ax = nexttile(layout);
hold(ax,"on");

bars = bar(ax,1:2,percentages,0.62,"stacked","LineWidth",0.9);
for categoryIndex = 1:numel(categoryNames)
    bars(categoryIndex).FaceColor = categoryColors(categoryIndex,:);
    bars(categoryIndex).EdgeColor = style.textColor;
end

xticks(ax,[1 2]);
xticklabels(ax,["Southern Hemisphere","South Pole"]);
xlim(ax,[0.45 2.55]);
ylim(ax,[0 100]);
yticks(ax,0:20:100);
ylabel(ax,"Measurement opportunities (%)");
title(ax,sprintf("RSO %02d, N_s = %d, %s-driven network", ...
    rsoIndex,networkSize,objectiveMode), ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");

ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 1.0;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";

lgd = legend(ax,bars,categoryNames, ...
    "Location","none","Box","off","Orientation","horizontal", ...
    "NumColumns",3);
lgd.FontName = style.fontName;
lgd.FontSize = max(15,style.legendFontSize-2);
lgd.FontWeight = "bold";
lgd.AutoUpdate = "off";
lgd.Layout.Tile = "north";

outputFile = fullfile(outputDirectory, ...
    sprintf("constraint_screening_rso%02d.eps",rsoIndex));
exportManuscriptFigure(fig,string(outputFile),7.6,5.7);

summaryTable = [fullRow;polarRow];
summaryFile = "";
if exportDiagnosticTables
    tableDirectory = fullfile(outputDirectory,"tables");
    if ~isfolder(tableDirectory), mkdir(tableDirectory); end
    summaryFile = fullfile(tableDirectory, ...
        sprintf("constraint_screening_rso%02d.csv",rsoIndex));
    writetable(summaryTable,summaryFile);
end

plotInfo = struct();
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.rsoIndex = rsoIndex;
plotInfo.objectiveMode = objectiveMode;
plotInfo.networkSize = networkSize;
plotInfo.percentages = percentages;
plotInfo.counts = [fullCount;polarCount];
plotInfo.summaryTable = summaryTable;
plotInfo.summaryFile = string(summaryFile);

fprintf("RSO-specific constraint-screening figure:\n  %s\n",outputFile);
end

function [percentages,counts,row] = computeCase( ...
    campaign,userConfig,domainLabel,objectiveMode,networkSize,rsoIndex)

database = campaign.database;
config = campaign.configuration;
projectRoot = string(campaign.projectRoot);

objectiveIndex = find(lower(string(config.objectiveModes))==objectiveMode,1);
networkIndex = find(double(config.networkSizes)==networkSize,1);
assert(~isempty(objectiveIndex) && ~isempty(networkIndex), ...
    "Requested objective/network-size case is unavailable.");

truthStates = double(database.truth.optimizationStateHistories);
assert(rsoIndex <= size(truthStates,3), ...
    "Requested RSO index exceeds the design population.");

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

counts = zeros(1,numel(masks));
reconstructed = false(size(accepted));
for categoryIndex = 1:numel(masks)
    reconstructed = reconstructed | masks{categoryIndex};
    counts(categoryIndex) = nnz(masks{categoryIndex});
end

totalOpportunities = numel(accepted);
assert(nnz(reconstructed)==totalOpportunities, ...
    "Screening categories do not reconstruct all RSO opportunities.");
assert(sum(counts)==totalOpportunities, ...
    "Screening categories are not mutually exclusive.");

percentages = 100*counts/totalOpportunities;
row = table( ...
    string(domainLabel),objectiveMode,networkSize,rsoIndex,totalOpportunities, ...
    counts(1),counts(2),counts(3),counts(4),counts(5),counts(6), ...
    percentages(1),percentages(2),percentages(3), ...
    percentages(4),percentages(5),percentages(6), ...
    'VariableNames',{ ...
    'Domain','Objective','NetworkSize','RsoIndex','TotalOpportunities', ...
    'BelowHorizonCount','TerrainBlockedCount','EarthBlockedCount', ...
    'SunBlockedCount','EarthAndSunCount','AcceptedCount', ...
    'BelowHorizonPercent','TerrainBlockedPercent','EarthBlockedPercent', ...
    'SunBlockedPercent','EarthAndSunPercent','AcceptedPercent'});
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

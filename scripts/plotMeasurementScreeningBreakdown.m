function plotInfo = plotMeasurementScreeningBreakdown( ...
    fullCampaign,restrictedCampaign,userConfig)
% PLOTMEASUREMENTSCREENINGBREAKDOWN Compare LOS screening outcomes.
%
% One figure is exported for each optimization objective. For every network
% size, the southern-hemisphere and restricted south-polar optimized networks
% are shown as adjacent stacked bars so the screening spread can be compared
% directly between BOTH studies.
%
% Outputs:
%   screening_breakdown_information.eps
%   screening_breakdown_coverage.eps
%   tables/measurement_screening_breakdown.csv

arguments
    fullCampaign (1,1) struct
    restrictedCampaign (1,1) struct = struct()
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = fullCampaign.configuration;
outputDirectory = string(fullCampaign.outputDirectory);
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
tableDirectory = fullfile(outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

hasRestricted = ~isempty(fieldnames(restrictedCampaign));
if hasRestricted
    assert(isequal(config.networkSizes, ...
        restrictedCampaign.configuration.networkSizes), ...
        "Full and restricted campaigns use different network sizes.");
    assert(isequal(config.objectiveModes, ...
        restrictedCampaign.configuration.objectiveModes), ...
        "Full and restricted campaigns use different objective modes.");
end

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

[fullPercent,fullCount,fullRows] = ...
    computeCampaignScreening(fullCampaign,userConfig,"Southern hemisphere");

if hasRestricted
    [restrictedPercent,restrictedCount,restrictedRows] = ...
        computeCampaignScreening( ...
            restrictedCampaign,userConfig,"Restricted south-polar");
else
    restrictedPercent = [];
    restrictedCount = [];
    restrictedRows = table();
end

plotInfo = struct();

for objectiveIndex = 1:numel(config.objectiveModes)
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);

    fig = figure("Name",objectiveMode + " measurement screening", ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 7.5 5.8],"Renderer","opengl");
    % Reserve enough left margin for the long y-axis label at paper font size.
    layout = tiledlayout(fig,1,1,"Padding","loose");
    ax = nexttile(layout);
    hold(ax,"on");

    x = 1:numel(config.networkSizes);
    if hasRestricted
        offset = 0.19;
        fullBars = bar(ax,x-offset, ...
            squeeze(fullPercent(:,:,objectiveIndex)),0.34,"stacked", ...
            "LineWidth",0.9,"LineStyle","-");
        restrictedBars = bar(ax,x+offset, ...
            squeeze(restrictedPercent(:,:,objectiveIndex)),0.34,"stacked", ...
            "LineWidth",1.1,"LineStyle","--");
    else
        fullBars = bar(ax,x, ...
            squeeze(fullPercent(:,:,objectiveIndex)),0.55,"stacked", ...
            "LineWidth",0.9,"LineStyle","-");
        restrictedBars = gobjects(0);
    end

    for categoryIndex = 1:numel(categoryNames)
        fullBars(categoryIndex).FaceColor = categoryColors(categoryIndex,:);
        fullBars(categoryIndex).EdgeColor = style.textColor;
        if hasRestricted
            restrictedBars(categoryIndex).FaceColor = ...
                categoryColors(categoryIndex,:);
            restrictedBars(categoryIndex).EdgeColor = style.boundaryColor;
        end
    end

    xlabel(ax,"Number of sensors, N_s");
    ylabel(ax,"Measurement opportunities (%)");
    xticks(ax,x);
    xticklabels(ax,string(config.networkSizes));
    xlim(ax,[0.55 numel(x)+0.45]);
    ylim(ax,[0 100]);
    yticks(ax,0:20:100);
    applyAxesStyle(ax,style);

    legendHandles = gobjects(0);
    legendLabels = strings(0,1);
    if hasRestricted
        fullDomainHandle = plot(ax,nan,nan,"-", ...
            "Color",style.textColor,"LineWidth",2.0);
        restrictedDomainHandle = plot(ax,nan,nan,"--", ...
            "Color",style.boundaryColor,"LineWidth",2.0);
        legendHandles = [fullDomainHandle;restrictedDomainHandle;fullBars(:)];
        legendLabels = [ ...
            "Southern hemisphere"; ...
            "Restricted south-polar"; ...
            categoryNames(:)];
    else
        legendHandles = fullBars(:);
        legendLabels = categoryNames(:);
    end

    lgd = legend(ax,legendHandles,legendLabels, ...
        "Location","none","Box","off", ...
        "Orientation","horizontal","NumColumns",2);
    lgd.FontName = style.fontName;
    lgd.FontSize = 13;
    lgd.FontWeight = "bold";
    lgd.AutoUpdate = "off";
    lgd.Layout.Tile = "north";

    outputFile = fullfile(outputDirectory, ...
        sprintf("screening_breakdown_%s.eps",objectiveMode));
    exportManuscriptFigure(fig,string(outputFile),7.5,5.8);

    plotInfo.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile), ...
        "fullPercent",squeeze(fullPercent(:,:,objectiveIndex)), ...
        "restrictedPercent",conditionalSlice( ...
            restrictedPercent,objectiveIndex,hasRestricted), ...
        "fullCount",squeeze(fullCount(:,:,objectiveIndex)), ...
        "restrictedCount",conditionalSlice( ...
            restrictedCount,objectiveIndex,hasRestricted));
end

summaryTable = fullRows;
if hasRestricted
    summaryTable = [fullRows;restrictedRows];
end
summaryFile = fullfile(tableDirectory,"measurement_screening_breakdown.csv");
writetable(summaryTable,summaryFile);

plotInfo.summaryTable = summaryTable;
plotInfo.summaryFile = string(summaryFile);

fprintf("Measurement-screening comparison figures:\n");
fprintf("  %s\n",fullfile(outputDirectory,"screening_breakdown_information.eps"));
fprintf("  %s\n",fullfile(outputDirectory,"screening_breakdown_coverage.eps"));
end

function [percentages,counts,rows] = ...
    computeCampaignScreening(campaign,userConfig,domainLabel)

database = campaign.database;
config = campaign.configuration;
projectRoot = string(campaign.projectRoot);

demFile = resolveDemFile(projectRoot,database,userConfig);
moonRadiusKm = database.config.moon.radiusKm;
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,moonRadiusKm,24,48);

trackingTimes = double(database.tracking.times(:));
truthStates = double(database.truth.optimizationStateHistories);
[earthPositions,sunPositions] = selectEphemerides(database,trackingTimes);

nN = numel(config.networkSizes);
nO = numel(config.objectiveModes);
numberOfCategories = 6;
counts = zeros(nN,numberOfCategories,nO);
percentages = zeros(size(counts));
rowCells = cell(nN*nO,1);
row = 0;

for objectiveIndex = 1:nO
    for networkIndex = 1:nN
        studyState = campaign.studies{networkIndex,objectiveIndex};
        runState = studyState.runStates{studyState.overallBestRunIndex};
        sensorLatitudesRad = double(runState.bestSensorLatitudesRad(:));
        sensorLongitudesRad = double(runState.bestSensorLongitudesRad(:));
        [horizonAzimuthsRad,maximumTerrainElevation] = ...
            resolveSelectedTerrain( ...
                database,sensorLatitudesRad,sensorLongitudesRad, ...
                dem,moonRadiusKm);

        [~,diagnostics] = optimization.buildFilteredVisibilityDatabase( ...
            trackingTimes,truthStates, ...
            sensorLatitudesRad,sensorLongitudesRad, ...
            dem,horizonAzimuthsRad, ...
            maximumTerrainElevation,earthPositions,sunPositions, ...
            database.config.visibility.minimumElevationRad, ...
            database.config.terrain.horizonMarginRad, ...
            database.config.visibility.earthRadiusKm, ...
            database.config.visibility.sunRadiusKm, ...
            database.config.visibility.sunMinimumAngularSeparationRad, ...
            moonRadiusKm,database.config.moon.theta0Rad, ...
            2*pi/database.config.moon.siderealPeriodSeconds, ...
            database.config.visibility.earthMinimumAngularSeparationRad);

        belowHorizon = ~diagnostics.geometricAvailability;
        terrainBlocked = diagnostics.terrainRejected;
        earthOnly = diagnostics.terrainAvailability & ...
            diagnostics.earthBlocked & ~diagnostics.sunBlocked;
        sunOnly = diagnostics.terrainAvailability & ...
            diagnostics.sunBlocked & ~diagnostics.earthBlocked;
        earthAndSun = diagnostics.terrainAvailability & ...
            diagnostics.earthBlocked & diagnostics.sunBlocked;
        accepted = diagnostics.accepted;

        masks = {belowHorizon,terrainBlocked,earthOnly,sunOnly,earthAndSun,accepted};
        totalOpportunities = numel(accepted);
        reconstructed = false(size(accepted));

        for categoryIndex = 1:numberOfCategories
            reconstructed = reconstructed | masks{categoryIndex};
            counts(networkIndex,categoryIndex,objectiveIndex) = ...
                nnz(masks{categoryIndex});
        end

        assert(nnz(reconstructed) == totalOpportunities, ...
            "Screening categories do not reconstruct all opportunities.");
        assert(sum(counts(networkIndex,:,objectiveIndex)) == totalOpportunities, ...
            "Screening categories are not mutually exclusive.");

        percentages(networkIndex,:,objectiveIndex) = ...
            100*counts(networkIndex,:,objectiveIndex)/totalOpportunities;

        row = row+1;
        rowCells{row} = table( ...
            string(domainLabel),config.objectiveModes(objectiveIndex), ...
            config.networkSizes(networkIndex),totalOpportunities, ...
            counts(networkIndex,1,objectiveIndex), ...
            counts(networkIndex,2,objectiveIndex), ...
            counts(networkIndex,3,objectiveIndex), ...
            counts(networkIndex,4,objectiveIndex), ...
            counts(networkIndex,5,objectiveIndex), ...
            counts(networkIndex,6,objectiveIndex), ...
            percentages(networkIndex,1,objectiveIndex), ...
            percentages(networkIndex,2,objectiveIndex), ...
            percentages(networkIndex,3,objectiveIndex), ...
            percentages(networkIndex,4,objectiveIndex), ...
            percentages(networkIndex,5,objectiveIndex), ...
            percentages(networkIndex,6,objectiveIndex), ...
            'VariableNames',{ ...
            'Domain','Objective','NetworkSize','TotalOpportunities', ...
            'BelowHorizonCount','TerrainBlockedCount','EarthBlockedCount', ...
            'SunBlockedCount','EarthAndSunCount','AcceptedCount', ...
            'BelowHorizonPercent','TerrainBlockedPercent','EarthBlockedPercent', ...
            'SunBlockedPercent','EarthAndSunPercent','AcceptedPercent'});
    end
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

for k = 1:numel(candidateFiles)
    if strlength(candidateFiles(k)) > 0 && isfile(candidateFiles(k))
        demFile = candidateFiles(k);
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
        sprintf('Could not align ephemerides with tracking time %.6f s.', ...
        trackingTimes(timeIndex)));
    indices(timeIndex) = matchIndex;
end

earthPositions = double(database.ephemeris.earthPositionsMci(:,indices));
sunPositions = double(database.ephemeris.sunPositionsMci(:,indices));
end

function [horizonAzimuthsRad,maximumTerrainElevationRad] = ...
    resolveSelectedTerrain(database,latitudesRad,longitudesRad,dem,moonRadiusKm)
% Use precomputed terrain only when every optimized site exactly matches the
% current candidate grid. Restricted-study sites came from a different grid,
% so their terrain horizons are recomputed at the original optimized
% coordinates rather than being snapped to a nearby full-domain candidate.

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
        maximumTerrainElevationRad = ...
            optimization.loadChunkedCandidateData( ...
                database,indices,"maximumTerrainElevationRad");
    else
        maximumTerrainElevationRad = ...
            database.terrain.maximumTerrainElevationRad(indices,:);
    end
    return
end

fprintf(['  Recomputing terrain horizons for %d off-grid optimized ' ...
    'sensor locations.\n'],numel(latitudesRad));

[horizonAzimuthsRad,maximumTerrainElevationRad] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        latitudesRad,longitudesRad,dem, ...
        database.config.terrain.maximumRangeKm, ...
        database.config.terrain.rangeStepKm, ...
        database.config.terrain.horizonAzimuthStepRad, ...
        moonRadiusKm);
end

function applyAxesStyle(ax,style)
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 0.9;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.Layer = "top";
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";
end

function value = conditionalSlice(array,objectiveIndex,hasRestricted)
if hasRestricted
    value = squeeze(array(:,:,objectiveIndex));
else
    value = [];
end
end
function plotInfo = plotMeasurementScreeningBreakdown(campaign,userConfig)
% PLOTMEASUREMENTSCREENINGBREAKDOWN Plot LOS/screening outcome fractions.
%
% One standalone stacked-bar chart is exported for each optimization
% objective. Each bar corresponds to the overall-best network for one N_s
% and partitions all selected-sensor / RSO / epoch measurement opportunities
% into mutually exclusive screening outcomes:
%   below local horizon, terrain blocked, Earth blocked, Sun blocked,
%   Earth+Sun blocked, or accepted.
%
% Outputs:
%   screening_breakdown_information.eps
%   screening_breakdown_coverage.eps
%   tables/measurement_screening_breakdown.csv

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style=publicationPlotStyle();
config=campaign.configuration;
database=campaign.database;
projectRoot=string(campaign.projectRoot);
outputDirectory=string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory")
    outputDirectory=string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
tableDirectory=fullfile(outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

demFile=resolveDemFile(projectRoot,database,userConfig);
moonRadiusKm=database.config.moon.radiusKm;
[dem,~]=digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,moonRadiusKm,24,48);

trackingTimes=double(database.tracking.times(:));
truthStates=double(database.truth.optimizationStateHistories);
[earthPositions,sunPositions]=selectEphemerides(database,trackingTimes);

categoryNames=[ ...
    "Below local horizon", ...
    "Terrain blocked", ...
    "Earth blocked", ...
    "Sun blocked", ...
    "Earth + Sun", ...
    "Accepted"];

categoryColors=[ ...
    style.grayColor; ...
    style.orangeColor; ...
    style.blueColor; ...
    style.magentaColor; ...
    0.38 0.24 0.54; ...
    style.greenColor];

numberOfNetworkSizes=numel(config.networkSizes);
numberOfObjectives=numel(config.objectiveModes);
allRows=cell(numberOfNetworkSizes*numberOfObjectives,1);
rowIndex=0;
plotInfo=struct();

for objectiveIndex=1:numberOfObjectives
    objectiveMode=config.objectiveModes(objectiveIndex);
    objectiveField=char(objectiveMode);
    percentages=zeros(numberOfNetworkSizes,numel(categoryNames));
    counts=zeros(size(percentages));

    for networkIndex=1:numberOfNetworkSizes
        networkSize=config.networkSizes(networkIndex);
        studyState=campaign.studies{networkIndex,objectiveIndex};
        sensorIndices=double(studyState.overallBestSensorIndices(:));

        if isfield(database.terrain,"candidateChunks") && ...
                ~isempty(database.terrain.candidateChunks)
            maximumTerrainElevation=optimization.loadChunkedCandidateData( ...
                database,sensorIndices,"maximumTerrainElevationRad");
        else
            maximumTerrainElevation= ...
                database.terrain.maximumTerrainElevationRad(sensorIndices,:);
        end

        [~,diagnostics]=optimization.buildFilteredVisibilityDatabase( ...
            trackingTimes,truthStates, ...
            database.candidates.latitudesRad(sensorIndices), ...
            database.candidates.longitudesRad(sensorIndices), ...
            dem,database.terrain.horizonAzimuthsRad,maximumTerrainElevation, ...
            earthPositions,sunPositions, ...
            database.config.visibility.minimumElevationRad, ...
            database.config.terrain.horizonMarginRad, ...
            database.config.visibility.earthRadiusKm, ...
            database.config.visibility.sunRadiusKm, ...
            database.config.visibility.sunMinimumAngularSeparationRad, ...
            moonRadiusKm,database.config.moon.theta0Rad, ...
            2*pi/database.config.moon.siderealPeriodSeconds, ...
            database.config.visibility.earthMinimumAngularSeparationRad);

        belowHorizon=~diagnostics.geometricAvailability;
        terrainBlocked=diagnostics.terrainRejected;
        earthOnly=diagnostics.terrainAvailability & ...
            diagnostics.earthBlocked & ~diagnostics.sunBlocked;
        sunOnly=diagnostics.terrainAvailability & ...
            diagnostics.sunBlocked & ~diagnostics.earthBlocked;
        earthAndSun=diagnostics.terrainAvailability & ...
            diagnostics.earthBlocked & diagnostics.sunBlocked;
        accepted=diagnostics.accepted;

        masks={belowHorizon,terrainBlocked,earthOnly,sunOnly,earthAndSun,accepted};
        totalOpportunities=numel(accepted);
        reconstructed=false(size(accepted));
        for categoryIndex=1:numel(masks)
            reconstructed=reconstructed | masks{categoryIndex};
            counts(networkIndex,categoryIndex)=nnz(masks{categoryIndex});
        end

        assert(nnz(reconstructed)==totalOpportunities, ...
            "Screening categories do not reconstruct all measurement opportunities.");
        assert(sum(counts(networkIndex,:))==totalOpportunities, ...
            "Screening categories are not mutually exclusive.");

        percentages(networkIndex,:)= ...
            100*counts(networkIndex,:)/totalOpportunities;

        rowIndex=rowIndex+1;
        allRows{rowIndex}=table( ...
            objectiveMode,networkSize,totalOpportunities, ...
            counts(networkIndex,1),counts(networkIndex,2), ...
            counts(networkIndex,3),counts(networkIndex,4), ...
            counts(networkIndex,5),counts(networkIndex,6), ...
            percentages(networkIndex,1),percentages(networkIndex,2), ...
            percentages(networkIndex,3),percentages(networkIndex,4), ...
            percentages(networkIndex,5),percentages(networkIndex,6), ...
            'VariableNames',{ ...
            'Objective','NetworkSize','TotalOpportunities', ...
            'BelowHorizonCount','TerrainBlockedCount','EarthBlockedCount', ...
            'SunBlockedCount','EarthAndSunCount','AcceptedCount', ...
            'BelowHorizonPercent','TerrainBlockedPercent','EarthBlockedPercent', ...
            'SunBlockedPercent','EarthAndSunPercent','AcceptedPercent'});
    end

    fig=figure("Name",objectiveMode+" measurement screening", ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 8.5 5.9],"Renderer","opengl");
    ax=axes(fig,"Position",[0.12 0.16 0.84 0.66]);
    hold(ax,"on");

    barHandles=bar(ax,config.networkSizes,percentages, ...
        "stacked","BarWidth",0.72,"LineStyle","none");
    for categoryIndex=1:numel(barHandles)
        barHandles(categoryIndex).FaceColor=categoryColors(categoryIndex,:);
    end

    xlabel(ax,"Number of sensors, N_s");
    ylabel(ax,"Measurement opportunities (%)");
    xticks(ax,config.networkSizes);
    xlim(ax,[min(config.networkSizes)-0.7 max(config.networkSizes)+0.7]);
    ylim(ax,[0 100]);
    yticks(ax,0:20:100);
    applyAxesStyle(ax,style);

    lgd=legend(ax,barHandles,categoryNames, ...
        "Location","northoutside","Orientation","horizontal", ...
        "NumColumns",3,"Box","off");
    lgd.FontName=style.fontName;
    lgd.FontSize=max(13,style.legendFontSize-3);
    lgd.FontWeight="bold";

    outputFile=fullfile(outputDirectory, ...
        sprintf("screening_breakdown_%s.eps",objectiveMode));
    exportManuscriptFigure(fig,string(outputFile),8.5,5.9);

    plotInfo.(objectiveField)=struct( ...
        "figure",fig,"outputFile",string(outputFile), ...
        "percentages",percentages,"counts",counts);
end

summaryTable=vertcat(allRows{:});
summaryFile=fullfile(tableDirectory,"measurement_screening_breakdown.csv");
writetable(summaryTable,summaryFile);
plotInfo.summaryTable=summaryTable;
plotInfo.summaryFile=string(summaryFile);

fprintf("Measurement-screening figures and table generated.\n");
end

function demFile=resolveDemFile(projectRoot,database,userConfig)
demFile="";
if isfield(userConfig,"demFile") && strlength(string(userConfig.demFile))>0
    demFile=string(userConfig.demFile);
end

candidateFiles=strings(0,1);
if strlength(demFile)>0, candidateFiles(end+1,1)=demFile; end
candidateFiles(end+1,1)=fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat");
candidateFiles(end+1,1)=fullfile(projectRoot,"data","Full_Resolution_DEM.mat");
if isfield(database,"meta") && isfield(database.meta,"demSource")
    candidateFiles(end+1,1)=string(database.meta.demSource);
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidateFiles(end+1,1)=string(database.config.demSource);
end

demFile="";
for k=1:numel(candidateFiles)
    if strlength(candidateFiles(k))>0 && isfile(candidateFiles(k))
        demFile=candidateFiles(k);
        return
    end
end
error("plotMeasurementScreeningBreakdown:DemNotFound", ...
    "No production DEM could be resolved.");
end

function [earthPositions,sunPositions]=selectEphemerides(database,trackingTimes)
fullTimes=double(database.truth.times(:));
indices=zeros(numel(trackingTimes),1);
for timeIndex=1:numel(trackingTimes)
    [difference,matchIndex]=min(abs(fullTimes-trackingTimes(timeIndex)));
    assert(difference<1e-8, ...
        "Could not align ephemerides with tracking time %.6f s.", ...
        trackingTimes(timeIndex));
    indices(timeIndex)=matchIndex;
end
earthPositions=double(database.ephemeris.earthPositionsMci(:,indices));
sunPositions=double(database.ephemeris.sunPositionsMci(:,indices));
end

function applyAxesStyle(ax,style)
ax.FontName=style.fontName;
ax.FontSize=style.axisFontSize;
ax.FontWeight="bold";
ax.LineWidth=0.9;
ax.TickDir="out";
ax.Box="on";
ax.XGrid="off";
ax.YGrid="on";
ax.GridColor=style.gridColor;
ax.GridAlpha=0.55;
ax.Layer="top";
ax.XLabel.FontSize=style.labelFontSize;
ax.XLabel.FontWeight="bold";
ax.YLabel.FontSize=style.labelFontSize;
ax.YLabel.FontWeight="bold";
end

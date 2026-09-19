function plotInfo = plotDesignRsoTrackingHeatmaps(campaign,userConfig)
% PLOTDESIGNRSOTRACKINGHEATMAPS Combined design-RSO RMSE/observability figure.
%
% The overall-best network from each production case is re-evaluated with a
% fixed measurement-noise seed. Metrics are cached to avoid repeated EKF work.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

config = campaign.configuration;
database = campaign.database;
style = publicationPlotStyle();
outputDirectory = string(campaign.outputDirectory);
if isfield(userConfig,"outputDirectory"), outputDirectory=string(userConfig.outputDirectory); end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
tableDirectory=fullfile(outputDirectory,"tables");
cacheDirectory=fullfile(outputDirectory,"cache");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end
if ~isfolder(cacheDirectory), mkdir(cacheDirectory); end

measurementNoiseSeed=5000;
if isfield(userConfig,"measurementNoiseSeed")
    measurementNoiseSeed=userConfig.measurementNoiseSeed;
end

numberOfObjects=database.meta.numberOfObjects;
numberOfTimes=database.meta.numberOfOptimizationEpochs;
databaseInfo=dir(campaign.databaseFile);
databaseDatenum=databaseInfo.datenum;
nN=numel(config.networkSizes); nO=numel(config.objectiveModes);
rms=nan(numberOfObjects,nN,nO);
observable=nan(numberOfObjects,nN,nO);
rows=cell(nN*nO,1);
caseIndex=0;

for objectiveIndex=1:nO
    for networkIndex=1:nN
        caseIndex=caseIndex+1;
        studyState=campaign.studies{networkIndex,objectiveIndex};
        sensors=double(studyState.overallBestSensorIndices(:));
        objectiveMode=config.objectiveModes(objectiveIndex);
        networkSize=config.networkSizes(networkIndex);

        cacheFile=fullfile(cacheDirectory, ...
            sprintf("design_tracking_%s_n%d.mat",objectiveMode,networkSize));
        useCache=false;
        if isfile(cacheFile)
            d=load(cacheFile,"metricCache");
            if isfield(d,"metricCache") && ...
                    isfield(d.metricCache,"databaseDatenum") && ...
                    isequal(d.metricCache.sensors,sensors) && ...
                    d.metricCache.measurementNoiseSeed==measurementNoiseSeed && ...
                    isequal(d.metricCache.databaseDatenum,databaseDatenum)
                metricCache=d.metricCache; useCache=true;
            end
        end
        if ~useCache
            vcfg=struct("measurementNoiseSeed",measurementNoiseSeed);
            validation=optimization.validateNetworkEkf(database,sensors,vcfg);
            availability=loadAvailability(database,sensors);
            epochObservable=squeeze(any(availability,1));
            if numberOfObjects==1, epochObservable=epochObservable(:); end
            metricCache=struct();
            metricCache.sensors=sensors;
            metricCache.measurementNoiseSeed=measurementNoiseSeed;
            metricCache.databaseFile=string(campaign.databaseFile);
            metricCache.databaseDatenum=databaseDatenum;
            metricCache.rmsPositionErrorKm=validation.rmsPositionErrorKm;
            metricCache.rmsVelocityErrorKmS=validation.rmsVelocityErrorKmS;
            metricCache.observableEpochPercent=100*sum(epochObservable,1).'/numberOfTimes;
            metricCache.measurementUpdates=validation.measurementUpdateCounts;
            save(cacheFile,"metricCache");
        end

        rms(:,networkIndex,objectiveIndex)=metricCache.rmsPositionErrorKm;
        observable(:,networkIndex,objectiveIndex)=metricCache.observableEpochPercent;
        rows{caseIndex}=table( ...
            repmat(objectiveMode,numberOfObjects,1), ...
            repmat(networkSize,numberOfObjects,1),(1:numberOfObjects).', ...
            metricCache.rmsPositionErrorKm,metricCache.rmsVelocityErrorKmS, ...
            metricCache.observableEpochPercent,metricCache.measurementUpdates, ...
            'VariableNames',{'Objective','NetworkSize','RsoIndex', ...
            'RmsPositionErrorKm','RmsVelocityErrorKmS', ...
            'ObservableEpochPercent','MeasurementUpdates'});
    end
end

detailTable=vertcat(rows{:});
detailFile=fullfile(tableDirectory,"design_rso_tracking.csv");
writetable(detailTable,detailFile);

fig=figure("Name","Design RSO tracking performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 9.5 7.4],"Renderer","opengl");
layout=tiledlayout(fig,2,nO,"TileSpacing","compact","Padding","compact");

for objectiveIndex=1:nO
    ax=nexttile(layout,objectiveIndex);
    imagesc(ax,1:nN,1:numberOfObjects,log10(max(rms(:,:,objectiveIndex),1e-12)));
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex==1);
    title(ax,objectiveTitle(config.objectiveModes(objectiveIndex)), ...
        "FontWeight","bold","FontSize",style.labelFontSize);
    xlabel(ax,"Number of sensors, N_s");
    cb=colorbar(ax); cb.Label.String="RMS position error (km)";
    styleColorbar(cb,style,true);

    ax=nexttile(layout,nO+objectiveIndex);
    imagesc(ax,1:nN,1:numberOfObjects,observable(:,:,objectiveIndex));
    clim(ax,[0 100]);
    styleHeatmapAxes(ax,style,config.networkSizes,numberOfObjects,objectiveIndex==1);
    xlabel(ax,"Number of sensors, N_s");
    cb=colorbar(ax); cb.Label.String="Observable epochs (%)";
    styleColorbar(cb,style,false);
end
colormap(fig,turbo(256));

outputFile=fullfile(outputDirectory,"design_rso_tracking_heatmaps.eps");
exportManuscriptFigure(fig,string(outputFile),9.5,7.4);

plotInfo=struct("figure",fig,"outputFile",string(outputFile), ...
    "detailTable",detailTable,"detailFile",string(detailFile));
end

function availability=loadAvailability(database,sensors)
if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)
    availability=optimization.loadChunkedCandidateData( ...
        database,sensors,"filteredAvailability");
else
    availability=database.visibility.filteredAvailability(sensors,:,:);
end
end

function styleHeatmapAxes(ax,style,networkSizes,nObjects,showY)
set(ax,"YDir","normal");
ax.FontName=style.fontName; ax.FontSize=style.axisFontSize; ax.FontWeight="bold";
ax.XTick=1:numel(networkSizes); ax.XTickLabel=string(networkSizes);
ax.YTick=1:nObjects;
if showY
    ax.YTickLabel=compose("%02d",1:nObjects);
    ylabel(ax,"RSO index");
else
    ax.YTickLabel=strings(nObjects,1);
end
end

function styleColorbar(cb,style,isLog)
cb.FontName=style.fontName; cb.FontSize=style.axisFontSize; cb.FontWeight="bold";
cb.Label.FontSize=style.labelFontSize; cb.Label.FontWeight="bold";
if isLog
    ticks=cb.Ticks;
    cb.TickLabels=compose("%.3g",10.^ticks);
end
end

function t=objectiveTitle(mode)
if mode=="information", t="Information-optimized"; else, t="Coverage-optimized"; end
end
function result = generateDomainComparisonProducts(fullCampaign,userConfig)
% GENERATEDOMAINCOMPARISONPRODUCTS Create the two domain-comparison panels.
%
% The current manuscript uses two subfigures:
%   domain_comparison_locations.eps  - selected sensor locations
%   domain_comparison_metrics.eps    - coverage and information scores
%
% It also uses a compact common-budget table:
%   tables/domain_comparison.csv
%
% Preferred configuration:
%   restrictedCampaignAnchor
%       Folder name, folder path, or study_summary.mat for any one case in
%       the restricted campaign. Example:
%       "ga_coverage_n3_20260915_121933"
%
% The anchor lets this function infer the restricted frozen database and
% study name even when full- and restricted-domain runs live under the same
% results/optimization_runs directory.
%
% Legacy explicit configuration is also supported:
%   restrictedResultsDirectory
%   restrictedDatabaseFile
%
% Optional:
%   restrictedStudyName
%   comparisonNetworkSize   (default: largest production N_s)
%   comparisonObjective     (default: "information")
%   measurementNoiseSeed    (default: 5000)

arguments
    fullCampaign (1,1) struct
    userConfig (1,1) struct
end

restrictedConfig=fullCampaign.configuration;
restrictedConfig.outputDirectory=string(fullCampaign.outputDirectory);

anchor="";
if isfield(userConfig,"restrictedCampaignAnchor")
    anchor=string(userConfig.restrictedCampaignAnchor);
end

if strlength(anchor)>0
    [anchorSummaryFile,anchorStudy]=resolveCampaignAnchor( ...
        anchor,string(fullCampaign.projectRoot), ...
        string(fullCampaign.configuration.resultsDirectory));

    restrictedConfig.resultsDirectory= ...
        string(fullCampaign.configuration.resultsDirectory);
    if isfield(userConfig,"restrictedResultsDirectory") && ...
            strlength(string(userConfig.restrictedResultsDirectory))>0
        restrictedConfig.resultsDirectory= ...
            string(userConfig.restrictedResultsDirectory);
    end

    assert(isfield(anchorStudy.config,"databaseFile"), ...
        "Restricted anchor study does not record config.databaseFile.");
    restrictedConfig.databaseFile=string(anchorStudy.config.databaseFile);
    restrictedConfig.studyName=string(anchorStudy.config.studyName);

    % If the stored path no longer exists, try the same database basename
    % directly under the active results directory.
    if ~isfile(restrictedConfig.databaseFile)
        [~,databaseName,databaseExtension]= ...
            fileparts(restrictedConfig.databaseFile);
        relocatedDatabase=fullfile( ...
            restrictedConfig.resultsDirectory, ...
            databaseName+databaseExtension);
        assert(isfile(relocatedDatabase), ...
            ["Restricted database from anchor study was not found:\n%s\n" ...
             "Also tried:\n%s"], ...
            restrictedConfig.databaseFile,relocatedDatabase);
        restrictedConfig.databaseFile=string(relocatedDatabase);
    end

    fprintf("Restricted campaign anchor:\n  %s\n",anchorSummaryFile);
    fprintf("Restricted database:\n  %s\n",restrictedConfig.databaseFile);
else
    assert(isfield(userConfig,"restrictedResultsDirectory") && ...
        strlength(string(userConfig.restrictedResultsDirectory))>0, ...
        ["Set restrictedCampaignAnchor, or provide " ...
         "restrictedResultsDirectory and restrictedDatabaseFile."]);
    assert(isfield(userConfig,"restrictedDatabaseFile") && ...
        strlength(string(userConfig.restrictedDatabaseFile))>0, ...
        ["Set restrictedCampaignAnchor, or provide " ...
         "restrictedResultsDirectory and restrictedDatabaseFile."]);

    restrictedConfig.resultsDirectory= ...
        string(userConfig.restrictedResultsDirectory);
    restrictedConfig.databaseFile= ...
        string(userConfig.restrictedDatabaseFile);

    if isfield(userConfig,"restrictedStudyName") && ...
            strlength(string(userConfig.restrictedStudyName))>0
        restrictedConfig.studyName=string(userConfig.restrictedStudyName);
    end
end

restrictedCampaign=loadProductionCampaign(restrictedConfig);

networkSizes=fullCampaign.configuration.networkSizes;
objectiveModes=fullCampaign.configuration.objectiveModes;
assert(isequal(networkSizes,restrictedCampaign.configuration.networkSizes), ...
    "Full and restricted campaigns use different network sizes.");
assert(isequal(objectiveModes,restrictedCampaign.configuration.objectiveModes), ...
    "Full and restricted campaigns use different objective modes.");

comparisonNetworkSize=max(networkSizes);
if isfield(userConfig,"comparisonNetworkSize")
    comparisonNetworkSize=double(userConfig.comparisonNetworkSize);
end
assert(ismember(comparisonNetworkSize,networkSizes), ...
    "comparisonNetworkSize must be one of the production network sizes.");

comparisonObjective="information";
if isfield(userConfig,"comparisonObjective")
    comparisonObjective=lower(string(userConfig.comparisonObjective));
end
assert(ismember(comparisonObjective,objectiveModes), ...
    "comparisonObjective must be information or coverage.");

measurementNoiseSeed=5000;
if isfield(userConfig,"measurementNoiseSeed")
    measurementNoiseSeed=double(userConfig.measurementNoiseSeed);
end

style=publicationPlotStyle();
outputDirectory=string(fullCampaign.outputDirectory);
tableDirectory=fullfile(outputDirectory,"tables");
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

%% Selected sensor locations at the common comparison budget

networkIndex=find(networkSizes==comparisonNetworkSize,1);
informationIndex=find(objectiveModes=="information",1);
coverageIndex=find(objectiveModes=="coverage",1);
assert(~isempty(informationIndex) && ~isempty(coverageIndex), ...
    "Both information and coverage studies are required.");

fullInfoSensors=double( ...
    fullCampaign.studies{networkIndex,informationIndex}.overallBestSensorIndices(:));
fullCoverageSensors=double( ...
    fullCampaign.studies{networkIndex,coverageIndex}.overallBestSensorIndices(:));
restrictedInfoSensors=double( ...
    restrictedCampaign.studies{networkIndex,informationIndex}.overallBestSensorIndices(:));
restrictedCoverageSensors=double( ...
    restrictedCampaign.studies{networkIndex,coverageIndex}.overallBestSensorIndices(:));

locationFig=figure("Name","Domain comparison sensor locations", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 10.0 5.4],"Renderer","opengl");
layout=tiledlayout(locationFig,1,2,"TileSpacing","compact","Padding","compact");

axFull=nexttile(layout,1);
plotLocationPanel(axFull,fullCampaign.database, ...
    fullInfoSensors,fullCoverageSensors,[-90 0],style);
title(axFull,"Southern hemisphere", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");

axRestricted=nexttile(layout,2);
plotLocationPanel(axRestricted,restrictedCampaign.database, ...
    restrictedInfoSensors,restrictedCoverageSensors,[-90 -75],style);
title(axRestricted,"Restricted south-polar domain", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold");

legendHandles=[ ...
    scatter(axFull,nan,nan,90,"o","MarkerFaceColor",style.blueColor, ...
        "MarkerEdgeColor",style.textColor,"LineWidth",0.8), ...
    scatter(axFull,nan,nan,90,"s","MarkerFaceColor",style.redColor, ...
        "MarkerEdgeColor",style.textColor,"LineWidth",0.8)];
lgd=legend(axFull,legendHandles, ...
    ["Information optimized","Coverage optimized"], ...
    "Location","northeast","Box","off");
lgd.FontName=style.fontName;
lgd.FontSize=max(14,style.legendFontSize-2);
lgd.FontWeight="bold";
lgd.AutoUpdate="off";

locationsFile=fullfile(outputDirectory,"domain_comparison_locations.eps");
exportManuscriptFigure(locationFig,string(locationsFile),10.0,5.4);

%% Coverage and information score comparison

fullCoverage=zeros(numel(networkSizes),1);
restrictedCoverage=zeros(numel(networkSizes),1);
fullInformation=zeros(numel(networkSizes),1);
restrictedInformation=zeros(numel(networkSizes),1);

for k=1:numel(networkSizes)
    fullCoverageState=bestRunState(fullCampaign.studies{k,coverageIndex});
    restrictedCoverageState=bestRunState(restrictedCampaign.studies{k,coverageIndex});
    fullInformationState=bestRunState(fullCampaign.studies{k,informationIndex});
    restrictedInformationState=bestRunState(restrictedCampaign.studies{k,informationIndex});

    fullCoverage(k)=fullCoverageState.bestCoverageScore;
    restrictedCoverage(k)=restrictedCoverageState.bestCoverageScore;
    fullInformation(k)=fullInformationState.bestInformationScore;
    restrictedInformation(k)=restrictedInformationState.bestInformationScore;
end

metricsFig=figure("Name","Domain comparison performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 10.0 5.4],"Renderer","opengl");
metricsLayout=tiledlayout(metricsFig,1,2, ...
    "TileSpacing","compact","Padding","compact");

ax=nexttile(metricsLayout,1);
plotComparisonMetric(ax,networkSizes,fullCoverage,restrictedCoverage, ...
    "Coverage score, C",style);
title(ax,"Coverage","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold");

ax=nexttile(metricsLayout,2);
plotComparisonMetric(ax,networkSizes,fullInformation,restrictedInformation, ...
    "Information score, I",style);
title(ax,"Information","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold");

metricHandles=[ ...
    plot(ax,nan,nan,"-o","Color",style.blueColor, ...
        "MarkerFaceColor",style.blueColor,"LineWidth",2.2), ...
    plot(ax,nan,nan,"--s","Color",style.redColor, ...
        "MarkerFaceColor",style.redColor,"LineWidth",2.2)];
lgd=legend(ax,metricHandles, ...
    ["Southern hemisphere","South-polar restriction"], ...
    "Location","northeast","Box","off");
lgd.FontName=style.fontName;
lgd.FontSize=max(14,style.legendFontSize-2);
lgd.FontWeight="bold";
lgd.AutoUpdate="off";

metricsFile=fullfile(outputDirectory,"domain_comparison_metrics.eps");
exportManuscriptFigure(metricsFig,string(metricsFile),10.0,5.4);

%% Common-budget manuscript table

objectiveIndex=find(objectiveModes==comparisonObjective,1);
fullStudy=fullCampaign.studies{networkIndex,objectiveIndex};
restrictedStudy=restrictedCampaign.studies{networkIndex,objectiveIndex};
fullState=bestRunState(fullStudy);
restrictedState=bestRunState(restrictedStudy);

fullSensors=double(fullStudy.overallBestSensorIndices(:));
restrictedSensors=double(restrictedStudy.overallBestSensorIndices(:));

fullTracking=trackingSummary( ...
    fullCampaign.database,fullSensors,measurementNoiseSeed);
restrictedTracking=trackingSummary( ...
    restrictedCampaign.database,restrictedSensors,measurementNoiseSeed);

quantity=[ ...
    "Candidate sites"; ...
    "Selected sensors"; ...
    "Coverage"; ...
    "Information"; ...
    "Tracking error"; ...
    "Longest observation gap"];

southernHemisphere=[ ...
    string(fullCampaign.database.meta.numberOfCandidates); ...
    string(comparisonNetworkSize); ...
    compose("%.6g",fullState.bestCoverageScore); ...
    compose("%.6g",fullState.bestInformationScore); ...
    compose("%.6g km",fullTracking.meanRmsPositionErrorKm); ...
    compose("%.6g min",fullTracking.longestObservationGapMinutes)];

southPolar=[ ...
    string(restrictedCampaign.database.meta.numberOfCandidates); ...
    string(comparisonNetworkSize); ...
    compose("%.6g",restrictedState.bestCoverageScore); ...
    compose("%.6g",restrictedState.bestInformationScore); ...
    compose("%.6g km",restrictedTracking.meanRmsPositionErrorKm); ...
    compose("%.6g min",restrictedTracking.longestObservationGapMinutes)];

summaryTable=table(quantity,southernHemisphere,southPolar, ...
    'VariableNames',{'Quantity','SouthernHemisphere','SouthPolar'});
tableFile=fullfile(tableDirectory,"domain_comparison.csv");
writetable(summaryTable,tableFile);

result=struct();
result.locationsFigure=locationFig;
result.locationsFile=string(locationsFile);
result.metricsFigure=metricsFig;
result.metricsFile=string(metricsFile);
result.table=summaryTable;
result.tableFile=string(tableFile);
result.comparisonNetworkSize=comparisonNetworkSize;
result.comparisonObjective=comparisonObjective;

fprintf("Domain-comparison products:\n");
fprintf("  %s\n",locationsFile);
fprintf("  %s\n",metricsFile);
fprintf("  %s\n",tableFile);
end

function state=bestRunState(study)
state=study.runStates{study.overallBestRunIndex};
end

function plotLocationPanel(ax,database,infoSensors,coverageSensors,limits,style)
hold(ax,"on");
infoLat=rad2deg(database.candidates.latitudesRad(infoSensors));
infoLon=mod(rad2deg(database.candidates.longitudesRad(infoSensors)),360);
coverageLat=rad2deg(database.candidates.latitudesRad(coverageSensors));
coverageLon=mod(rad2deg(database.candidates.longitudesRad(coverageSensors)),360);

scatter(ax,infoLon,infoLat,90,"o", ...
    "MarkerFaceColor",style.blueColor, ...
    "MarkerEdgeColor",style.textColor,"LineWidth",0.8, ...
    "HandleVisibility","off");
scatter(ax,coverageLon,coverageLat,90,"s", ...
    "MarkerFaceColor",style.redColor, ...
    "MarkerEdgeColor",style.textColor,"LineWidth",0.8, ...
    "HandleVisibility","off");

xlim(ax,[0 360]);
ylim(ax,limits);
xticks(ax,0:60:360);
if limits(2)==0
    yticks(ax,-90:15:0);
else
    yticks(ax,-90:5:-75);
end
xlabel(ax,"East longitude (deg)");
ylabel(ax,"Latitude (deg)");
ax.FontName=style.fontName;
ax.FontSize=style.axisFontSize;
ax.FontWeight="bold";
ax.LineWidth=0.9;
ax.TickDir="out";
ax.Box="on";
ax.XGrid="on";
ax.YGrid="on";
ax.GridColor=style.gridColor;
ax.GridAlpha=0.55;
ax.Layer="top";
end

function plotComparisonMetric(ax,networkSizes,fullValues,restrictedValues,yLabel,style)
hold(ax,"on");
plot(ax,networkSizes,fullValues,"-o", ...
    "Color",style.blueColor,"MarkerFaceColor",style.blueColor, ...
    "LineWidth",2.2,"MarkerSize",8,"HandleVisibility","off");
plot(ax,networkSizes,restrictedValues,"--s", ...
    "Color",style.redColor,"MarkerFaceColor",style.redColor, ...
    "LineWidth",2.2,"MarkerSize",8,"HandleVisibility","off");
xlabel(ax,"Number of sensors, N_s");
ylabel(ax,yLabel);
xticks(ax,networkSizes);
xlim(ax,[min(networkSizes)-0.5 max(networkSizes)+0.5]);
ax.FontName=style.fontName;
ax.FontSize=style.axisFontSize;
ax.FontWeight="bold";
ax.LineWidth=0.9;
ax.TickDir="out";
ax.Box="on";
ax.XGrid="on";
ax.YGrid="on";
ax.GridColor=style.gridColor;
ax.GridAlpha=0.55;
ax.Layer="top";
end

function summary=trackingSummary(database,sensorIndices,measurementNoiseSeed)
validationConfig=struct();
validationConfig.measurementNoiseSeed=measurementNoiseSeed;
validation=optimization.validateNetworkEkf( ...
    database,sensorIndices,validationConfig);

availability=loadAvailability(database,sensorIndices);
epochObservable=squeeze(any(availability,1));
if database.meta.numberOfObjects==1
    epochObservable=epochObservable(:);
end

longestGapEpochs=0;
for objectIndex=1:size(epochObservable,2)
    longestGapEpochs=max(longestGapEpochs, ...
        longestFalseRun(epochObservable(:,objectIndex)));
end

times=double(database.tracking.times(:));
if numel(times)>=2
    cadenceMinutes=median(diff(times))/60;
else
    cadenceMinutes=NaN;
end

summary=struct();
summary.meanRmsPositionErrorKm=mean(validation.rmsPositionErrorKm);
summary.longestObservationGapMinutes=longestGapEpochs*cadenceMinutes;
end

function availability=loadAvailability(database,sensorIndices)
if isfield(database.visibility,"candidateChunks") && ...
        ~isempty(database.visibility.candidateChunks)
    availability=optimization.loadChunkedCandidateData( ...
        database,sensorIndices,"filteredAvailability");
else
    availability=database.visibility.filteredAvailability(sensorIndices,:,:);
end
end

function longest=longestFalseRun(values)
values=logical(values(:));
transitions=diff([true;values;true]);
starts=find(transitions==-1);
stops=find(transitions==1)-1;
if isempty(starts)
    longest=0;
else
    longest=max(stops-starts+1);
end
end

function [summaryFile,studyState]=resolveCampaignAnchor(anchor,projectRoot,resultsDirectory)
anchor=string(anchor);
candidates=strings(0,1);

if isfile(anchor)
    candidates(end+1,1)=anchor;
elseif isfolder(anchor)
    candidates(end+1,1)=fullfile(anchor,"study_summary.mat");
else
    candidates(end+1,1)=fullfile( ...
        resultsDirectory,"optimization_runs",anchor,"study_summary.mat");
    candidates(end+1,1)=fullfile(projectRoot,anchor,"study_summary.mat");
end

summaryFile="";
for k=1:numel(candidates)
    if isfile(candidates(k))
        summaryFile=candidates(k);
        break
    end
end

assert(strlength(summaryFile)>0, ...
    "Restricted campaign anchor could not be resolved: %s",anchor);

data=load(summaryFile,"studyState");
assert(isfield(data,"studyState") && isfield(data.studyState,"config"), ...
    "Restricted campaign anchor does not contain a valid studyState.");
studyState=data.studyState;
end

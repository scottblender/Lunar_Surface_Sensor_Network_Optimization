function result = generateDomainComparisonProducts( ...
    fullCampaign,userConfig,restrictedCampaign)
% GENERATEDOMAINCOMPARISONPRODUCTS Compare full and restricted design domains.
%
% Outputs:
%   domain_comparison_locations.eps
%   domain_comparison_metrics.eps
%   tables/domain_comparison.csv
%
% The two EPS files are intended for the two half-width subfigures in the
% manuscript. Each is therefore kept to a compact source width so typography
% remains legible after LaTeX scaling.

arguments
    fullCampaign (1,1) struct
    userConfig (1,1) struct = struct()
    restrictedCampaign (1,1) struct = struct()
end

if isempty(fieldnames(restrictedCampaign))
    restrictedCampaign = loadRestrictedCampaign(fullCampaign,userConfig);
end

networkSizes = fullCampaign.configuration.networkSizes;
objectiveModes = fullCampaign.configuration.objectiveModes;
assert(isequal(networkSizes,restrictedCampaign.configuration.networkSizes), ...
    "Full and restricted campaigns use different network sizes.");
assert(isequal(objectiveModes,restrictedCampaign.configuration.objectiveModes), ...
    "Full and restricted campaigns use different objective modes.");

comparisonNetworkSize = max(networkSizes);
if isfield(userConfig,"comparisonNetworkSize")
    comparisonNetworkSize = double(userConfig.comparisonNetworkSize);
end
assert(ismember(comparisonNetworkSize,networkSizes), ...
    "comparisonNetworkSize must be one of the production network sizes.");

comparisonObjective = "information";
if isfield(userConfig,"comparisonObjective")
    comparisonObjective = lower(string(userConfig.comparisonObjective));
end
assert(ismember(comparisonObjective,objectiveModes), ...
    "comparisonObjective must be information or coverage.");

measurementNoiseSeed = 5000;
if isfield(userConfig,"measurementNoiseSeed")
    measurementNoiseSeed = double(userConfig.measurementNoiseSeed);
end

style = publicationPlotStyle();
outputDirectory = string(fullCampaign.outputDirectory);
tableDirectory = fullfile(outputDirectory,"tables");
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

informationIndex = find(objectiveModes=="information",1);
coverageIndex = find(objectiveModes=="coverage",1);
assert(~isempty(informationIndex) && ~isempty(coverageIndex), ...
    "Both information and coverage studies are required.");
networkIndex = find(networkSizes==comparisonNetworkSize,1);

%% Selected sensor locations: one readable comparison map

fullInfo = bestRunState(fullCampaign.studies{networkIndex,informationIndex});
fullCoverage = bestRunState(fullCampaign.studies{networkIndex,coverageIndex});
restrictedInfo = bestRunState( ...
    restrictedCampaign.studies{networkIndex,informationIndex});
restrictedCoverage = bestRunState( ...
    restrictedCampaign.studies{networkIndex,coverageIndex});

locationFig = figure("Name","Domain comparison sensor locations", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 7.0 4.8],"Renderer","opengl");
locationLayout = tiledlayout(locationFig,1,1,"Padding","loose");
ax = nexttile(locationLayout);
hold(ax,"on");

h1 = scatter(ax,mod(rad2deg(fullInfo.bestSensorLongitudesRad),360), ...
    rad2deg(fullInfo.bestSensorLatitudesRad),90,"o", ...
    "MarkerFaceColor",style.blueColor, ...
    "MarkerEdgeColor",style.textColor,"LineWidth",0.8);
h2 = scatter(ax,mod(rad2deg(fullCoverage.bestSensorLongitudesRad),360), ...
    rad2deg(fullCoverage.bestSensorLatitudesRad),90,"s", ...
    "MarkerFaceColor",style.redColor, ...
    "MarkerEdgeColor",style.textColor,"LineWidth",0.8);
h3 = scatter(ax,mod(rad2deg(restrictedInfo.bestSensorLongitudesRad),360), ...
    rad2deg(restrictedInfo.bestSensorLatitudesRad),105,"o", ...
    "MarkerFaceColor","none","MarkerEdgeColor",style.blueColor, ...
    "LineWidth",2.0);
h4 = scatter(ax,mod(rad2deg(restrictedCoverage.bestSensorLongitudesRad),360), ...
    rad2deg(restrictedCoverage.bestSensorLatitudesRad),105,"s", ...
    "MarkerFaceColor","none","MarkerEdgeColor",style.redColor, ...
    "LineWidth",2.0);

xlim(ax,[0 360]);
ylim(ax,[-90 0]);
xticks(ax,0:60:360);
yticks(ax,-90:15:0);
xlabel(ax,"East longitude (deg)");
ylabel(ax,"Latitude (deg)");
styleAxes(ax,style);

lgd = legend(ax,[h1 h2 h3 h4], ...
    ["Southern: information","Southern: coverage", ...
     "South-polar: information","South-polar: coverage"], ...
    "Location","none","Orientation","horizontal", ...
    "NumColumns",2,"Box","off");
lgd.FontName = style.fontName;
lgd.FontSize = 13;
lgd.FontWeight = "bold";
lgd.AutoUpdate = "off";
lgd.Layout.Tile = "north";

locationsFile = fullfile(outputDirectory,"domain_comparison_locations.eps");
exportManuscriptFigure(locationFig,string(locationsFile),7.0,4.8);

%% Coverage and information: BOTH studies as grouped bars

fullCoverageScore = zeros(numel(networkSizes),1);
restrictedCoverageScore = zeros(numel(networkSizes),1);
fullInformationScore = zeros(numel(networkSizes),1);
restrictedInformationScore = zeros(numel(networkSizes),1);

for k = 1:numel(networkSizes)
    state = bestRunState(fullCampaign.studies{k,coverageIndex});
    fullCoverageScore(k) = state.bestCoverageScore;
    state = bestRunState(restrictedCampaign.studies{k,coverageIndex});
    restrictedCoverageScore(k) = state.bestCoverageScore;
    state = bestRunState(fullCampaign.studies{k,informationIndex});
    fullInformationScore(k) = state.bestInformationScore;
    state = bestRunState(restrictedCampaign.studies{k,informationIndex});
    restrictedInformationScore(k) = state.bestInformationScore;
end

metricsFig = figure("Name","Domain comparison performance", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 7.0 7.0],"Renderer","opengl");
layout = tiledlayout(metricsFig,2,1, ...
    "TileSpacing","loose","Padding","loose");

axCoverage = nexttile(layout,1);
coverageHandles = plotComparisonBars(axCoverage,networkSizes, ...
    fullCoverageScore,restrictedCoverageScore, ...
    "Coverage score, C",style);
title(axCoverage,"Coverage","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold");

lgd = legend(axCoverage,coverageHandles, ...
    ["Southern hemisphere","Restricted south-polar"], ...
    "Location","none","Orientation","horizontal", ...
    "NumColumns",2,"Box","off");
lgd.FontName = style.fontName;
lgd.FontSize = 13;
lgd.FontWeight = "bold";
lgd.AutoUpdate = "off";
lgd.Layout.Tile = "north";

axInformation = nexttile(layout,2);
plotComparisonBars(axInformation,networkSizes, ...
    fullInformationScore,restrictedInformationScore, ...
    "Information score, I",style);
title(axInformation,"Information","FontName",style.fontName, ...
    "FontSize",style.labelFontSize,"FontWeight","bold");

metricsFile = fullfile(outputDirectory,"domain_comparison_metrics.eps");
exportManuscriptFigure(metricsFig,string(metricsFile),7.0,7.0);

%% Common-budget manuscript table

objectiveIndex = find(objectiveModes==comparisonObjective,1);
fullStudy = fullCampaign.studies{networkIndex,objectiveIndex};
restrictedStudy = restrictedCampaign.studies{networkIndex,objectiveIndex};
fullState = bestRunState(fullStudy);
restrictedState = bestRunState(restrictedStudy);

fullRun = bestRunState(fullStudy);
restrictedRun = bestRunState(restrictedStudy);

fullAvailability = optimization.buildFilteredVisibilityAtLocations( ...
    fullCampaign.database, ...
    fullRun.bestSensorLatitudesRad,fullRun.bestSensorLongitudesRad, ...
    userConfig);
restrictedAvailability = optimization.buildFilteredVisibilityAtLocations( ...
    fullCampaign.database, ...
    restrictedRun.bestSensorLatitudesRad,restrictedRun.bestSensorLongitudesRad, ...
    userConfig);

fullTracking = trackingSummary( ...
    fullCampaign.database, ...
    fullRun.bestSensorLatitudesRad,fullRun.bestSensorLongitudesRad, ...
    fullAvailability,measurementNoiseSeed,userConfig);
restrictedTracking = trackingSummary( ...
    fullCampaign.database, ...
    restrictedRun.bestSensorLatitudesRad,restrictedRun.bestSensorLongitudesRad, ...
    restrictedAvailability,measurementNoiseSeed,userConfig);

quantity = [ ...
    "Candidate sites"; ...
    "Selected sensors"; ...
    "Coverage"; ...
    "Information"; ...
    "Tracking error"; ...
    "Longest observation gap"];

southernHemisphere = [ ...
    string(fullRun.numberOfCandidates); ...
    string(comparisonNetworkSize); ...
    compose("%.6g",fullState.bestCoverageScore); ...
    compose("%.6g",fullState.bestInformationScore); ...
    compose("%.6g km",fullTracking.meanRmsPositionErrorKm); ...
    compose("%.6g min",fullTracking.longestObservationGapMinutes)];

southPolar = [ ...
    string(restrictedRun.numberOfCandidates); ...
    string(comparisonNetworkSize); ...
    compose("%.6g",restrictedState.bestCoverageScore); ...
    compose("%.6g",restrictedState.bestInformationScore); ...
    compose("%.6g km",restrictedTracking.meanRmsPositionErrorKm); ...
    compose("%.6g min",restrictedTracking.longestObservationGapMinutes)];

summaryTable = table(quantity,southernHemisphere,southPolar, ...
    'VariableNames',{'Quantity','SouthernHemisphere','SouthPolar'});
tableFile = fullfile(tableDirectory,"domain_comparison.csv");
writetable(summaryTable,tableFile);

result = struct();
result.restrictedCampaign = restrictedCampaign;
result.locationsFigure = locationFig;
result.locationsFile = string(locationsFile);
result.metricsFigure = metricsFig;
result.metricsFile = string(metricsFile);
result.table = summaryTable;
result.tableFile = string(tableFile);
result.comparisonNetworkSize = comparisonNetworkSize;
result.comparisonObjective = comparisonObjective;

fprintf("Domain-comparison products:\n");
fprintf("  %s\n",locationsFile);
fprintf("  %s\n",metricsFile);
fprintf("  %s\n",tableFile);
end

function state = bestRunState(study)
state = study.runStates{study.overallBestRunIndex};
end

function handles = plotComparisonBars( ...
    ax,networkSizes,fullValues,restrictedValues,yLabel,style)
values = [fullValues(:),restrictedValues(:)];
handles = bar(ax,1:numel(networkSizes),values,"grouped", ...
    "BarWidth",0.76,"LineStyle","none");
handles(1).FaceColor = style.blueColor;
handles(2).FaceColor = style.redColor;

xlabel(ax,"Number of sensors, N_s");
ylabel(ax,yLabel);
xticks(ax,1:numel(networkSizes));
xticklabels(ax,string(networkSizes));
xlim(ax,[0.5 numel(networkSizes)+0.5]);
styleAxes(ax,style);
end

function styleAxes(ax,style)
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

function summary = trackingSummary( ...
    database,sensorLatitudesRad,sensorLongitudesRad, ...
    availability,measurementNoiseSeed,userConfig)

validationConfig = struct();
validationConfig.measurementNoiseSeed = measurementNoiseSeed;
if isfield(userConfig,"demFile") && ...
        strlength(string(userConfig.demFile)) > 0
    validationConfig.demFile = string(userConfig.demFile);
end

validation = optimization.validateNetworkEkfAtLocations( ...
    database,sensorLatitudesRad,sensorLongitudesRad, ...
    availability,validationConfig);

epochObservable = squeeze(any(availability,1));
if database.meta.numberOfObjects == 1
    epochObservable = epochObservable(:);
end

longestGapEpochs = 0;
for objectIndex = 1:size(epochObservable,2)
    longestGapEpochs = max(longestGapEpochs, ...
        longestFalseRun(epochObservable(:,objectIndex)));
end

times = double(database.tracking.times(:));
if numel(times) >= 2
    cadenceMinutes = median(diff(times))/60;
else
    cadenceMinutes = NaN;
end

summary = struct();
summary.meanRmsPositionErrorKm = mean(validation.rmsPositionErrorKm);
summary.longestObservationGapMinutes = longestGapEpochs*cadenceMinutes;
end

function longest = longestFalseRun(values)
values = logical(values(:));
transitions = diff([true;values;true]);
starts = find(transitions==-1);
stops = find(transitions==1)-1;
if isempty(starts)
    longest = 0;
else
    longest = max(stops-starts+1);
end
end
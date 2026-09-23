function products = exportQuadChartFigures(userConfig)
% EXPORTQUADCHARTFIGURES Export a Figure 10 summary table and Figure 13 for a quad chart.
%
% This script reuses the same production results and screening calculations as
% the manuscript. Figure 10 is condensed to a presentation-ready table of the
% most frequently selected geographic bins, while Figure 13 is retained as a
% presentation-format constraint-screening figure.
%
% Outputs:
%   quadchart_figure10_selection_table.pdf
%   quadchart_figure13_constraint_screening.pdf
%
% Example:
%   products = exportQuadChartFigures();
%
%   cfg = struct();
%   cfg.outputDirectory = "C:\\Users\\me\\Desktop\\quadchart";
%   products = exportQuadChartFigures(cfg);

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
addpath(scriptDirectory);
addpath(sourceDirectory);
rehash path;

defaults = struct();
defaults.outputDirectory = fullfile(projectRoot,"results","quadchart_artifacts");
defaults.productionCampaignDates = ["20260918","20260919"];
defaults.restrictedCampaignDate = "20260915";
defaults.restrictedCampaignAnchor = "";
defaults.restrictedResultsDirectory = "";
defaults.restrictedStudyName = "";
defaults.comparisonNetworkSize = 10;
defaults.comparisonObjective = "information";
defaults.figure10TableSizeInches = [10.5 6.4];
defaults.topSelectionBins = 3;
defaults.figure13SizeInches = [12.4 8.2];
config = mergeStruct(defaults,userConfig);

config.outputDirectory = string(config.outputDirectory);
config.productionCampaignDates = string(config.productionCampaignDates(:));
config.restrictedCampaignDate = string(config.restrictedCampaignDate);
config.restrictedCampaignAnchor = string(config.restrictedCampaignAnchor);
config.restrictedResultsDirectory = string(config.restrictedResultsDirectory);
config.restrictedStudyName = string(config.restrictedStudyName);

if ~isfolder(config.outputDirectory)
    mkdir(config.outputDirectory);
end

% Keep the export workflow non-interactive: helper routines still create
% MATLAB figures internally, but none of them should open preview windows.
previousFigureVisibility = get(groot,"defaultFigureVisible");
set(groot,"defaultFigureVisible","off");
visibilityCleanup = onCleanup(@()set(groot, ...
    "defaultFigureVisible",previousFigureVisibility));

%% Load the same campaigns used by the manuscript

campaignConfig = struct();
campaignConfig.outputDirectory = config.outputDirectory;
campaignConfig.campaignDates = config.productionCampaignDates;
campaignConfig.requireDatabaseMatch = true;
fullCampaign = loadProductionCampaign(campaignConfig);

restrictedConfig = struct();
restrictedConfig.restrictedCampaignDate = config.restrictedCampaignDate;
restrictedConfig.restrictedCampaignAnchor = config.restrictedCampaignAnchor;
restrictedConfig.restrictedResultsDirectory = config.restrictedResultsDirectory;
restrictedConfig.restrictedStudyName = config.restrictedStudyName;
restrictedCampaign = loadRestrictedCampaign(fullCampaign,restrictedConfig);

%% Reuse manuscript calculations in a scratch directory

scratchDirectory = fullfile(config.outputDirectory,"_quadchart_scratch");
if isfolder(scratchDirectory)
    rmdir(scratchDirectory,"s");
end
mkdir(scratchDirectory);
cleanupObject = onCleanup(@()cleanupScratch(scratchDirectory));

rawConfig = struct();
rawConfig.outputDirectory = scratchDirectory;
rawConfig.comparisonNetworkSize = config.comparisonNetworkSize;
rawConfig.comparisonObjective = config.comparisonObjective;
rawConfig.exportDiagnosticTables = false;

% Figure 10 data: compute the same information-driven geographic-bin
% selection frequencies used by the manuscript, but without creating the
% four polar-map preview figures.
selectionData = computeInformationSelectionFrequency(fullCampaign);

% Figure 13 data: exact screening percentages used in the manuscript.
screeningData = plotMeasurementScreeningBreakdown( ...
    fullCampaign,restrictedCampaign,rawConfig);

if isfield(screeningData,"figure") && isgraphics(screeningData.figure)
    close(screeningData.figure);
end

%% Figure 10 summary table -- information-driven selection recurrence

style = publicationPlotStyle();
[figure10Table,selectionSummaryTable] = buildSelectionFrequencyTable( ...
    selectionData,fullCampaign,style,config.figure10TableSizeInches, ...
    config.topSelectionBins);

figure10Base = fullfile(config.outputDirectory, ...
    "quadchart_figure10_selection_table");
figure10Files = exportPowerPointFigure( ...
    figure10Table,figure10Base,config.figure10TableSizeInches);

%% Figure 13 -- constraint screening by RSO

figure13 = buildConstraintScreeningFigure( ...
    screeningData.fullPercent,screeningData.polarPercent, ...
    style,config.figure13SizeInches);

figure13Base = fullfile(config.outputDirectory, ...
    "quadchart_figure13_constraint_screening");
figure13Files = exportPowerPointFigure( ...
    figure13,figure13Base,config.figure13SizeInches);

close(figure10Table);
close(figure13);

products = struct();
products.outputDirectory = config.outputDirectory;
products.figure10Table = struct( ...
    "files",figure10Files, ...
    "summaryTable",selectionSummaryTable, ...
    "selectionPercent",selectionData.selectionPercent);
products.figure13 = struct( ...
    "files",figure13Files, ...
    "fullPercent",screeningData.fullPercent, ...
    "polarPercent",screeningData.polarPercent);

fprintf("\n============================================================\n");
fprintf("Quad-chart figure export complete\n");
fprintf("============================================================\n");
fprintf("Figure 10 summary-table PDF: %s\n",figure10Files.pdf);
fprintf("Figure 13 PDF: %s\n",figure13Files.pdf);

clear cleanupObject;
cleanupScratch(scratchDirectory);
clear visibilityCleanup;
end

function selectionData = computeInformationSelectionFrequency(campaign)
% Compute the same binned recurrence percentages shown in manuscript Figure 10.

latitudeEdges = -90:10:0;
longitudeEdges = 0:30:360;
networkSizes = double(campaign.configuration.networkSizes(:).');
objectiveModes = lower(string(campaign.configuration.objectiveModes(:).'));
objectiveIndex = find(objectiveModes=="information",1);
assert(~isempty(objectiveIndex), ...
    "Information-driven optimization results are unavailable.");

frequency = zeros( ...
    numel(latitudeEdges)-1, ...
    numel(longitudeEdges)-1, ...
    numel(networkSizes));

for networkIndex = 1:numel(networkSizes)
    study = campaign.studies{networkIndex,objectiveIndex};
    numberOfRuns = min( ...
        campaign.configuration.numberOfRuns, ...
        numel(study.runStates));
    runs = study.runStates(1:numberOfRuns);

    frequency(:,:,networkIndex) = binNetworkSelectionFrequency( ...
        runs,campaign.database,latitudeEdges,longitudeEdges);
end

selectionData = struct();
selectionData.selectionPercent = frequency;
selectionData.latitudeEdges = latitudeEdges;
selectionData.longitudeEdges = longitudeEdges;
selectionData.networkSizes = networkSizes;
end

function [fig,summaryTable] = buildSelectionFrequencyTable( ...
    selectionData,campaign,style,figureSize,topN)
% Condense Figure 10 into a quad-chart-friendly table of recurring bins.

validateattributes(topN,{'numeric'},{'scalar','integer','positive'});
frequency = double(selectionData.selectionPercent);
latitudeEdges = double(selectionData.latitudeEdges);
longitudeEdges = double(selectionData.longitudeEdges);
networkSizes = double(selectionData.networkSizes(:).');

numberOfRows = numel(networkSizes)*topN;
networkColumn = zeros(numberOfRows,1);
rankColumn = zeros(numberOfRows,1);
latitudeColumn = strings(numberOfRows,1);
longitudeColumn = strings(numberOfRows,1);
frequencyColumn = zeros(numberOfRows,1);

row = 0;
for networkIndex = 1:numel(networkSizes)
    values = frequency(:,:,networkIndex);
    [sortedValues,sortedIndices] = sort(values(:),"descend");

    keep = min(topN,numel(sortedIndices));
    for rankIndex = 1:keep
        row = row+1;
        [latitudeIndex,longitudeIndex] = ind2sub( ...
            size(values),sortedIndices(rankIndex));

        networkColumn(row) = networkSizes(networkIndex);
        rankColumn(row) = rankIndex;
        latitudeColumn(row) = formatSouthLatitudeBin( ...
            latitudeEdges(latitudeIndex),latitudeEdges(latitudeIndex+1));
        longitudeColumn(row) = sprintf("%d--%d deg E", ...
            longitudeEdges(longitudeIndex), ...
            longitudeEdges(longitudeIndex+1));
        frequencyColumn(row) = sortedValues(rankIndex);
    end
end

networkColumn = networkColumn(1:row);
rankColumn = rankColumn(1:row);
latitudeColumn = latitudeColumn(1:row);
longitudeColumn = longitudeColumn(1:row);
frequencyColumn = frequencyColumn(1:row);

summaryTable = table( ...
    networkColumn,rankColumn,latitudeColumn,longitudeColumn,frequencyColumn, ...
    'VariableNames',{ ...
    'NetworkSize','Rank','LatitudeBin','LongitudeBin', ...
    'SelectionFrequencyPercent'});

fig = figure( ...
    "Name","Quad chart - Figure 10 selection summary", ...
    "Color","white", ...
    "Units","inches", ...
    "Position",[1 1 figureSize], ...
    "Renderer","painters", ...
    "InvertHardcopy","off", ...
    "Visible","off");

ax = axes(fig,"Position",[0 0 1 1],"Visible","off");
hold(ax,"on");
xlim(ax,[0 1]);
ylim(ax,[0 1]);

text(ax,0.5,0.955, ...
    "Information-driven sensor-selection recurrence", ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "FontName",style.fontName, ...
    "FontSize",22, ...
    "FontWeight","bold");

text(ax,0.5,0.905, ...
    sprintf("Top %d geographic bins for each network size across %d independent GA runs", ...
    topN,campaign.configuration.numberOfRuns), ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "FontName",style.fontName, ...
    "FontSize",14, ...
    "FontWeight","bold");

headers = ["N_s","Rank","Latitude bin","Longitude bin","Selection frequency"];
columnEdges = [0.055 0.16 0.26 0.50 0.75 0.945];
tableTop = 0.855;
tableBottom = 0.135;
headerHeight = 0.065;
dataHeight = (tableTop-tableBottom-headerHeight)/height(summaryTable);

% Header background and table border.
rectangle(ax,"Position",[columnEdges(1) tableTop-headerHeight ...
    columnEdges(end)-columnEdges(1) headerHeight], ...
    "FaceColor",[0.92 0.92 0.93], ...
    "EdgeColor",[0.25 0.25 0.25], ...
    "LineWidth",1.1);

for columnIndex = 1:numel(headers)
    xCenter = mean(columnEdges(columnIndex:columnIndex+1));
    text(ax,xCenter,tableTop-headerHeight/2,headers(columnIndex), ...
        "HorizontalAlignment","center", ...
        "VerticalAlignment","middle", ...
        "FontName",style.fontName, ...
        "FontSize",13, ...
        "FontWeight","bold");
end

% Data rows.
for rowIndex = 1:height(summaryTable)
    yTop = tableTop-headerHeight-(rowIndex-1)*dataHeight;
    yBottom = yTop-dataHeight;

    if mod(ceil(rowIndex/topN),2)==0
        rowColor = [0.975 0.975 0.98];
    else
        rowColor = [1 1 1];
    end

    rectangle(ax,"Position",[columnEdges(1) yBottom ...
        columnEdges(end)-columnEdges(1) dataHeight], ...
        "FaceColor",rowColor, ...
        "EdgeColor","none");

    values = [ ...
        sprintf("%d",summaryTable.NetworkSize(rowIndex)), ...
        sprintf("%d",summaryTable.Rank(rowIndex)), ...
        summaryTable.LatitudeBin(rowIndex), ...
        summaryTable.LongitudeBin(rowIndex), ...
        sprintf("%.0f%%",summaryTable.SelectionFrequencyPercent(rowIndex))];

    for columnIndex = 1:numel(values)
        xCenter = mean(columnEdges(columnIndex:columnIndex+1));
        text(ax,xCenter,mean([yTop yBottom]),values(columnIndex), ...
            "HorizontalAlignment","center", ...
            "VerticalAlignment","middle", ...
            "FontName",style.fontName, ...
            "FontSize",12.5, ...
            "FontWeight","bold");
    end

    % Stronger separator after each network-size group.
    if mod(rowIndex,topN)==0
        line(ax,[columnEdges(1) columnEdges(end)], ...
            [yBottom yBottom], ...
            "Color",[0.25 0.25 0.25], ...
            "LineWidth",1.05);
    else
        line(ax,[columnEdges(1) columnEdges(end)], ...
            [yBottom yBottom], ...
            "Color",[0.78 0.78 0.80], ...
            "LineWidth",0.55);
    end
end

% Vertical rules.
for edgeIndex = 1:numel(columnEdges)
    line(ax,[columnEdges(edgeIndex) columnEdges(edgeIndex)], ...
        [tableBottom tableTop], ...
        "Color",[0.45 0.45 0.47], ...
        "LineWidth",0.7);
end

% Outer border.
rectangle(ax,"Position",[columnEdges(1) tableBottom ...
    columnEdges(end)-columnEdges(1) tableTop-tableBottom], ...
    "FaceColor","none", ...
    "EdgeColor",[0.25 0.25 0.25], ...
    "LineWidth",1.1);

text(ax,0.5,0.070, ...
    sprintf(["Selection frequency is the fraction of %d runs in which at least " ...
    "one optimized sensor lies in the 10 deg latitude x 30 deg longitude bin."], ...
    campaign.configuration.numberOfRuns), ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","middle", ...
    "FontName",style.fontName, ...
    "FontSize",11.5, ...
    "FontWeight","bold");

drawnow;
end

function label = formatSouthLatitudeBin(lowerEdge,upperEdge)
% Display negative lunar latitudes as an intuitive south-latitude range.
southA = abs(lowerEdge);
southB = abs(upperEdge);
label = sprintf("%d--%d deg S",southA,southB);
end

function fig = buildConstraintScreeningFigure( ...
    fullPercent,polarPercent,style,figureSize)
% Presentation layout for manuscript Figure 13.
%
% The figure is intentionally taller than the manuscript version so the 20
% RSO rows remain distinct after insertion into a PowerPoint quad chart.

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

numberOfRsos = size(fullPercent,1);
assert(isequal(size(fullPercent),size(polarPercent)), ...
    "Screening arrays must have the same dimensions.");

fig = figure( ...
    "Name","Quad chart - Figure 13", ...
    "Color","white", ...
    "Units","inches", ...
    "Position",[1 1 figureSize], ...
    "Renderer","painters", ...
    "InvertHardcopy","off", ...
    "Visible","off");

layout = tiledlayout(fig,1,2, ...
    "TileSpacing","loose", ...
    "Padding","loose");
layout.Units = "normalized";
layout.OuterPosition = [0.035 0.09 0.93 0.80];

domains = ["Southern hemisphere","Restricted south-polar"];
values = {fullPercent,polarPercent};

for domainIndex = 1:2
    ax = nexttile(layout,domainIndex);

    bars = barh(ax,1:numberOfRsos,values{domainIndex},0.68, ...
        "stacked","EdgeColor","none");

    for categoryIndex = 1:numel(categoryNames)
        bars(categoryIndex).FaceColor = categoryColors(categoryIndex,:);
    end

    ax.YDir = "reverse";
    ax.YTick = 1:numberOfRsos;
    if domainIndex == 1
        ax.YTickLabel = compose("RSO %02d",1:numberOfRsos);
    else
        ax.YTickLabel = [];
    end

    ax.FontName = style.fontName;
    ax.FontSize = 11.5;
    ax.FontWeight = "bold";
    ax.TickDir = "out";
    ax.Box = "on";
    xlim(ax,[0 100]);
    ylim(ax,[0.35 numberOfRsos+0.65]);
    xticks(ax,0:25:100);

    title(ax,domains(domainIndex), ...
        "FontName",style.fontName, ...
        "FontSize",18, ...
        "FontWeight","bold");

    if domainIndex == 1
        legendHandle = legend(ax,bars,categoryNames, ...
            "NumColumns",3, ...
            "Orientation","horizontal", ...
            "Box","off");
        legendHandle.FontName = style.fontName;
        legendHandle.FontSize = 12;
        legendHandle.FontWeight = "bold";
        legendHandle.AutoUpdate = "off";
        legendHandle.Layout.Tile = "north";
    end
end

xlabel(layout,"Measurement opportunities (%)", ...
    "FontName",style.fontName, ...
    "FontSize",17, ...
    "FontWeight","bold");

applyPresentationFont(fig,style.fontName);
drawnow;
end

function files = exportPowerPointFigure(fig,baseFile,figureSize)
% Export only a vector PDF. The PDF can be converted to SVG in Inkscape.

fig.Color = "white";
fig.InvertHardcopy = "off";
fig.Units = "inches";
fig.Position(3:4) = figureSize;
fig.PaperUnits = "inches";
fig.PaperSize = figureSize;
fig.PaperPosition = [0 0 figureSize];
fig.PaperPositionMode = "manual";
drawnow;

pdfFile = string(baseFile) + ".pdf";

exportgraphics(fig,char(pdfFile), ...
    "ContentType","vector", ...
    "BackgroundColor","white");

files = struct("pdf",pdfFile);
end

function applyPresentationFont(fig,fontName)
objects = findall(fig);
for objectIndex = 1:numel(objects)
    if isprop(objects(objectIndex),"FontName")
        try
            objects(objectIndex).FontName = fontName;
        catch
        end
    end
end
end

function cleanupScratch(scratchDirectory)
if isfolder(scratchDirectory)
    try
        rmdir(scratchDirectory,"s");
    catch
    end
end
end

function out = mergeStruct(defaults,override)
out = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    out.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end

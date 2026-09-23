function products = exportQuadChartFigures(userConfig)
% EXPORTQUADCHARTFIGURES Export a raw Figure 10 summary table and Figure 13 for a quad chart.
%
% This script reuses the same production results and screening calculations as
% the manuscript. Figure 10 is condensed to a presentation-ready table of the
% most frequently selected geographic bins, while Figure 13 is retained as a
% presentation-format constraint-screening figure.
%
% Outputs:
%   quadchart_figure10_selection_table.xlsx
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

%% Figure 10 summary table -- raw data for PowerPoint

style = publicationPlotStyle();
selectionSummaryTable = buildSelectionFrequencyTable( ...
    selectionData,config.topSelectionBins);

figure10TableFile = fullfile(config.outputDirectory, ...
    "quadchart_figure10_selection_table.xlsx");
writetable(selectionSummaryTable,figure10TableFile);

% Also print the table so it can be copied directly from the Command Window.
fprintf("\nFigure 10 selection-frequency summary table:\n");
disp(selectionSummaryTable);

%% Figure 13 -- constraint screening by RSO

figure13 = buildConstraintScreeningFigure( ...
    screeningData.fullPercent,screeningData.polarPercent, ...
    style,config.figure13SizeInches);

figure13Base = fullfile(config.outputDirectory, ...
    "quadchart_figure13_constraint_screening");
figure13Files = exportPowerPointFigure( ...
    figure13,figure13Base,config.figure13SizeInches);

close(figure13);

products = struct();
products.outputDirectory = config.outputDirectory;
products.figure10Table = struct( ...
    "file",string(figure10TableFile), ...
    "summaryTable",selectionSummaryTable, ...
    "selectionPercent",selectionData.selectionPercent);
products.figure13 = struct( ...
    "files",figure13Files, ...
    "fullPercent",screeningData.fullPercent, ...
    "polarPercent",screeningData.polarPercent);

fprintf("\n============================================================\n");
fprintf("Quad-chart figure export complete\n");
fprintf("============================================================\n");
fprintf("Figure 10 raw table: %s\n",figure10TableFile);
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

function summaryTable = buildSelectionFrequencyTable(selectionData,topN)
% Build a raw table of the most frequently selected Figure 10 bins.

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
    'N_s','Rank','LatitudeBin','LongitudeBin','SelectionFrequencyPercent'});
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

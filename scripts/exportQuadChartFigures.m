function products = exportQuadChartFigures(userConfig)
% EXPORTQUADCHARTFIGURES Export Figures 10 and 13 for PowerPoint/quad charts.
%
% This script reuses the same production results and screening calculations as
% the manuscript, but rebuilds the two figures for a wide presentation panel
% rather than for LaTeX/EPS placement.
%
% Outputs:
%   quadchart_figure10_selection_frequency.pdf
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
defaults.figure10SizeInches = [13.0 10.0];
defaults.figure13SizeInches = [12.4 8.2];
defaults.keepFiguresOpen = true;
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

% Figure 10 data: selection frequencies from the same 20-run campaigns.
networkData = plotProductionNetworkLocations(fullCampaign,rawConfig);

% Figure 13 data: exact screening percentages used in the manuscript.
screeningData = plotMeasurementScreeningBreakdown( ...
    fullCampaign,restrictedCampaign,rawConfig);

% Close only the temporary manuscript-format figures.
closeTemporaryFigure(networkData,"information");
closeTemporaryFigure(networkData,"coverage");
if isfield(screeningData,"figure") && isgraphics(screeningData.figure)
    close(screeningData.figure);
end

%% Figure 10 -- information-driven sensor-selection frequency

style = publicationPlotStyle();
figure10 = buildSelectionFrequencyFigure( ...
    networkData.information,fullCampaign,style,config.figure10SizeInches);

figure10Base = fullfile(config.outputDirectory, ...
    "quadchart_figure10_selection_frequency");
figure10Files = exportPowerPointFigure( ...
    figure10,figure10Base,config.figure10SizeInches);

%% Figure 13 -- constraint screening by RSO

figure13 = buildConstraintScreeningFigure( ...
    screeningData.fullPercent,screeningData.polarPercent, ...
    style,config.figure13SizeInches);

figure13Base = fullfile(config.outputDirectory, ...
    "quadchart_figure13_constraint_screening");
figure13Files = exportPowerPointFigure( ...
    figure13,figure13Base,config.figure13SizeInches);

if ~config.keepFiguresOpen
    close(figure10);
    close(figure13);
end

products = struct();
products.outputDirectory = config.outputDirectory;
products.figure10 = struct( ...
    "figure",figure10, ...
    "files",figure10Files, ...
    "selectionPercent",networkData.information.selectionPercent);
products.figure13 = struct( ...
    "figure",figure13, ...
    "files",figure13Files, ...
    "fullPercent",screeningData.fullPercent, ...
    "polarPercent",screeningData.polarPercent);

fprintf("\n============================================================\n");
fprintf("Quad-chart figure export complete\n");
fprintf("============================================================\n");
fprintf("Figure 10 PDF: %s\n",figure10Files.pdf);
fprintf("Figure 13 PDF: %s\n",figure13Files.pdf);

clear cleanupObject;
cleanupScratch(scratchDirectory);
end

function fig = buildSelectionFrequencyFigure(plotInfo,campaign,style,figureSize)
% Presentation layout for manuscript Figure 10.
%
% Retain the 2x2 tiled layout so the four polar maps remain large. The
% presentation canvas is enlarged and generous loose tile spacing is used
% so the cardinal labels and N_s headings do not crowd adjacent panels.

latitudeEdges = double(plotInfo.latitudeEdges);
longitudeEdges = double(plotInfo.longitudeEdges);
frequency = double(plotInfo.selectionPercent);
networkSizes = double(campaign.configuration.networkSizes(:).');

projectRoot = string(campaign.projectRoot);
demFile = fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat");
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    demFile,campaign.database.config.moon.radiusKm,24,48);

fig = figure( ...
    "Name","Quad chart - Figure 10", ...
    "Color","white", ...
    "Units","inches", ...
    "Position",[1 1 figureSize], ...
    "Renderer","opengl", ...
    "InvertHardcopy","off");

layout = tiledlayout(fig,2,2, ...
    "TileSpacing","loose", ...
    "Padding","loose");
layout.Units = "normalized";

% Reserve a generous frame around the tiled region and leave a dedicated
% band below it for the two shared colorbars.
layout.OuterPosition = [0.055 0.19 0.89 0.76];

mapStyle = style;
mapStyle.axisFontSize = 14;
mapStyle.labelFontSize = 16;

terrainLimits = [0 1];
lastAxis = gobjects(1);

for networkIndex = 1:numel(networkSizes)
    ax = nexttile(layout,networkIndex);

    terrainLimits = plotPolarSelectionMap( ...
        ax,frequency(:,:,networkIndex), ...
        latitudeEdges,longitudeEdges,dem,mapStyle);

    title(ax,sprintf("N_s = %d",networkSizes(networkIndex)), ...
        "FontName",style.fontName, ...
        "FontSize",18, ...
        "FontWeight","bold", ...
        "Interpreter","tex");
    lastAxis = ax;
end

% Selection-frequency scale.
frequencyAxes = axes(fig, ...
    "Visible","off", ...
    "Units","normalized", ...
    "Position",[0.075 0.050 0.37 0.01]);
colormap(frequencyAxes,colormap(lastAxis));
clim(frequencyAxes,[0 100]);
frequencyBar = colorbar(frequencyAxes,"southoutside");
frequencyBar.Units = "normalized";
frequencyBar.Position = [0.075 0.050 0.37 0.026];
frequencyBar.Ticks = 0:20:100;
frequencyBar.FontName = style.fontName;
frequencyBar.FontSize = 13;
frequencyBar.FontWeight = "bold";
frequencyBar.Label.String = "Selection frequency (%)";
frequencyBar.Label.FontName = style.fontName;
frequencyBar.Label.FontSize = 15;
frequencyBar.Label.FontWeight = "bold";
frequencyAxes.Visible = "off";

% Elevation scale.
terrainAxes = axes(fig, ...
    "Visible","off", ...
    "Units","normalized", ...
    "Position",[0.555 0.050 0.37 0.01]);
colormap(terrainAxes,repmat(linspace(0.30,0.96,256).',1,3));
clim(terrainAxes,terrainLimits);
elevationBar = colorbar(terrainAxes,"southoutside");
elevationBar.Units = "normalized";
elevationBar.Position = [0.555 0.050 0.37 0.026];
elevationBar.FontName = style.fontName;
elevationBar.FontSize = 13;
elevationBar.FontWeight = "bold";
elevationBar.Label.String = "Elevation (km)";
elevationBar.Label.FontName = style.fontName;
elevationBar.Label.FontSize = 15;
elevationBar.Label.FontWeight = "bold";
terrainAxes.Visible = "off";

applyPresentationFont(fig,style.fontName);
drawnow;
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
    "InvertHardcopy","off");

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

function closeTemporaryFigure(data,fieldName)
if isfield(data,fieldName)
    item = data.(fieldName);
    if isstruct(item) && isfield(item,"figure") && isgraphics(item.figure)
        close(item.figure);
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

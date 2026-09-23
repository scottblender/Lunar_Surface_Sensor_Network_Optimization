function products = exportQuadChartFigures(userConfig)
% EXPORTQUADCHARTFIGURES Export Figures 10 and 13 for PowerPoint/quad charts.
%
% This script reuses the same production results and screening calculations as
% the manuscript, but rebuilds the two figures for a wide presentation panel
% rather than for LaTeX/EPS placement.
%
% Outputs:
%   quadchart_figure10_selection_frequency.svg/.pdf/.png
%   quadchart_figure13_constraint_screening.svg/.pdf/.png
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
defaults.pngResolution = 600;
defaults.figure10SizeInches = [10.8 7.2];
defaults.figure13SizeInches = [12.8 5.4];
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
    figure10,figure10Base,config.figure10SizeInches,config.pngResolution);

%% Figure 13 -- constraint screening by RSO

figure13 = buildConstraintScreeningFigure( ...
    screeningData.fullPercent,screeningData.polarPercent, ...
    style,config.figure13SizeInches);

figure13Base = fullfile(config.outputDirectory, ...
    "quadchart_figure13_constraint_screening");
figure13Files = exportPowerPointFigure( ...
    figure13,figure13Base,config.figure13SizeInches,config.pngResolution);

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
fprintf("Figure 10 SVG: %s\n",figure10Files.svg);
fprintf("Figure 13 SVG: %s\n",figure13Files.svg);
fprintf("PNG fallbacks are exported at %d dpi.\n",config.pngResolution);

clear cleanupObject;
cleanupScratch(scratchDirectory);
end

function fig = buildSelectionFrequencyFigure(plotInfo,campaign,style,figureSize)
% Use a balanced 2x2 layout so each polar map remains readable in a quad-chart panel.

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

% A 2x2 arrangement gives each circular map a nearly square tile and avoids
% the crowding that occurs in a 1x4 PowerPoint layout.
layout = tiledlayout(fig,2,2, ...
    "TileSpacing","loose","Padding","compact");
layout.Units = "normalized";
layout.OuterPosition = [0.035 0.20 0.93 0.775];

% Presentation-specific map typography. These values remain readable after
% insertion into a half-slide quadrant without crowding the longitude labels.
mapStyle = style;
mapStyle.axisFontSize = 16;
mapStyle.labelFontSize = 18;

terrainLimits = [0 1];
lastAxis = gobjects(1);
for networkIndex = 1:numel(networkSizes)
    ax = nexttile(layout,networkIndex);
    terrainLimits = plotPolarSelectionMap( ...
        ax,frequency(:,:,networkIndex), ...
        latitudeEdges,longitudeEdges,dem,mapStyle);
    title(ax,sprintf("N_s = %d",networkSizes(networkIndex)), ...
        "FontName",style.fontName, ...
        "FontSize",20, ...
        "FontWeight","bold", ...
        "Interpreter","tex");
    lastAxis = ax;
end

% Selection-frequency color scale.
frequencyAxes = axes(fig, ...
    "Visible","off", ...
    "Units","normalized", ...
    "Position",[0.08 0.070 0.36 0.01]);
colormap(frequencyAxes,colormap(lastAxis));
clim(frequencyAxes,[0 100]);
frequencyBar = colorbar(frequencyAxes,"southoutside");
frequencyBar.Units = "normalized";
frequencyBar.Position = [0.08 0.070 0.36 0.030];
frequencyBar.Ticks = 0:20:100;
frequencyBar.FontName = style.fontName;
frequencyBar.FontSize = 15;
frequencyBar.FontWeight = "bold";
frequencyBar.Label.String = "Selection frequency (%)";
frequencyBar.Label.FontName = style.fontName;
frequencyBar.Label.FontSize = 17;
frequencyBar.Label.FontWeight = "bold";
frequencyAxes.Visible = "off";

% DEM elevation color scale.
terrainAxes = axes(fig, ...
    "Visible","off", ...
    "Units","normalized", ...
    "Position",[0.56 0.070 0.36 0.01]);
colormap(terrainAxes,repmat(linspace(0.30,0.96,256).',1,3));
clim(terrainAxes,terrainLimits);
elevationBar = colorbar(terrainAxes,"southoutside");
elevationBar.Units = "normalized";
elevationBar.Position = [0.56 0.070 0.36 0.030];
elevationBar.FontName = style.fontName;
elevationBar.FontSize = 15;
elevationBar.FontWeight = "bold";
elevationBar.Label.String = "Elevation (km)";
elevationBar.Label.FontName = style.fontName;
elevationBar.Label.FontSize = 17;
elevationBar.Label.FontWeight = "bold";
terrainAxes.Visible = "off";

applyPresentationFont(fig,style.fontName);
drawnow;
end

function fig = buildConstraintScreeningFigure( ...
    fullPercent,polarPercent,style,figureSize)

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
    "TileSpacing","compact","Padding","compact");

domains = ["Southern hemisphere","Restricted south-polar"];
values = {fullPercent,polarPercent};

for domainIndex = 1:2
    ax = nexttile(layout,domainIndex);
    bars = barh(ax,1:numberOfRsos,values{domainIndex},0.80, ...
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
    ax.FontSize = 18;
    ax.FontWeight = "bold";
    ax.TickDir = "out";
    ax.Box = "on";
    xlim(ax,[0 100]);
    ylim(ax,[0.4 numberOfRsos+0.6]);
    xticks(ax,0:25:100);

    title(ax,domains(domainIndex), ...
        "FontName",style.fontName, ...
        "FontSize",22, ...
        "FontWeight","bold");

    if domainIndex == 1
        legendHandle = legend(ax,bars,categoryNames, ...
            "NumColumns",3, ...
            "Orientation","horizontal", ...
            "Box","off");
        legendHandle.FontName = style.fontName;
        legendHandle.FontSize = 18;
        legendHandle.FontWeight = "bold";
        legendHandle.AutoUpdate = "off";
        legendHandle.Layout.Tile = "north";
    end
end

xlabel(layout,"Measurement opportunities (%)", ...
    "FontName",style.fontName, ...
    "FontSize",22, ...
    "FontWeight","bold");

applyPresentationFont(fig,style.fontName);
drawnow;
end

function files = exportPowerPointFigure(fig,baseFile,figureSize,pngResolution)
% Export an SVG for PowerPoint, a vector PDF backup, and a high-DPI PNG.

fig.Color = "white";
fig.InvertHardcopy = "off";
fig.Units = "inches";
fig.Position(3:4) = figureSize;
fig.PaperUnits = "inches";
fig.PaperSize = figureSize;
fig.PaperPosition = [0 0 figureSize];
fig.PaperPositionMode = "manual";
drawnow;

svgFile = string(baseFile) + ".svg";
pdfFile = string(baseFile) + ".pdf";
pngFile = string(baseFile) + ".png";

% SVG is the preferred PowerPoint format because text and linework remain sharp.
print(fig,char(svgFile),"-dsvg","-painters");

% PDF is a vector backup for editing/conversion workflows.
exportgraphics(fig,char(pdfFile), ...
    "ContentType","vector", ...
    "BackgroundColor","white");

% PNG is a compatibility fallback for PowerPoint or other slide software.
exportgraphics(fig,char(pngFile), ...
    "Resolution",pngResolution, ...
    "BackgroundColor","white");

files = struct("svg",svgFile,"pdf",pdfFile,"png",pngFile);
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

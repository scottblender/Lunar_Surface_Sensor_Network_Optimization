function plotInfo = plotMonteCarloConferenceFigure(userConfig)
% PLOTMONTECARLOCONFERENCEFIGURE Create one compact MC robustness figure.
%
% If a completed Monte Carlo robustness study is available, one 1x2 figure is
% produced: information-score robustness and coverage-score robustness. Each
% panel shows the local perturbation distribution versus network size with the
% nominal optimized score and the Monte Carlo mean overlaid.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");
addpath(scriptDirectory);
style = publicationPlotStyle();

config = struct();
config.resultsDirectory = resultsDirectory;
config.outputDirectory = fullfile(resultsDirectory,"production_figures");
config.monteCarloResultsFile = "";
config.exportResolution = 600;
config = mergeStruct(config,userConfig);
config.resultsDirectory = string(config.resultsDirectory);
config.outputDirectory = string(config.outputDirectory);
config.monteCarloResultsFile = string(config.monteCarloResultsFile);

resultsFile = resolveMonteCarloResults(config);
plotInfo = struct();
plotInfo.available = false;
plotInfo.resultsFile = resultsFile;
plotInfo.figure = gobjects(0);
plotInfo.outputFile = "";
plotInfo.summaryFile = "";

if strlength(resultsFile) == 0
    fprintf("\nNo completed Monte Carlo robustness study found; MC figure skipped.\n");
    return
end

data = load(resultsFile,"studyState");
assert(isfield(data,"studyState") && data.studyState.completed, ...
    "Selected Monte Carlo result is incomplete: %s",resultsFile);
studyState = data.studyState;
networkSizes = studyState.config.networkSizes;

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end
tableDirectory = fullfile(config.outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

fig = figure("Name","Monte Carlo robustness", ...
    "Color",style.backgroundColor,"Units","inches", ...
    "Position",[0.5 0.5 style.wideFigureWidthInches style.wideFigureHeightInches], ...
    "Renderer","painters");
layout = tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");

makePanel(nexttile(layout,1),studyState,"information","informationScore", ...
    "Information score",style);
makePanel(nexttile(layout,2),studyState,"coverage","coverageScore", ...
    "Coverage score",style);

sgtitle(layout,"Local Monte Carlo robustness", ...
    "FontName",style.fontName,"FontSize",style.labelFontSize, ...
    "FontWeight","bold","Color",style.textColor);

outputFile = fullfile(config.outputDirectory,"monte_carlo_robustness.eps");
exportgraphics(fig,outputFile,"ContentType","vector", ...
    "BackgroundColor",style.backgroundColor,"Colorspace","rgb");

summaryTable = buildSummaryTable(studyState);
summaryFile = fullfile(tableDirectory,"monte_carlo_summary.csv");
writetable(summaryTable,summaryFile);

plotInfo.available = true;
plotInfo.figure = fig;
plotInfo.outputFile = string(outputFile);
plotInfo.summaryFile = string(summaryFile);
plotInfo.summaryTable = summaryTable;
plotInfo.resultsFile = resultsFile;

fprintf("Monte Carlo robustness figure:\n  %s\n",outputFile);
end

function makePanel(ax,studyState,objectiveMode,metricField,yLabelText,style)
modeIndex = find(studyState.config.nominalObjectiveModes == objectiveMode,1);
assert(~isempty(modeIndex),"MC study does not contain %s objective.",objectiveMode);
networkSizes = studyState.config.networkSizes;
allValues = zeros(0,1);
groups = zeros(0,1);
nominal = nan(size(networkSizes));
means = nan(size(networkSizes));

for networkIndex = 1:numel(networkSizes)
    caseState = studyState.cases{modeIndex,networkIndex};
    values = caseState.rso.(metricField);
    allValues = [allValues;values(:)]; %#ok<AGROW>
    groups = [groups;repmat(networkSizes(networkIndex),numel(values),1)]; %#ok<AGROW>
    nominal(networkIndex) = caseState.nominal.rso.(metricField);
    means(networkIndex) = mean(values);
end

if objectiveMode == "information"
    boxColor = style.blueColor;
else
    boxColor = style.redColor;
end

hold(ax,"on");
boxHandle = boxchart(ax,groups,allValues, ...
    "BoxFaceColor",boxColor,"MarkerStyle",".","MarkerColor",style.grayColor);
nominalHandle = plot(ax,networkSizes,nominal,"o", ...
    "LineStyle","none","MarkerSize",11,"LineWidth",2.2, ...
    "MarkerFaceColor",style.backgroundColor,"MarkerEdgeColor",style.redColor);
meanHandle = plot(ax,networkSizes,means,"x", ...
    "LineStyle","none","MarkerSize",12,"LineWidth",2.4, ...
    "Color",style.textColor);

xlabel(ax,"Number of sensors, N_s");
ylabel(ax,yLabelText);
xticks(ax,networkSizes);
xlim(ax,[min(networkSizes)-0.6 max(networkSizes)+0.6]);
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 1.0;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.XLabel.FontSize = style.labelFontSize;
ax.YLabel.FontSize = style.labelFontSize;

lgd = legend(ax,[boxHandle nominalHandle meanHandle], ...
    ["MC samples","Nominal","MC mean"], ...
    "Location","northoutside","Orientation","horizontal","Box","off");
lgd.FontName = style.fontName;
lgd.FontSize = style.legendFontSize;
lgd.FontWeight = "bold";

valuesForLimits = [allValues;nominal(:);means(:)];
span = max(valuesForLimits)-min(valuesForLimits);
if span <= 0, span = max(1,0.05*max(abs(valuesForLimits))); end
ylim(ax,[min(valuesForLimits)-0.08*span max(valuesForLimits)+0.08*span]);
end

function summaryTable = buildSummaryTable(studyState)
networkSizes = studyState.config.networkSizes;
objectiveModes = studyState.config.nominalObjectiveModes;
numberOfRows = numel(networkSizes)*numel(objectiveModes);
objective = strings(numberOfRows,1);
networkSize = zeros(numberOfRows,1);
nominal = zeros(numberOfRows,1);
meanValue = zeros(numberOfRows,1);
stdValue = zeros(numberOfRows,1);
medianValue = zeros(numberOfRows,1);
minimumValue = zeros(numberOfRows,1);
maximumValue = zeros(numberOfRows,1);
row = 0;

for modeIndex = 1:numel(objectiveModes)
    objectiveMode = objectiveModes(modeIndex);
    metricField = objectiveMode + "Score";
    for networkIndex = 1:numel(networkSizes)
        row = row + 1;
        caseState = studyState.cases{modeIndex,networkIndex};
        values = caseState.rso.(metricField);
        objective(row) = objectiveMode;
        networkSize(row) = networkSizes(networkIndex);
        nominal(row) = caseState.nominal.rso.(metricField);
        meanValue(row) = mean(values);
        stdValue(row) = std(values);
        medianValue(row) = median(values);
        minimumValue(row) = min(values);
        maximumValue(row) = max(values);
    end
end

summaryTable = table(objective,networkSize,nominal,meanValue,stdValue, ...
    medianValue,minimumValue,maximumValue, ...
    'VariableNames',{'Objective','NetworkSize','Nominal','Mean','Std', ...
    'Median','Minimum','Maximum'});
end

function resultsFile = resolveMonteCarloResults(config)
resultsFile = "";
if strlength(config.monteCarloResultsFile) > 0
    if isfile(config.monteCarloResultsFile)
        resultsFile = config.monteCarloResultsFile;
    end
    return
end

files = dir(fullfile(config.resultsDirectory,"monte_carlo_robustness", ...
    "**","monte_carlo_results.mat"));
if isempty(files), return, end
[~,order] = sort([files.datenum],"descend");
files = files(order);
for fileIndex = 1:numel(files)
    candidate = string(fullfile(files(fileIndex).folder,files(fileIndex).name));
    try
        data = load(candidate,"studyState");
        if isfield(data,"studyState") && isfield(data.studyState,"completed") && ...
                data.studyState.completed
            resultsFile = candidate;
            return
        end
    catch
    end
end
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end

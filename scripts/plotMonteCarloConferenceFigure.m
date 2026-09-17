function plotInfo = plotMonteCarloConferenceFigure(userConfig)
% PLOTMONTECARLOCONFERENCEFIGURE Create separate MC robustness subfigures.
%
% A completed Monte Carlo robustness study produces one information-objective
% figure and one coverage-objective figure. They are intentionally separate so
% the manuscript can place them in a LaTeX subfigure environment without a
% crowded shared legend or compressed axes. The plotted quantity is the actual
% minimized objective J = -score, and the nominal optimized objective is shown
% as a short horizontal reference line for each network size.

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
config.networkSizes = [3 5 7 10];
config.objectiveModes = ["information","coverage"];
config = mergeStruct(config,userConfig);
config.resultsDirectory = string(config.resultsDirectory);
config.outputDirectory = string(config.outputDirectory);
config.monteCarloResultsFile = string(config.monteCarloResultsFile);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));

resultsFile = resolveMonteCarloResults(config);
plotInfo = struct();
plotInfo.available = false;
plotInfo.resultsFile = resultsFile;
plotInfo.information = struct();
plotInfo.coverage = struct();
plotInfo.summaryFile = "";

if strlength(resultsFile) == 0
    fprintf("\nNo completed full Monte Carlo robustness study found; MC figures skipped.\n");
    return
end

data = load(resultsFile,"studyState");
assert(isfield(data,"studyState") && data.studyState.completed, ...
    "Selected Monte Carlo result is incomplete: %s",resultsFile);
studyState = data.studyState;

if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end
tableDirectory = fullfile(config.outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

for objectiveMode = config.objectiveModes
    objectiveField = char(objectiveMode);
    metricField = objectiveMode + "Score";

    fig = figure("Name",sprintf("Monte Carlo robustness: %s",objectiveMode), ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[0.5 0.5 7.0 5.4],"Renderer","painters");
    ax = axes(fig);

    [boxHandle,nominalHandle] = makePanel( ...
        ax,studyState,objectiveMode,metricField,style);

    lgd = legend(ax,[boxHandle nominalHandle], ...
        ["MC perturbations","Nominal optimum"], ...
        "Location","northoutside","Orientation","horizontal","Box","off");
    lgd.FontName = style.fontName;
    lgd.FontSize = style.legendFontSize;
    lgd.FontWeight = "bold";

    outputFile = fullfile(config.outputDirectory, ...
        sprintf("monte_carlo_%s.eps",objectiveMode));
    exportPaintersEps(fig,outputFile,style);

    plotInfo.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end

summaryTable = buildSummaryTable(studyState);
summaryFile = fullfile(tableDirectory,"monte_carlo_summary.csv");
writetable(summaryTable,summaryFile);

plotInfo.available = true;
plotInfo.summaryFile = string(summaryFile);
plotInfo.summaryTable = summaryTable;
plotInfo.resultsFile = resultsFile;

fprintf("Monte Carlo robustness figures:\n");
for objectiveMode = config.objectiveModes
    fprintf("  %s\n",plotInfo.(char(objectiveMode)).outputFile);
end
end

function [boxHandle,nominalLegendHandle] = makePanel( ...
    ax,studyState,objectiveMode,metricField,style)
modeIndex = find(studyState.config.nominalObjectiveModes == objectiveMode,1);
assert(~isempty(modeIndex),"MC study does not contain %s objective.",objectiveMode);
networkSizes = double(studyState.config.networkSizes(:).');
allValues = zeros(0,1);
groups = zeros(0,1);
nominal = nan(size(networkSizes));

for networkIndex = 1:numel(networkSizes)
    caseState = studyState.cases{modeIndex,networkIndex};
    values = -double(caseState.rso.(metricField));
    allValues = [allValues;values(:)]; %#ok<AGROW>
    groups = [groups;repmat(networkSizes(networkIndex),numel(values),1)]; %#ok<AGROW>
    nominal(networkIndex) = -double(caseState.nominal.rso.(metricField));
end

if objectiveMode == "information"
    boxColor = style.blueColor;
else
    boxColor = style.redColor;
end

hold(ax,"on");
boxHandle = boxchart(ax,groups,allValues, ...
    "BoxFaceColor",boxColor, ...
    "MarkerStyle",".", ...
    "MarkerColor",style.grayColor, ...
    "LineWidth",1.25);

% Short horizontal references are visually distinct from the box median and
% directly identify the nominal optimum without adding a large marker.
nominalLegendHandle = gobjects(1);
halfWidth = 0.36;
for networkIndex = 1:numel(networkSizes)
    currentHandle = plot(ax, ...
        networkSizes(networkIndex) + [-halfWidth halfWidth], ...
        [nominal(networkIndex) nominal(networkIndex)], ...
        "-","Color",style.redColor,"LineWidth",3.0);
    if networkIndex == 1
        nominalLegendHandle = currentHandle;
    else
        currentHandle.HandleVisibility = "off";
    end
end

xlabel(ax,"Number of sensors, N_s");
ylabel(ax,"Objective, J");
xticks(ax,networkSizes);
xlim(ax,[min(networkSizes)-0.65 max(networkSizes)+0.65]);
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 1.0;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.XLabel.FontSize = style.labelFontSize;
ax.XLabel.FontWeight = "bold";
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";

valuesForLimits = [allValues;nominal(:)];
span = max(valuesForLimits)-min(valuesForLimits);
if span <= 0
    span = max(1,0.05*max(abs(valuesForLimits)));
end
ylim(ax,[min(valuesForLimits)-0.10*span max(valuesForLimits)+0.10*span]);
end

function summaryTable = buildSummaryTable(studyState)
networkSizes = studyState.config.networkSizes;
objectiveModes = studyState.config.nominalObjectiveModes;
numberOfRows = numel(networkSizes)*numel(objectiveModes);
objective = strings(numberOfRows,1);
networkSize = zeros(numberOfRows,1);
nominalObjective = zeros(numberOfRows,1);
meanObjective = zeros(numberOfRows,1);
stdObjective = zeros(numberOfRows,1);
medianObjective = zeros(numberOfRows,1);
minimumObjective = zeros(numberOfRows,1);
maximumObjective = zeros(numberOfRows,1);
row = 0;

for modeIndex = 1:numel(objectiveModes)
    objectiveMode = objectiveModes(modeIndex);
    metricField = objectiveMode + "Score";
    for networkIndex = 1:numel(networkSizes)
        row = row + 1;
        caseState = studyState.cases{modeIndex,networkIndex};
        values = -double(caseState.rso.(metricField));
        objective(row) = objectiveMode;
        networkSize(row) = networkSizes(networkIndex);
        nominalObjective(row) = -double(caseState.nominal.rso.(metricField));
        meanObjective(row) = mean(values);
        stdObjective(row) = std(values);
        medianObjective(row) = median(values);
        minimumObjective(row) = min(values);
        maximumObjective(row) = max(values);
    end
end

summaryTable = table(objective,networkSize,nominalObjective,meanObjective, ...
    stdObjective,medianObjective,minimumObjective,maximumObjective, ...
    'VariableNames',{'Objective','NetworkSize','NominalObjective', ...
    'MeanObjective','StdObjective','MedianObjective','MinimumObjective', ...
    'MaximumObjective'});
end

function resultsFile = resolveMonteCarloResults(config)
resultsFile = "";
if strlength(config.monteCarloResultsFile) > 0
    if isfile(config.monteCarloResultsFile)
        data = load(config.monteCarloResultsFile,"studyState");
        if isfield(data,"studyState") && isFullStudy(data.studyState,config)
            resultsFile = config.monteCarloResultsFile;
        end
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
        if isfield(data,"studyState") && isFullStudy(data.studyState,config)
            resultsFile = candidate;
            return
        end
    catch
    end
end
end

function tf = isFullStudy(studyState,config)
tf = isstruct(studyState) && isfield(studyState,"completed") && ...
    studyState.completed && isfield(studyState,"config") && ...
    isfield(studyState.config,"networkSizes") && ...
    isfield(studyState.config,"nominalObjectiveModes");
if ~tf, return, end
networkSizes = double(studyState.config.networkSizes(:).');
objectiveModes = lower(string(studyState.config.nominalObjectiveModes(:).'));
tf = all(ismember(config.networkSizes,networkSizes)) && ...
    all(ismember(config.objectiveModes,objectiveModes));
end

function exportPaintersEps(fig,outputFile,style)
fig.Renderer = "painters";
fig.Color = style.backgroundColor;
fig.InvertHardcopy = "off";
print(fig,char(outputFile),"-depsc","-painters");
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end

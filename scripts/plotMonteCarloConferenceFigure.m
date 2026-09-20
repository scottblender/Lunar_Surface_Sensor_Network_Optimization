function plotInfo = plotMonteCarloConferenceFigure(userConfig)
% PLOTMONTECARLOCONFERENCEFIGURE Create separate MC robustness figures.
%
% A completed Monte Carlo robustness study produces one standalone boxplot
% for every objective/network-size combination. This mirrors the separate-
% configuration presentation used in the space-based study and avoids placing
% multiple boxplots on the same MATLAB figure. The plotted quantity is the
% minimized objective J = -score, with the nominal optimized objective shown
% as a horizontal reference line.

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
config.optimizationCampaignDates = ["20260918","20260919"];
config = mergeStruct(config,userConfig);
config.resultsDirectory = string(config.resultsDirectory);
config.outputDirectory = string(config.outputDirectory);
config.monteCarloResultsFile = string(config.monteCarloResultsFile);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));
config.optimizationCampaignDates = string(config.optimizationCampaignDates(:));

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
    modeIndex = find(studyState.config.nominalObjectiveModes == objectiveMode,1);
    assert(~isempty(modeIndex),"MC study does not contain %s objective.",objectiveMode);

    for networkSize = config.networkSizes
        networkIndex = find(double(studyState.config.networkSizes(:).') == networkSize,1);
        assert(~isempty(networkIndex), ...
            "MC study does not contain N_s = %d.",networkSize);

        caseState = studyState.cases{modeIndex,networkIndex};
        values = -double(caseState.rso.(metricField));
        values = values(:);
        nominal = -double(caseState.nominal.rso.(metricField));

        fig = figure("Name",sprintf("Monte Carlo robustness: %s, N_s=%d", ...
            objectiveMode,networkSize), ...
            "Color",style.backgroundColor,"Units","inches", ...
            "Position",[0.5 0.5 7.0 4.8],"Renderer","opengl");
        fig.InvertHardcopy = "off";
        layout = tiledlayout(fig,1,1,"Padding","loose","TileSpacing","loose");
        ax = nexttile(layout);

        [boxHandle,nominalHandle] = makeSingleBoxplot( ...
            ax,values,nominal,networkSize,objectiveMode,style);

        lgd = legend(ax,[boxHandle nominalHandle], ...
            ["MC perturbations","Nominal optimum"], ...
            "Location","none","Orientation","horizontal", ...
            "NumColumns",2,"Box","off");
        lgd.FontName = style.fontName;
        lgd.FontSize = max(14,style.legendFontSize-2);
        lgd.FontWeight = "bold";
        lgd.Layout.Tile = "north";

        outputFile = fullfile(config.outputDirectory, ...
            sprintf("monte_carlo_%s_n%d.eps",objectiveMode,networkSize));
        exportManuscriptFigure(fig,string(outputFile),7.0,4.8);

        networkField = sprintf("n%d",networkSize);
        plotInfo.(objectiveField).(networkField) = struct( ...
            "figure",fig,"outputFile",string(outputFile), ...
            "networkSize",networkSize);
    end
end

summaryTable = buildSummaryTable(studyState);
summaryFile = fullfile(tableDirectory,"monte_carlo_summary.csv");
if ~isfield(config,"exportDiagnosticTables") || config.exportDiagnosticTables
    writetable(summaryTable,summaryFile);
else
    summaryFile = "";
end

plotInfo.available = true;
plotInfo.summaryFile = string(summaryFile);
plotInfo.summaryTable = summaryTable;
plotInfo.resultsFile = resultsFile;

fprintf("Monte Carlo robustness figures:\n");
for objectiveMode = config.objectiveModes
    objectiveField = char(objectiveMode);
    fields = fieldnames(plotInfo.(objectiveField));
    for fieldIndex = 1:numel(fields)
        fprintf("  %s\n",plotInfo.(objectiveField).(fields{fieldIndex}).outputFile);
    end
end
end

function [boxHandle,nominalHandle] = makeSingleBoxplot( ...
    ax,values,nominal,networkSize,objectiveMode,style)

if objectiveMode == "information"
    boxColor = style.blueColor;
else
    boxColor = style.redColor;
end

hold(ax,"on");
boxHandle = boxchart(ax,ones(size(values)),values, ...
    "BoxFaceColor",boxColor, ...
    "MarkerStyle",".", ...
    "MarkerColor",style.grayColor, ...
    "LineWidth",1.25);
nominalHandle = plot(ax,[0.68 1.32],[nominal nominal], ...
    "-","Color",style.redColor,"LineWidth",3.0);

xticks(ax,1);
xticklabels(ax,sprintf("N_s = %d",networkSize));
xlim(ax,[0.5 1.5]);
ylabel(ax,"Objective, J");
ax.FontName = style.fontName;
ax.FontSize = style.axisFontSize;
ax.FontWeight = "bold";
ax.LineWidth = 1.0;
ax.TickDir = "out";
ax.Box = "on";
ax.XGrid = "off";
ax.YGrid = "off";
ax.YLabel.FontSize = style.labelFontSize;
ax.YLabel.FontWeight = "bold";

valuesForLimits = [values(:);nominal];
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

if tf && ~isempty(config.optimizationCampaignDates)
    if ~isfield(studyState.config,"optimizationCampaignDates")
        tf = false;
        return
    end
    sourceDates = string(studyState.config.optimizationCampaignDates(:));
    tf = isequal(sort(sourceDates),sort(config.optimizationCampaignDates));
end
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    output.(fields{fieldIndex}) = override.(fields{fieldIndex});
end
end
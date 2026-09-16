function plotInfo = plotMonteCarloRobustness(resultsFile,outputDirectory)
% PLOTMONTECARLOROBUSTNESS Plot local sensor-placement robustness results.
%
% The main-paper outputs are intentionally limited to two box-and-whisker
% figures: RSO information performance for information-optimized networks and
% RSO coverage performance for coverage-optimized networks. If operational
% spacecraft are enabled, the corresponding two figures are written to a
% supplemental subdirectory. Nominal optimized performance and the Monte
% Carlo mean are overlaid on every boxplot.
%
% By default, the Monte Carlo figures are written beside the rest of the
% production conference figures under results/production_figures. This keeps
% the final manuscript products in one location while the raw MC MAT file
% remains in its timestamped study directory.

arguments
    resultsFile (1,1) string
    outputDirectory (1,1) string = ""
end

assert(isfile(resultsFile),"Monte Carlo results file was not found: %s",resultsFile);
data = load(resultsFile,"studyState");
assert(isfield(data,"studyState"),"Result file does not contain studyState.");
studyState = data.studyState;
assert(studyState.completed,"The supplied Monte Carlo study is incomplete.");

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
addpath(scriptDirectory);
style = publicationPlotStyle();

if strlength(outputDirectory) == 0
    outputDirectory = string(fullfile(projectRoot,"results","production_figures"));
end
figuresDirectory = outputDirectory;
supplementalDirectory = fullfile(figuresDirectory,"supplemental");
tableDirectory = fullfile(figuresDirectory,"tables");
if ~isfolder(figuresDirectory), mkdir(figuresDirectory); end
if ~isfolder(supplementalDirectory), mkdir(supplementalDirectory); end
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

%% Main-paper Monte Carlo figures
infoFigure = plotMetricBoxplot( ...
    studyState,"information","rso","informationScore", ...
    "Information score","monte_carlo_rso_information_boxplot", ...
    figuresDirectory,style);
coverageFigure = plotMetricBoxplot( ...
    studyState,"coverage","rso","coverageScore", ...
    "Coverage score","monte_carlo_rso_coverage_boxplot", ...
    figuresDirectory,style);

%% Supplemental operational-spacecraft figures
operationalInfoFigure = "";
operationalCoverageFigure = "";
if studyState.config.includeOperationalSpacecraft
    operationalInfoFigure = plotMetricBoxplot( ...
        studyState,"information","operational","informationScore", ...
        "Information score","monte_carlo_operational_information_boxplot", ...
        supplementalDirectory,style);
    operationalCoverageFigure = plotMetricBoxplot( ...
        studyState,"coverage","operational","coverageScore", ...
        "Coverage score","monte_carlo_operational_coverage_boxplot", ...
        supplementalDirectory,style);
end

%% Summary statistics
summaryTable = buildSummaryTable(studyState);
summaryFile = fullfile(tableDirectory,"monte_carlo_summary.csv");
writetable(summaryTable,summaryFile);

fprintf("\n============================================================\n");
fprintf("Monte Carlo robustness summary\n");
fprintf("============================================================\n");
disp(summaryTable);
fprintf("Main-paper MC figures:\n");
fprintf("  %s\n",infoFigure);
fprintf("  %s\n",coverageFigure);
if studyState.config.includeOperationalSpacecraft
    fprintf("Supplemental operational-spacecraft MC figures:\n");
    fprintf("  %s\n",operationalInfoFigure);
    fprintf("  %s\n",operationalCoverageFigure);
end
fprintf("Summary CSV:\n  %s\n",summaryFile);

plotInfo = struct();
plotInfo.resultsFile = resultsFile;
plotInfo.figuresDirectory = string(figuresDirectory);
plotInfo.informationFigure = string(infoFigure);
plotInfo.coverageFigure = string(coverageFigure);
plotInfo.operationalInformationFigure = string(operationalInfoFigure);
plotInfo.operationalCoverageFigure = string(operationalCoverageFigure);
plotInfo.summaryTable = summaryTable;
plotInfo.summaryFile = string(summaryFile);

end

%% ------------------------------------------------------------------------
function epsFile = plotMetricBoxplot( ...
    studyState,objectiveMode,targetSet,metricField,yLabelText,fileStem, ...
    figuresDirectory,style)

modeIndex = find(studyState.config.nominalObjectiveModes == objectiveMode,1);
assert(~isempty(modeIndex),"Requested objective mode was not included in the study.");
networkSizes = studyState.config.networkSizes;
allValues = zeros(0,1);
groupValues = zeros(0,1);
nominalValues = nan(size(networkSizes));
meanValues = nan(size(networkSizes));

for networkIndex = 1:numel(networkSizes)
    caseState = studyState.cases{modeIndex,networkIndex};
    currentValues = caseState.(targetSet).(metricField);
    allValues = [allValues; currentValues(:)]; %#ok<AGROW>
    groupValues = [groupValues; repmat(networkSizes(networkIndex), ...
        numel(currentValues),1)]; %#ok<AGROW>
    nominalValues(networkIndex) = caseState.nominal.(targetSet).(metricField);
    meanValues(networkIndex) = mean(currentValues);
end

if objectiveMode == "information"
    boxColor = style.blueColor;
else
    boxColor = style.redColor;
end

widthIn = style.exportWidthInches;
heightIn = style.exportHeightInches;
fig = figure("Color",style.backgroundColor,"Units","inches", ...
    "Position",[1 1 widthIn heightIn],"PaperUnits","inches", ...
    "PaperSize",[widthIn heightIn],"PaperPosition",[0 0 widthIn heightIn], ...
    "PaperPositionMode","manual","Renderer","painters", ...
    "InvertHardcopy","off");
ax = axes(fig,"Units","normalized","Position",[0.16 0.18 0.80 0.70]);
hold(ax,"on");
box(ax,"off");
grid(ax,"off");

boxHandle = boxchart(ax,groupValues,allValues, ...
    "BoxFaceColor",boxColor,"MarkerStyle",".","MarkerColor",style.grayColor);
nominalHandle = plot(ax,networkSizes,nominalValues,"o", ...
    "LineStyle","none","MarkerSize",11,"LineWidth",2.0, ...
    "MarkerFaceColor",style.backgroundColor,"MarkerEdgeColor",style.redColor);
meanHandle = plot(ax,networkSizes,meanValues,"x", ...
    "LineStyle","none","MarkerSize",12,"LineWidth",2.2, ...
    "Color",style.textColor);

xlabel(ax,"Number of sensors, N_s","FontWeight","bold");
ylabel(ax,yLabelText,"FontWeight","bold");
xticks(ax,networkSizes);
xlim(ax,[min(networkSizes)-0.7 max(networkSizes)+0.7]);
set(ax,"FontName",style.fontName,"FontSize",style.axisFontSize, ...
    "FontWeight","bold","LineWidth",1.1,"TickDir","out", ...
    "XGrid","off","YGrid","off","Box","off","Layer","top");
ax.XLabel.FontSize = style.labelFontSize;
ax.YLabel.FontSize = style.labelFontSize;

lgd = legend(ax,[boxHandle nominalHandle meanHandle], ...
    ["Monte Carlo samples","Nominal optimized","Monte Carlo mean"], ...
    "Location","northoutside","Orientation","horizontal", ...
    "NumColumns",3,"Box","off");
lgd.FontName = style.fontName;
lgd.FontSize = style.legendFontSize;
lgd.FontWeight = "bold";

plotValues = [allValues;nominalValues(:);meanValues(:)];
plotValues = plotValues(isfinite(plotValues));
span = max(plotValues)-min(plotValues);
if span <= 0
    span = max(1,0.05*max(abs(plotValues)));
end
padding = 0.10*span;
ylim(ax,[min(plotValues)-padding max(plotValues)+padding]);

% Keep the larger manuscript font from producing too many y tick labels.
limits = ylim(ax);
ax.YTick = linspace(limits(1),limits(2),5);

% Use a little more whitespace around the large tick labels before export.
ax.LooseInset = max(ax.TightInset,[0.03 0.03 0.03 0.03]);

drawnow;
epsFile = fullfile(figuresDirectory,fileStem + ".eps");
pngFile = fullfile(figuresDirectory,fileStem + ".png");
print(fig,epsFile,"-depsc2","-painters","-r600","-loose");
exportgraphics(fig,pngFile,"Resolution",600, ...
    "BackgroundColor",style.backgroundColor);
close(fig);
end

%% ------------------------------------------------------------------------
function summaryTable = buildSummaryTable(studyState)
networkSizes = studyState.config.networkSizes;
objectiveModes = studyState.config.nominalObjectiveModes;
numberOfRows = numel(networkSizes)*numel(objectiveModes)* ...
    (1 + double(studyState.config.includeOperationalSpacecraft));

population = strings(numberOfRows,1);
objective = strings(numberOfRows,1);
networkSize = zeros(numberOfRows,1);
nominalValue = zeros(numberOfRows,1);
meanValue = zeros(numberOfRows,1);
stdValue = zeros(numberOfRows,1);
medianValue = zeros(numberOfRows,1);
p05 = zeros(numberOfRows,1);
p25 = zeros(numberOfRows,1);
p75 = zeros(numberOfRows,1);
p95 = zeros(numberOfRows,1);
minimumValue = zeros(numberOfRows,1);
maximumValue = zeros(numberOfRows,1);

row = 0;
for modeIndex = 1:numel(objectiveModes)
    objectiveMode = objectiveModes(modeIndex);
    metricField = objectiveMode + "Score";
    targetSets = "rso";
    if studyState.config.includeOperationalSpacecraft
        targetSets = ["rso","operational"];
    end

    for targetSet = targetSets
        for networkIndex = 1:numel(networkSizes)
            row = row + 1;
            caseState = studyState.cases{modeIndex,networkIndex};
            values = caseState.(targetSet).(metricField);
            q = prctile(values,[5 25 50 75 95]);

            population(row) = targetSet;
            objective(row) = objectiveMode;
            networkSize(row) = networkSizes(networkIndex);
            nominalValue(row) = caseState.nominal.(targetSet).(metricField);
            meanValue(row) = mean(values);
            stdValue(row) = std(values);
            medianValue(row) = q(3);
            p05(row) = q(1);
            p25(row) = q(2);
            p75(row) = q(4);
            p95(row) = q(5);
            minimumValue(row) = min(values);
            maximumValue(row) = max(values);
        end
    end
end

summaryTable = table(population,objective,networkSize,nominalValue, ...
    meanValue,stdValue,medianValue,p05,p25,p75,p95,minimumValue,maximumValue, ...
    'VariableNames',{'Population','Objective','NetworkSize','Nominal', ...
    'Mean','Std','Median','P05','P25','P75','P95','Minimum','Maximum'});
end

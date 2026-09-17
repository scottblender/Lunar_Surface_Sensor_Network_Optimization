function plotInfo = plotMonteCarloRobustness(resultsFile,outputDirectory)
% PLOTMONTECARLOROBUSTNESS Plot local sensor-placement robustness results.
%
% Each objective/network-size combination is exported as its own standalone
% box-and-whisker figure. Operational-spacecraft figures, when enabled, use the
% same one-network-per-figure convention in the supplemental directory.

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

networkSizes = double(studyState.config.networkSizes(:).');

%% Main-paper Monte Carlo figures
rsoInformationFigures = strings(numel(networkSizes),1);
rsoCoverageFigures = strings(numel(networkSizes),1);
for networkIndex = 1:numel(networkSizes)
    networkSize = networkSizes(networkIndex);
    rsoInformationFigures(networkIndex) = plotMetricBoxplot( ...
        studyState,"information","rso","informationScore",networkIndex, ...
        "Information score",sprintf("monte_carlo_rso_information_n%d",networkSize), ...
        figuresDirectory,style);
    rsoCoverageFigures(networkIndex) = plotMetricBoxplot( ...
        studyState,"coverage","rso","coverageScore",networkIndex, ...
        "Coverage score",sprintf("monte_carlo_rso_coverage_n%d",networkSize), ...
        figuresDirectory,style);
end

%% Supplemental operational-spacecraft figures
operationalInformationFigures = strings(0,1);
operationalCoverageFigures = strings(0,1);
if studyState.config.includeOperationalSpacecraft
    operationalInformationFigures = strings(numel(networkSizes),1);
    operationalCoverageFigures = strings(numel(networkSizes),1);
    for networkIndex = 1:numel(networkSizes)
        networkSize = networkSizes(networkIndex);
        operationalInformationFigures(networkIndex) = plotMetricBoxplot( ...
            studyState,"information","operational","informationScore",networkIndex, ...
            "Information score",sprintf("monte_carlo_operational_information_n%d",networkSize), ...
            supplementalDirectory,style);
        operationalCoverageFigures(networkIndex) = plotMetricBoxplot( ...
            studyState,"coverage","operational","coverageScore",networkIndex, ...
            "Coverage score",sprintf("monte_carlo_operational_coverage_n%d",networkSize), ...
            supplementalDirectory,style);
    end
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
allMainFiles = [rsoInformationFigures;rsoCoverageFigures];
for fileIndex = 1:numel(allMainFiles)
    fprintf("  %s\n",allMainFiles(fileIndex));
end
if studyState.config.includeOperationalSpacecraft
    fprintf("Supplemental operational-spacecraft MC figures:\n");
    allSupplementalFiles = [operationalInformationFigures;operationalCoverageFigures];
    for fileIndex = 1:numel(allSupplementalFiles)
        fprintf("  %s\n",allSupplementalFiles(fileIndex));
    end
end
fprintf("Summary CSV:\n  %s\n",summaryFile);

plotInfo = struct();
plotInfo.resultsFile = resultsFile;
plotInfo.figuresDirectory = string(figuresDirectory);
plotInfo.informationFigures = rsoInformationFigures;
plotInfo.coverageFigures = rsoCoverageFigures;
plotInfo.operationalInformationFigures = operationalInformationFigures;
plotInfo.operationalCoverageFigures = operationalCoverageFigures;
plotInfo.summaryTable = summaryTable;
plotInfo.summaryFile = string(summaryFile);

end

%% ------------------------------------------------------------------------
function epsFile = plotMetricBoxplot( ...
    studyState,objectiveMode,targetSet,metricField,networkIndex,yLabelText, ...
    fileStem,figuresDirectory,style)

modeIndex = find(studyState.config.nominalObjectiveModes == objectiveMode,1);
assert(~isempty(modeIndex),"Requested objective mode was not included in the study.");
networkSize = studyState.config.networkSizes(networkIndex);
caseState = studyState.cases{modeIndex,networkIndex};
values = double(caseState.(targetSet).(metricField));
values = values(:);
nominalValue = double(caseState.nominal.(targetSet).(metricField));
meanValue = mean(values);
fileStem = string(fileStem);

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
    "PaperPositionMode","manual","InvertHardcopy","off", ...
    "Renderer","opengl");
ax = axes(fig,"Units","normalized","Position",[0.16 0.18 0.80 0.70]);
hold(ax,"on");
box(ax,"off");
grid(ax,"off");

boxHandle = boxchart(ax,ones(size(values)),values, ...
    "BoxFaceColor",boxColor,"MarkerStyle",".","MarkerColor",style.grayColor);
nominalHandle = plot(ax,[0.68 1.32],[nominalValue nominalValue],"-", ...
    "LineWidth",3.0,"Color",style.redColor);
meanHandle = plot(ax,1,meanValue,"x", ...
    "LineStyle","none","MarkerSize",12,"LineWidth",2.2, ...
    "Color",style.textColor);

xticks(ax,1);
xticklabels(ax,sprintf("N_s = %d",networkSize));
xlim(ax,[0.5 1.5]);
ylabel(ax,yLabelText,"FontWeight","bold");
set(ax,"FontName",style.fontName,"FontSize",style.axisFontSize, ...
    "FontWeight","bold","LineWidth",1.1,"TickDir","out", ...
    "XGrid","off","YGrid","off","Box","off","Layer","top");
ax.YLabel.FontSize = style.labelFontSize;

lgd = legend(ax,[boxHandle nominalHandle meanHandle], ...
    ["Monte Carlo samples","Nominal optimized","Monte Carlo mean"], ...
    "Location","northoutside","Orientation","horizontal", ...
    "NumColumns",3,"Box","off");
lgd.FontName = style.fontName;
lgd.FontSize = style.legendFontSize;
lgd.FontWeight = "bold";

plotValues = [values;nominalValue;meanValue];
plotValues = plotValues(isfinite(plotValues));
span = max(plotValues)-min(plotValues);
if span <= 0
    span = max(1,0.05*max(abs(plotValues)));
end
padding = 0.10*span;
ylim(ax,[min(plotValues)-padding max(plotValues)+padding]);
limits = ylim(ax);
ax.YTick = linspace(limits(1),limits(2),5);
ax.LooseInset = max(ax.TightInset,[0.03 0.03 0.03 0.03]);

drawnow;
epsFile = string(fullfile(figuresDirectory,fileStem + ".eps"));
pngFile = string(fullfile(figuresDirectory,fileStem + ".png"));
print(fig,char(epsFile),"-depsc","-opengl","-r600");
exportgraphics(fig,char(pngFile),"Resolution",600, ...
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

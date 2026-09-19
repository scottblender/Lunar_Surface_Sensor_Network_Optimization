function plotInfo = plotProductionConvergence(campaign,userConfig)
% PLOTPRODUCTIONCONVERGENCE Generate the two manuscript convergence figures.

arguments
    campaign (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = campaign.configuration;
if isfield(userConfig,"outputDirectory")
    outputDirectory = string(userConfig.outputDirectory);
else
    outputDirectory = string(campaign.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

networkColors = [style.blueColor;style.orangeColor;style.greenColor;style.magentaColor];
assert(numel(config.networkSizes) <= size(networkColors,1), ...
    "Add plotting colors for additional network sizes.");

plotInfo = struct();
for objectiveIndex = 1:numel(config.objectiveModes)
    objectiveMode = config.objectiveModes(objectiveIndex);
    objectiveField = char(objectiveMode);

    fig = figure("Name",objectiveMode + " convergence", ...
        "Color",style.backgroundColor,"Units","inches", ...
        "Position",[1 1 7.0 4.5],"Renderer","opengl");
    ax = axes(fig,"Position",[0.13 0.17 0.57 0.74]);
    hold(ax,"on");

    handles = gobjects(numel(config.networkSizes),1);
    labels = strings(numel(config.networkSizes),1);

    for networkIndex = 1:numel(config.networkSizes)
        studyState = campaign.studies{networkIndex,objectiveIndex};
        [fe,meanHistory,stdHistory] = aggregateConvergence( ...
            studyState,config.numberOfRuns);
        c = networkColors(networkIndex,:);

        fill(ax,[fe;flipud(fe)], ...
            [meanHistory-stdHistory;flipud(meanHistory+stdHistory)], ...
            c,"FaceAlpha",0.13,"EdgeColor","none","HandleVisibility","off");
        handles(networkIndex) = plot(ax,fe,meanHistory, ...
            "Color",c,"LineWidth",2.3);
        labels(networkIndex) = sprintf("N_s = %d",config.networkSizes(networkIndex));
    end

    xlabel(ax,"Function evaluations");
    ylabel(ax,"Incumbent objective, J");
    xlim(ax,[config.populationSize config.functionEvaluationBudget]);
    applyAxesStyle(ax,style);
    lgd = legend(ax,handles,labels,"Location","northeastoutside","Interpreter","tex");
    lgd.FontName = style.fontName;
    lgd.FontSize = style.legendFontSize;
    lgd.FontWeight = "bold";
    lgd.Box = "on";

    outputFile = fullfile(outputDirectory, ...
        sprintf("convergence_%s.eps",objectiveMode));
    exportManuscriptFigure(fig,string(outputFile),7.0,4.5);

    plotInfo.(objectiveField) = struct( ...
        "figure",fig,"outputFile",string(outputFile));
end
end

function [fe,meanHistory,stdHistory] = aggregateConvergence(studyState,numberOfRuns)
assert(numel(studyState.runStates) == numberOfRuns, ...
    "Study contains an unexpected number of run states.");
fe = double(studyState.runStates{1}.history.fe(:));
allHistories = zeros(numel(fe),numberOfRuns);
for runIndex = 1:numberOfRuns
    runState = studyState.runStates{runIndex};
    currentFe = double(runState.history.fe(:));
    currentBest = double(runState.history.bestJ(:));
    assert(isequal(currentFe,fe), ...
        "Run %d uses a different FE history grid.",runIndex);
    allHistories(:,runIndex) = currentBest;
end
meanHistory = mean(allHistories,2);
stdHistory = std(allHistories,0,2);
end

function applyAxesStyle(ax,style)
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
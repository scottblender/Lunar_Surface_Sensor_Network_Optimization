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
        "Position",[1 1 7.0 5.8],"Renderer","opengl");
    layout = tiledlayout(fig,1,1,"Padding","compact","TileSpacing","compact");
    ax = nexttile(layout);
    hold(ax,"on");

    handles = gobjects(numel(config.networkSizes),1);
    labels = strings(numel(config.networkSizes),1);

    for networkIndex = 1:numel(config.networkSizes)
        studyState = campaign.studies{networkIndex,objectiveIndex};
        [fe,meanHistory,stdHistory] = aggregateConvergence( ...
            studyState,config.numberOfRuns);
        c = networkColors(networkIndex,:);
        % EPS does not preserve transparency as reliably as MATLAB's on-screen
        % renderer. Use an opaque lightened version of the series color for
        % the +/-1 sigma band so it remains visible after EPS/PDF conversion.
        bandColor = 0.45*c + 0.55*[1 1 1];

        fill(ax,[fe;flipud(fe)], ...
            [meanHistory-stdHistory;flipud(meanHistory+stdHistory)], ...
            bandColor,"FaceAlpha",1.0,"EdgeColor","none", ...
            "HandleVisibility","off");

        % Draw the +/-1 sigma boundaries explicitly so overlapping uncertainty
        % bands remain distinguishable after EPS export.
        plot(ax,fe,meanHistory-stdHistory, ...
            "--","Color",c,"LineWidth",1.0,"HandleVisibility","off");
        plot(ax,fe,meanHistory+stdHistory, ...
            "--","Color",c,"LineWidth",1.0,"HandleVisibility","off");

        handles(networkIndex) = plot(ax,fe,meanHistory, ...
            "Color",c,"LineWidth",2.3);
        labels(networkIndex) = sprintf("N_s = %d",config.networkSizes(networkIndex));
    end

    xlabel(ax,"Function evaluations");
    ylabel(ax,{'Mean best-so-far','objective, J'});
    xlim(ax,[config.populationSize config.functionEvaluationBudget]);
    if objectiveMode == "coverage"
        ylim(ax,[-405 -335]);
    end
    applyAxesStyle(ax,style);
    % Sparse FE ticks remain legible at the half-page manuscript width.
    xticks(ax,config.functionEvaluationBudget*(1:3)/3);
    xtickformat(ax,"%.0f");
    lgd = legend(ax,handles,labels, ...
        "Location","none","Orientation","horizontal", ...
        "NumColumns",2,"Interpreter","tex","Box","off");
    lgd.FontName = style.fontName;
    lgd.FontSize = max(14,style.legendFontSize-2);
    lgd.FontWeight = "bold";
    lgd.Layout.Tile = "north";

    outputFile = fullfile(outputDirectory, ...
        sprintf("convergence_%s.eps",objectiveMode));
    applyManuscriptTypography(fig,string(outputFile),7.0);
    layout.Units = "normalized";
    layout.OuterPosition = [0.015 0.025 0.97 0.955];
    setappdata(fig,"ManuscriptTypographyFinalized",true);
    exportManuscriptFigure(fig,string(outputFile),7.0,5.8);

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
        sprintf('Run %d uses a different FE history grid.',runIndex));
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
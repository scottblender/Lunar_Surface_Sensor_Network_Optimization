function result = generateDomainComparisonProducts(fullCampaign,userConfig)
% GENERATEDOMAINCOMPARISONPRODUCTS Compare full and restricted design domains.
%
% Required userConfig fields:
%   restrictedResultsDirectory
%   restrictedDatabaseFile
%
% The restricted campaign must use the same network sizes, objectives, FE
% budget, population size, number of runs, and seeds as the full campaign.

arguments
    fullCampaign (1,1) struct
    userConfig (1,1) struct
end

assert(isfield(userConfig,"restrictedResultsDirectory") && ...
    strlength(string(userConfig.restrictedResultsDirectory))>0, ...
    "Set userConfig.restrictedResultsDirectory for the south-polar campaign.");
assert(isfield(userConfig,"restrictedDatabaseFile") && ...
    strlength(string(userConfig.restrictedDatabaseFile))>0, ...
    "Set userConfig.restrictedDatabaseFile for the south-polar campaign.");

restrictedConfig=fullCampaign.configuration;
restrictedConfig.resultsDirectory=string(userConfig.restrictedResultsDirectory);
restrictedConfig.databaseFile=string(userConfig.restrictedDatabaseFile);
restrictedConfig.outputDirectory=string(fullCampaign.outputDirectory);
restrictedCampaign=loadProductionCampaign(restrictedConfig);

assert(isequal(fullCampaign.configuration.networkSizes, ...
    restrictedCampaign.configuration.networkSizes));
assert(isequal(fullCampaign.configuration.objectiveModes, ...
    restrictedCampaign.configuration.objectiveModes));

style=publicationPlotStyle();
networkSizes=fullCampaign.configuration.networkSizes;
objectiveModes=fullCampaign.configuration.objectiveModes;
outputDirectory=string(fullCampaign.outputDirectory);
tableDirectory=fullfile(outputDirectory,"tables");
if ~isfolder(tableDirectory), mkdir(tableDirectory); end

fig=figure("Name","Design-domain comparison","Color",style.backgroundColor, ...
    "Units","inches","Position",[1 1 10 5.6],"Renderer","opengl");
layout=tiledlayout(fig,1,numel(objectiveModes),"TileSpacing","compact","Padding","compact");

rows=cell(numel(networkSizes)*numel(objectiveModes),1);
row=0;
for objectiveIndex=1:numel(objectiveModes)
    ax=nexttile(layout,objectiveIndex);
    hold(ax,"on");

    fullValues=zeros(numel(networkSizes),1);
    restrictedValues=zeros(numel(networkSizes),1);

    for networkIndex=1:numel(networkSizes)
        fullStudy=fullCampaign.studies{networkIndex,objectiveIndex};
        restrictedStudy=restrictedCampaign.studies{networkIndex,objectiveIndex};
        fullValues(networkIndex)=fullStudy.overallBestObjective;
        restrictedValues(networkIndex)=restrictedStudy.overallBestObjective;

        row=row+1;
        rows{row}=table(objectiveModes(objectiveIndex),networkSizes(networkIndex), ...
            fullStudy.overallBestObjective,restrictedStudy.overallBestObjective, ...
            'VariableNames',{'Objective','NetworkSize','SouthernHemisphereValue', ...
            'SouthPolarValue'});
    end

    plot(ax,networkSizes,fullValues,"-o","LineWidth",2.2, ...
        "MarkerSize",8,"DisplayName","Southern hemisphere");
    plot(ax,networkSizes,restrictedValues,"--s","LineWidth",2.2, ...
        "MarkerSize",8,"DisplayName","South-polar restriction");

    xlabel(ax,"Number of sensors, N_s");
    ylabel(ax,"Best objective, J");
    title(ax,objectiveTitle(objectiveModes(objectiveIndex)), ...
        "FontWeight","bold","FontSize",style.labelFontSize);
    ax.FontName=style.fontName;
    ax.FontSize=style.axisFontSize;
    ax.FontWeight="bold";
    ax.LineWidth=0.9;
    ax.TickDir="out";
    ax.XGrid="on";
    ax.YGrid="on";
    ax.XTick=networkSizes;
    if objectiveIndex==1
        lgd=legend(ax,"Location","best");
        lgd.FontName=style.fontName;
        lgd.FontSize=style.legendFontSize;
        lgd.FontWeight="bold";
    end
end

outputFile=fullfile(outputDirectory,"domain_comparison.eps");
exportManuscriptFigure(fig,string(outputFile),10,5.6);

summaryTable=vertcat(rows{:});
tableFile=fullfile(tableDirectory,"domain_comparison.csv");
writetable(summaryTable,tableFile);

result=struct("figure",fig,"outputFile",string(outputFile), ...
    "table",summaryTable,"tableFile",string(tableFile));
end

function t=objectiveTitle(mode)
if mode=="information", t="Information objective"; else, t="Coverage objective"; end
end

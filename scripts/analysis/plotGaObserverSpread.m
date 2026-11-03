function report=plotGaObserverSpread(studyDirectory,independentRuns,options)
% PLOTGAOBSERVERSPREAD - Box-and-whisker distances by observer and FE budget.
% Reuses the polar plot's fixed reference and permutation-invariant matching.
% Boxes: median and quartiles; whiskers: 1.5 IQR; outliers remain visible.
arguments
    studyDirectory (1,1) string
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,:) double = []
end
report=loadGaObserverLocations(studyDirectory,independentRuns,options.RequestedFE);
locations=report.locations; budgets=report.requestedFE;
fig=figure("Name","Observer location spread versus FE","Color","white", ...
    "Units","inches","Position",[0.5 0.5 13 4.8],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
limit=max(1,1.05*max(locations.DistanceFromBestKm));
for observer=1:3
    ax=nexttile(layout);
    selected=locations.Observer==observer;
    [~,group]=ismember(locations.RequestedFE(selected),budgets);
    boxchart(ax,group,locations.DistanceFromBestKm(selected), ...
        "BoxFaceColor",[0.05 0.35 0.65],"MarkerColor",[0.05 0.35 0.65],"MarkerStyle",".");
    title(ax,sprintf("Observer %d",observer),"FontSize",12);
    xlabel(ax,"Requested FE per run"); ylabel(ax,"Distance from best-run site (km)");
    xticks(ax,1:numel(budgets)); xticklabels(ax,string(budgets));
    xlim(ax,[0.5 numel(budgets)+0.5]); ylim(ax,[0 limit]); grid(ax,"on");
    ax.FontSize=10;
end
title(layout,sprintf("%d runs/FE | Reference: seed %d, FE %d, J = %.6f", ...
    report.independentRuns,report.referenceSeed,report.referenceRequestedFE,report.referenceObjective), ...
    "FontSize",12);
out=report.outputDirectory; if ~isfolder(out), mkdir(out); end
report.pngFile=fullfile(out,"observer_spread_vs_fe.png");
report.pdfFile=fullfile(out,"observer_spread_vs_fe.pdf");
report.locationsCsvFile=fullfile(out,"observer_distances_vs_fe.csv");
exportgraphics(fig,report.pngFile,"Resolution",220);
exportgraphics(fig,report.pdfFile,"ContentType","vector");
writetable(locations,report.locationsCsvFile);
report.whiskerRule="furthest observed values within 1.5 IQR of the quartiles; remaining values plotted as outliers";
fprintf("Observer-distance boxplots saved to:\n  %s\n",report.pngFile);
end

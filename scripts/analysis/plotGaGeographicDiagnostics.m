function plotGaGeographicDiagnostics(report)
% PLOTGAGEOGRAPHICDIAGNOSTICS - No reference observers or artificial identities.
out=report.outputDirectory; colors=lines(3);
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 13 4.5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
for side=1:3
    ax=nexttile(layout); t=report.shapeSummary(report.shapeSummary.SortedSide==side,:);
    fill(ax,[t.RequestedFE;flipud(t.RequestedFE)],[t.P10Deg;flipud(t.P90Deg)],colors(side,:), ...
        'FaceAlpha',.15,'EdgeColor','none'); hold(ax,"on");
    plot(ax,t.RequestedFE,t.MedianDeg,'-o','Color',colors(side,:),'LineWidth',1.5);
    xlabel(ax,"Requested FE per run"); ylabel(ax,"Inter-sensor separation (deg)");
    title(ax,"Sorted side "+side+": median and run P10-P90"); grid(ax,"on"); xticks(ax,report.budgets);
end
title(layout,"Network shape ignores labels, geographic orientation and reflection");
exportPair(fig,out,"network_shape_vs_fe"); clear cleanup
if ~isempty(report.movement)
    fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 12 5]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
    ax=nexttile(layout); hold(ax,"on"); intervals=unique([report.movement.FromFE report.movement.ToFE],'rows');
    for k=1:height(intervals)
        t=report.movement(report.movement.FromFE==intervals(k,1),:);
        scatter(ax,t.MeanMatchedMovementKm,t.ObjectiveImprovement,22,'filled', ...
            'DisplayName',sprintf('%d to %d FE',intervals(k,:)));
    end
    xlabel(ax,"Paired-seed mean matched location movement (km)"); ylabel(ax,"Objective improvement (positive is better)");
    grid(ax,"on"); legend(ax,'Location','best');
    ax=nexttile(layout); s=report.movementSummary;
    labels=string(s.FromFE)+" to "+string(s.ToFE);
    bar(ax,categorical(labels,labels),100*[s.UnchangedNetworks s.ChangedNetworks]./s.IndependentSeeds,'stacked');
    ylabel(ax,"Independent seeds (%)"); ylim(ax,[0 100]); xlabel(ax,"FE interval");
    legend(ax,["Unchanged network","Changed network"],'Location','best'); grid(ax,"on");
    title(layout,"Do runs stagnate, adjust locally, or jump between configurations?");
    exportPair(fig,out,"paired_movement_vs_gain"); clear cleanup
end
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 13 4.5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
metrics=["MeanMatchedKm","BottleneckKm","MaxShapeSideChangeDeg"];
labels=["Mean matched distance (km)","Worst-sensor matched distance (km)","Largest sorted-side difference (deg)"];
for k=1:3
    ax=nexttile(layout); t=report.spread(report.spread.Metric==metrics(k),:);
    fill(ax,[t.RequestedFE;flipud(t.RequestedFE)],[t.BootstrapLower95;flipud(t.BootstrapUpper95)],colors(k,:), ...
        'FaceAlpha',.15,'EdgeColor','none'); hold(ax,'on');
    plot(ax,t.RequestedFE,t.Median,'-o','Color',colors(k,:),'LineWidth',1.5);
    xlabel(ax,"Requested FE per run"); ylabel(ax,labels(k)); grid(ax,'on'); xticks(ax,report.budgets);
end
title(layout,"Median pairwise spread: pointwise 95% seed-bootstrap intervals, conditional on the frozen model");
exportPair(fig,out,"bootstrap_geographic_spread");
end
function exportPair(fig,out,stem)
exportgraphics(fig,fullfile(out,stem+".png"),'Resolution',200);
exportgraphics(fig,fullfile(out,stem+".pdf"),'ContentType','vector');
end

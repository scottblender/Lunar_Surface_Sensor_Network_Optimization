function plotGaSolutionFamilies(report)
% PLOTGASOLUTIONFAMILIES - Objective/spatial spread, shared families, sensitivity.
out=report.outputDirectory; r=report.runs; budgets=unique(r.RequestedFE).'; colors=lines(numel(budgets));
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 12 5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
for metric=1:2
    ax=nexttile(layout); hold(ax,"on");
    names=["MedianMeanMatchedKm","P90MeanMatchedKm"];
    label="Mean matched sensor distance (km)";
    if metric==2, names=["MedianBottleneckKm","P90BottleneckKm"]; label="Minimum worst-sensor matched distance (km)"; end
    for subset=["all","near_best"]
        t=report.pairwiseDispersion(report.pairwiseDispersion.Subset==subset,:);
        color=[0.1 0.35 0.7]; if subset=="near_best", color=[0.8 0.25 0.1]; end
        plot(ax,t.RequestedFE,t.(names(1)),"-o","Color",color,"DisplayName",subset+" median","LineWidth",1.5);
        plot(ax,t.RequestedFE,t.(names(2)),"--o","Color",color,"DisplayName",subset+" P90","LineWidth",1.5);
    end
    xlabel(ax,"Requested FE per run"); ylabel(ax,label); grid(ax,"on"); legend(ax,"Location","best"); xticks(ax,budgets);
end
title(layout,"Reference-free network spread: observer permutations are minimized for every pair");
exportPair(fig,out,"reference_free_dispersion_vs_fe"); clear cleanup
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 9 5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); hold(ax,"on");
for k=1:numel(budgets)
    t=r(r.RequestedFE==budgets(k)&r.NearBest,:);
    offset=0; if numel(budgets)>1, offset=-0.2+0.4*(k-1)/(numel(budgets)-1); end
    scatter(ax,t.Family+offset,t.ObjectiveGap,22,colors(k,:),"filled","DisplayName",sprintf("FE %d",budgets(k)));
end
xlabel(ax,"Geometric family (fixed across FE budgets)"); ylabel(ax,"Objective gap from best observed score");
title(ax,"Compare scores of near-best families; pooled results contain paired seeds");
legend(ax,"Location","best"); grid(ax,"on");
exportPair(fig,out,"family_objective_distributions"); clear cleanup
f=report.frequency; nf=height(report.families);
final=f(f.RequestedFE==max(budgets) & f.Family>0,:); final=sortrows(final,{'RunCount','Family'},{'descend','ascend'});
shown=final.Family(1:min(8,height(final))); others=setdiff((1:nf).',shown);
values=zeros(numel(budgets),numel(shown)+1+(~isempty(others)));
labels="Outside score tolerance"; cmap=[0.75 0.75 0.75;lines(numel(shown)+(~isempty(others)))];
for k=1:numel(budgets)
    t=f(f.RequestedFE==budgets(k),:); values(k,1)=t.PercentAllRuns(t.Family==0);
    for j=1:numel(shown), values(k,j+1)=t.PercentAllRuns(t.Family==shown(j)); end
    if ~isempty(others), values(k,end)=sum(t.PercentAllRuns(ismember(t.Family,others))); end
end
for c=shown.', labels(end+1)="Family "+string(c); end
if ~isempty(others), labels(end+1)="Other qualifying families"; end
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 9 5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); bars=bar(ax,categorical(string(budgets),string(budgets)),values,"stacked");
for k=1:numel(bars), bars(k).FaceColor=cmap(k,:); end
ylim(ax,[0 100]); xlabel(ax,"Requested FE per run"); ylabel(ax,"Percentage of ALL independent runs");
title(ax,sprintf("Fixed pooled families | gap <= %.4g | %s-distance diameter <= %.0f km", ...
    report.options.ObjectiveGap,report.options.DistanceMetric,report.options.DistanceKm));
legend(ax,labels,"Location","eastoutside"); grid(ax,"on");
exportPair(fig,out,"family_frequency_vs_fe"); clear cleanup
s=report.sensitivity; gaps=unique(s.ObjectiveGap).'; distances=unique(s.DistanceKm); z=zeros(numel(distances),numel(gaps));
for i=1:numel(distances)
    for j=1:numel(gaps), z(i,j)=s.NumberOfFamilies(s.DistanceKm==distances(i)&s.ObjectiveGap==gaps(j)); end
end
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 8 5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); imagesc(ax,z); ax.YDir="normal"; colormap(ax,parula); colorbar(ax);
xticks(ax,1:numel(gaps)); xticklabels(ax,string(gaps)); yticks(ax,1:numel(distances)); yticklabels(ax,string(distances));
for i=1:numel(distances)
    for j=1:numel(gaps)
        text(ax,j,i,string(z(i,j)),"HorizontalAlignment","center","FontWeight","bold", ...
            "Color","black","BackgroundColor","white","Margin",1);
    end
end
xlabel(ax,"Absolute objective-gap tolerance"); ylabel(ax,"Complete-link diameter threshold (km)");
title(ax,"Number of geometric families: sensitivity, not a count of proven modes");
exportPair(fig,out,"family_threshold_sensitivity");
clear cleanup
hemispheres=["south","north"]; columns=min(4,numel(budgets)); groups=ceil(numel(budgets)/columns);
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 max(7,3.2*columns) 6.5*groups]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2*groups,columns,"TileSpacing","compact","Padding","compact");
style=publicationPlotStyle(); style.axisFontSize=10; dem=@(lat,lon)zeros(size(lat));
if strlength(report.options.DemFile)>0, [dem,~]=digitalElevationModel.loadTriaxialLunarDem(report.options.DemFile); end
for k=1:numel(budgets)
    group=floor((k-1)/columns); column=mod(k-1,columns)+1;
    for h=1:2
        rows=1:9; if h==2, rows=10:18; end
        ax=nexttile(layout,(2*group+h-1)*columns+column);
        plotPolarSelectionMap(ax,report.frequencyPercent(rows,:,k), ...
            report.latitudeEdges([rows rows(end)+1]),report.longitudeEdges,dem,style,hemispheres(h));
        title(ax,sprintf("%s | FE %d",hemispheres(h),budgets(k)),"FontSize",12);
    end
end
cb=colorbar(ax); cb.Layout.Tile="east"; cb.Label.String="Runs selecting any sensor in bin (%)"; cb.Ticks=0:20:100;
title(layout,"Unlabeled geographic selection frequency: all runs, same 10 x 30 degree bins");
exportPair(fig,out,"unlabeled_geographic_frequency");

end
function exportPair(fig,out,stem)
exportgraphics(fig,fullfile(out,stem+".png"),"Resolution",200);
exportgraphics(fig,fullfile(out,stem+".pdf"),"ContentType","vector");
end

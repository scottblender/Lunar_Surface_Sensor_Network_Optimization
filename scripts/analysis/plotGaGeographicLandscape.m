function plotGaGeographicLandscape(report)
% PLOTGAGEOGRAPHICLANDSCAPE - Plot evaluated grid nodes, never interpolate gates.
colors=interp1([0 .5 1],[.10 .35 .70;.98 .98 .98;.85 .30 .08],linspace(0,1,256));
p=report.probes; c=report.contexts; nr=height(report.representatives); out=report.outputDirectory;
for local=[false true]
    fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 12 max(4,3.2*nr)]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,nr,3,'TileSpacing','compact','Padding','compact');
    allowed=true(height(p),1); if local, allowed=p.DistanceFromOriginalKm<=report.options.LocalRadiusKm; end
    limit=max(abs(p.ChangeFromSavedObjective(allowed))); limit=max(limit,1e-12);
    for context=1:height(c)
        ax=nexttile(layout); t=p(p.Context==c.Context(context)&allowed,:); hold(ax,'on');
        x=t.LongitudeDeg; x0=c.OriginalLongitudeDeg(context);
        if local, x=mod(x-x0+180,360)-180; x0=0; end
        scatter(ax,x,t.LatitudeDeg,12,t.ChangeFromSavedObjective,'filled');
        plot(ax,x0,c.OriginalLatitudeDeg(context),'rp','MarkerFaceColor','red','MarkerSize',9);
        if ~local
            plot(ax,[c.Held1LongitudeDeg(context),c.Held2LongitudeDeg(context)], ...
                [c.Held1LatitudeDeg(context),c.Held2LatitudeDeg(context)],'ks','MarkerFaceColor','black','MarkerSize',4);
            xlim(ax,[0 360]); ylim(ax,[-90 90]); xticks(ax,0:90:360);
        end
        title(ax,sprintf('Rep %d | moving slot %d | held IDs %d, %d', ...
            c.Representative(context),c.MovingSlot(context),c.HeldCandidate1(context),c.HeldCandidate2(context)),'FontSize',9);
        if local, xlabel(ax,'Wrapped longitude from original site (deg)'); else, xlabel(ax,'East longitude (deg)'); end
        ylabel(ax,'Latitude (deg)'); grid(ax,'on'); colormap(ax,colors); clim(ax,[-limit limit]);
    end
    cb=colorbar(ax); cb.Layout.Tile='east'; cb.Label.String='Objective minus saved-network objective (negative is better)';
    stem="conditional_global_maps"; caption="Global sampled frozen-grid sites; red star: original; black squares: held sites";
    if local, stem="conditional_local_maps"; caption="Local sampled sites; two sensors held fixed; no interpolation or local optimization"; end
    title(layout,caption,'FontSize',11); exportPair(fig,out,stem,true); clear cleanup
end
if ~isempty(report.perRsoContributions)
    weighted=report.componentInformationScores.*report.normalizedWeights;
    fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 12 7]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
    ax=nexttile(layout); imagesc(ax,weighted); colorbar(ax);
    ylabel(ax,'Representative'); xlabel(ax,'RSO'); title(ax,'Weighted per-RSO information contributions');
    yticks(ax,1:nr); xticks(ax,1:size(weighted,2));
    ax=nexttile(layout); difference=weighted-mean(weighted,1); imagesc(ax,difference); colormap(ax,colors);
    limit=max(1e-12,max(abs(difference),[],'all')); clim(ax,[-limit limit]); colorbar(ax);
    ylabel(ax,'Representative'); xlabel(ax,'RSO'); title(ax,'Contribution minus mean across representatives: compensating trade-offs');
    yticks(ax,1:nr); xticks(ax,1:size(weighted,2));
    title(layout,'Components reconstruct the original frozen weighted objective; these are not EKF errors');
    exportPair(fig,out,"per_rso_contribution_tradeoffs",false); clear cleanup
end
if ~isempty(report.jointProbes)
    j=report.jointProbes; fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 max(5,4*nr) 4.5]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,1,nr,'TileSpacing','compact','Padding','compact');
    limit=max(1e-12,max(abs(j.ChangeFromSavedObjective),[],'omitnan'));
    for rep=1:nr
        ax=nexttile(layout); t=j(j.Representative==rep,:);
        z=NaN(max(t.FirstProbeIndex),max(t.SecondProbeIndex));
        z(sub2ind(size(z),t.FirstProbeIndex,t.SecondProbeIndex))=t.ChangeFromSavedObjective;
        h=imagesc(ax,z); h.AlphaData=isfinite(z); ax.Color=[.7 .7 .7]; colormap(ax,colors); clim(ax,[-limit limit]);
        title(ax,sprintf('Rep %d | third site held fixed',rep));
        xlabel(ax,'Second-site probe index'); ylabel(ax,'First-site probe index');
    end
    cb=colorbar(ax); cb.Layout.Tile='east'; cb.Label.String='Objective change (negative is better; gray is invalid)';
    title(layout,'Coordinated two-site probes: indices identify saved candidate IDs, not continuous coordinates');
    exportPair(fig,out,"joint_two_site_probes",true);
end
end
function exportPair(fig,out,stem,raster)
exportgraphics(fig,fullfile(out,stem+".png"),'Resolution',180);
kind="vector"; if raster, kind="image"; end
exportgraphics(fig,fullfile(out,stem+".pdf"),'ContentType',kind,'Resolution',180);
end

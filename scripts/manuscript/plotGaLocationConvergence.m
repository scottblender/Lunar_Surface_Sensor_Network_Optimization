function plotGaLocationConvergence(result,database)
% PLOTGALOCATIONCONVERGENCE - Two paper-inspired global polar frequency figures.
% Columns vary run count at the largest FE, or FE at the largest run count.
% North and south maps share 10-degree latitude / 30-degree longitude bins.
analysis=result.analysis; config=result.config;
terrain=[];
if isfield(database.meta,"demSource") && isfile(database.meta.demSource)
    [terrain,~]=digitalElevationModel.loadTriaxialLunarDem(string(database.meta.demSource));
end
colors=[0.78 0.16 0.18;0.10 0.50 0.20;0.50 0.20 0.72];
for mode=["samples","evaluations"]
    if mode=="samples"
        settings=config.runCounts; name="independent_samples_location_convergence";
        heading=sprintf("Three-observer global GA: independent runs (requested FE = %d)",max(config.functionEvaluationBudgets));
        xlabelText="Independent GA runs";
    else
        settings=config.functionEvaluationBudgets; name="function_evaluations_location_convergence";
        heading=sprintf("Three-observer global GA: requested FE budgets (%d independent runs)",max(config.runCounts));
        xlabelText="Requested FE budget (raw GA counts are audited separately)";
    end
    n=numel(settings);
    f=figure('Visible','off','Color','white','Position',[50 50 max(900,330*n) 1050]);
    cleanup=onCleanup(@()close(f));
    layout=tiledlayout(f,3,n,'TileSpacing','compact','Padding','compact');
    title(layout,heading,'FontSize',14,'FontWeight','bold');
    lastAx=[];
    for column=1:n
        if mode=="samples", count=settings(column); budget=max(config.functionEvaluationBudgets);
        else, count=max(config.runCounts); budget=settings(column); end
        selected=analysis.alignedRecords([analysis.alignedRecords.requestedBudget]==budget & ...
            [analysis.alignedRecords.runIndex]<=count);
        for hemisphere=1:2
            ax=nexttile(layout,(hemisphere-1)*n+column); lastAx=ax;
            north=hemisphere==1; latitudeEdges=-90:10:0; longitudeEdges=0:30:360;
            frequency=zeros(9,12);
            for run=1:numel(selected)
                sites=selected(run).locations; keep=sites(:,1)<0;
                if north, keep=sites(:,1)>=0; end
                mapped=-abs(sites(keep,1));
                frequency=frequency+(histcounts2(mapped,mod(sites(keep,2),360),latitudeEdges,longitudeEdges)>0);
            end
            frequency=100*frequency/numel(selected);
            if isempty(terrain), dem=@(lat,lon)zeros(size(lat));
            elseif north, dem=@(lat,lon)terrain(-lat,lon);
            else, dem=@(lat,lon)terrain(lat,lon); end
            plotPolarSelectionMap(ax,frequency,latitudeEdges,longitudeEdges,dem,struct("axisFontSize",9));
            if north
                texts=findall(ax,'Type','text');
                for t=1:numel(texts), texts(t).String=strrep(texts(t).String,'S','N'); end
            end
            for observer=1:3
                ids=arrayfun(@(r)r.candidateIds(observer),selected);
                for id=unique(ids(:)).'
                    first=find(ids==id,1); location=selected(first).locations(observer,:);
                    if (north && location(1)<0) || (~north && location(1)>=0), continue; end
                    radius=1-abs(location(1))/90; longitude=location(2);
                    scatter3(ax,radius*sind(longitude),radius*cosd(longitude),4, ...
                        8+80*mean(ids==id),colors(observer,:),'filled','MarkerEdgeColor','white','LineWidth',0.3);
                end
                location=analysis.reference(observer,:);
                if (north && location(1)>=0) || (~north && location(1)<0)
                    radius=1-abs(location(1))/90;
                    text(ax,radius*sind(location(2)),radius*cosd(location(2)),5,sprintf(" O%d",observer), ...
                        'Color',colors(observer,:),'FontWeight','bold','FontSize',10,'Clipping','on');
                end
            end
            side="South"; if north, side="North"; end
            title(ax,sprintf("%s | N = %d | FE = %d",side,count,budget),'FontSize',10);
        end
    end
    cb=colorbar(lastAx); cb.Layout.Tile='east'; cb.Label.String='Runs selecting bin (%)'; cb.Ticks=0:20:100;
    ax=nexttile(layout,2*n+1,[1 n]); hold(ax,'on');
    for observer=1:3
        values=zeros(size(settings));
        for k=1:n
            count=max(config.runCounts); budget=max(config.functionEvaluationBudgets);
            if mode=="samples", count=settings(k); else, budget=settings(k); end
            row=analysis.summary.Observer==observer & analysis.summary.IndependentRuns==count & analysis.summary.RequestedFE==budget;
            values(k)=analysis.summary.P90DistanceKm(row);
        end
        plot(ax,settings,values,'-o','Color',colors(observer,:),'DisplayName',sprintf('Observer %d',observer),'LineWidth',1.5);
    end
    xlabel(ax,xlabelText); ylabel(ax,'90th-percentile distance from reference (km)');
    title(ax,'Small distance and concentrated maps indicate repeatable locations; a broad plateau does not');
    legend(ax,'Location','best'); grid(ax,'on'); xticks(ax,settings);
    if numel(settings)>1, xlim(ax,[min(settings) max(settings)]); end
    fprintf("Exporting %s.png...\n",name);
    exportgraphics(f,fullfile(config.outputDirectory,name+".png"),'Resolution',180);
    fprintf("Exporting %s.pdf...\n",name);
    exportgraphics(f,fullfile(config.outputDirectory,name+".pdf"),'ContentType','image','Resolution',300);
    fprintf("Finished %s exports.\n",name);
    clear cleanup;
end
end

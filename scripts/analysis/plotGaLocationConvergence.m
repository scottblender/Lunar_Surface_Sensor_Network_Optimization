function report=plotGaLocationConvergence(studyDirectory,demFile,independentRuns)
% PLOTGALOCATIONCONVERGENCE - Reuse manuscript selection maps across FE budgets.
% Reads saved convergence data only. No database, GPU, or GA rerun is needed.
% A bin is counted once per run if ANY observer is in it, matching the paper.
% Global bins are formed before hemisphere splitting: equator belongs north.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
    independentRuns (1,1) double = Inf
end
file=fullfile(studyDirectory,"ga_convergence_study.mat");
assert(isfile(file),"plotGaLocationConvergence:Missing","Missing completed sweep: %s",file);
saved=load(file,"result"); result=saved.result;
assert(result.status=="complete","plotGaLocationConvergence:Incomplete","Use a completed convergence sweep.");
if isinf(independentRuns), independentRuns=max(result.config.runCounts); end
validateattributes(independentRuns,{'double'},{'scalar','integer','positive','finite'});
budgets=sort(unique([result.records.requestedBudget]));
latitudeEdges=-90:10:90; longitudeEdges=0:30:360;
frequency=zeros(18,12,numel(budgets)); exactRows={}; binRows={};
for k=1:numel(budgets)
    records=result.records([result.records.requestedBudget]==budgets(k) & ...
        [result.records.runIndex]<=independentRuns);
    [~,order]=sort([records.runIndex]); records=records(order);
    assert(numel(records)==independentRuns && isequal([records.runIndex],1:independentRuns), ...
        "plotGaLocationConvergence:Runs","Every FE budget must contain the same complete run prefix.");
    runStates=cell(independentRuns,1);
    for j=1:independentRuns
        assert(isequal(size(records(j).locations),[3 2]), ...
            "plotGaLocationConvergence:NetworkSize","Expected three observers per run.");
        assert(numel(records(j).candidateIds)==3 && numel(unique(records(j).candidateIds))==3, ...
            "plotGaLocationConvergence:CandidateIds","Each run must contain three distinct candidate IDs.");
        runStates{j}=struct("bestSensorLatitudesRad",deg2rad(records(j).locations(:,1)), ...
            "bestSensorLongitudesRad",deg2rad(records(j).locations(:,2)));
    end
    % Reuse the existing manuscript counting rule. Observer labels do not matter.
    frequency(:,:,k)=binNetworkSelectionFrequency(runStates,struct(),latitudeEdges,longitudeEdges);
    for i=1:18
        for j=1:12
            binRows{end+1,1}=struct("RequestedFE",budgets(k),"IndependentRuns",independentRuns, ...
                "LatitudeLowerDeg",latitudeEdges(i),"LatitudeUpperDeg",latitudeEdges(i+1), ...
                "LongitudeLowerDeg",longitudeEdges(j),"LongitudeUpperDeg",longitudeEdges(j+1), ...
                "SelectionPercent",frequency(i,j,k)); %#ok<AGROW>
        end
    end
    ids=vertcat(records.candidateIds); locations=vertcat(records.locations);
    [sites,first,group]=unique(ids); count=accumarray(group,1);
    for j=1:numel(sites)
        exactRows{end+1,1}=struct("RequestedFE",budgets(k),"IndependentRuns",independentRuns, ...
            "CandidateId",sites(j),"LatitudeDeg",locations(first(j),1), ...
            "LongitudeDeg",mod(locations(first(j),2),360), ...
            "RunsSelected",count(j),"SelectionPercent",100*count(j)/independentRuns); %#ok<AGROW>
    end
end
bins=struct2table(vertcat(binRows{:}));
exact=struct2table(vertcat(exactRows{:}));
exact=sortrows(exact,{'RequestedFE','SelectionPercent'},{'ascend','descend'});
% Reuse saved permutation alignment and ONE full-sweep empirical reference.
% Recomputing medoids separately per budget would make distances incomparable.
summaryRows={}; locations=result.analysis.locations;
for budget=budgets
    for observer=1:3
        rows=locations.RequestedFE==budget & locations.RunIndex<=independentRuns & locations.Observer==observer;
        d=sort(locations.DistanceFromReferenceKm(rows));
        assert(numel(d)==independentRuns,"plotGaLocationConvergence:Alignment","Incomplete aligned locations.");
        x=1+0.9*(numel(d)-1);
        p90=d(floor(x))+(x-floor(x))*(d(ceil(x))-d(floor(x)));
        summaryRows{end+1,1}=struct("RequestedFE",budget,"IndependentRuns",independentRuns,"Observer",observer, ...
            "MedianDistanceKm",median(d),"P90DistanceKm",p90,"MaximumDistanceKm",max(d), ...
            "SameCandidatePercent",100*mean(locations.CandidateId(rows)==result.analysis.referenceCandidateIds(observer))); %#ok<AGROW>
    end
end
summary=struct2table(vertcat(summaryRows{:}));
out=fullfile(studyDirectory,"location_frequency_plots",sprintf("n_%d",independentRuns));
if ~isfolder(out), mkdir(out); end
writetable(bins,fullfile(out,"selection_frequency_bins.csv"));
writetable(exact,fullfile(out,"exact_candidate_frequency.csv"));
writetable(summary,fullfile(out,"location_consistency_vs_fe.csv"));
dem=@(lat,lon)zeros(size(lat)); terrainLabel="Neutral background (no DEM supplied)";
if strlength(demFile)>0
    [dem,~]=digitalElevationModel.loadTriaxialLunarDem(demFile);
    terrainLabel="Gray background: terrain elevation";
end
style=publicationPlotStyle(); style.axisFontSize=10;
% Keep at most four FE columns; additional budgets create a new panel row pair.
columns=min(4,numel(budgets)); groups=ceil(numel(budgets)/columns);
fig=figure("Name","Selection frequency versus FE","Color","white", ...
    "Units","inches","Position",[0.5 0.5 max(7,3.2*columns) 6.7*groups],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2*groups,columns,"TileSpacing","compact","Padding","compact");
for k=1:numel(budgets)
    group=floor((k-1)/columns); column=mod(k-1,columns)+1;
    for hemisphere=["south","north"]
        row=2*group+1; latRows=1:9;
        if hemisphere=="north", row=row+1; latRows=10:18; end
        ax=nexttile(layout,(row-1)*columns+column);
        plotPolarSelectionMap(ax,frequency(latRows,:,k),latitudeEdges([latRows latRows(end)+1]), ...
            longitudeEdges,dem,style,hemisphere);
        title(ax,sprintf("%s | FE %d",upper(extractBefore(hemisphere,2))+extractAfter(hemisphere,1),budgets(k)), ...
            "FontSize",12,"FontWeight","bold");
    end
end
cb=colorbar(ax); cb.Layout.Tile="east"; cb.Ticks=0:20:100;
cb.Label.String="Runs selecting at least one sensor in bin (%)";
title(layout,sprintf("3 observers | %d independent runs per FE | 10 deg x 30 deg bins",independentRuns),"FontSize",13);
subtitle(layout,terrainLabel+"; frequency scale fixed at 0-100%","FontSize",10);
exportgraphics(fig,fullfile(out,"selection_frequency_vs_fe.png"),"Resolution",220);
exportgraphics(fig,fullfile(out,"selection_frequency_vs_fe.pdf"),"ContentType","image","Resolution",220);
clear cleanFigure
fig=figure("Name","Location consistency versus FE","Color","white", ...
    "Units","inches","Position",[0.5 0.5 13 4.8],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
metrics=["MedianDistanceKm","P90DistanceKm","SameCandidatePercent"];
labels=["Median distance from reference (km)","P90 distance from reference (km)","Exact reference-site recurrence (%)"];
colors=lines(3);
for m=1:3
    ax=nexttile(layout); hold(ax,"on");
    for observer=1:3
        t=sortrows(summary(summary.Observer==observer,:),"RequestedFE");
        plot(ax,t.RequestedFE,t.(metrics(m)),"-o","Color",colors(observer,:), ...
            "LineWidth",1.6,"DisplayName",sprintf("Observer %d",observer));
    end
    xlabel(ax,"Requested FE per run"); ylabel(ax,labels(m)); grid(ax,"on");
    xticks(ax,budgets); if m==3, ylim(ax,[0 100]); else, ylim(ax,[0 Inf]); end
    legend(ax,"Location","best");
end
title(layout,"Same empirical reference network across all FE budgets; lower distances and higher recurrence indicate consistency", ...
    "FontSize",11);
exportgraphics(fig,fullfile(out,"location_consistency_vs_fe.png"),"Resolution",220);
exportgraphics(fig,fullfile(out,"location_consistency_vs_fe.pdf"),"ContentType","vector");
report=struct("outputDirectory",out,"independentRuns",independentRuns,"budgets",budgets, ...
    "latitudeEdges",latitudeEdges,"longitudeEdges",longitudeEdges,"frequencyPercent",frequency, ...
    "bins",bins,"exactCandidateFrequency",exact,"locationSummary",summary, ...
    "referenceRule",result.analysis.referenceRule, ...
    "interpretation","coarse-bin stability alone does not establish exact-location consistency");
save(fullfile(out,"location_frequency_report.mat"),"report");
fprintf("Selection-frequency and location-consistency figures saved to:\n  %s\n",out);
end

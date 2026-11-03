function report=plotGaObserverEfficiency(studyDirectory,independentRuns,options)
% PLOTGAOBSERVEREFFICIENCY - Observer IQR versus median solver runtime per run.
% Marginal efficiency = IQR reduction / additional median runtime, in km/s.
arguments
    studyDirectory (1,1) string
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,:) double = []
end
report=loadGaObserverLocations(studyDirectory,independentRuns,options.RequestedFE);
locations=report.locations; budgets=report.requestedFE;
saved=load(fullfile(studyDirectory,"ga_convergence_study.mat"),"result");
r=saved.result.records;
r=r(ismember([r.requestedBudget],budgets) & [r.runIndex]<=report.independentRuns);
assert(isfield(r,"runtimeSeconds") && all(arrayfun(@(x)isnumeric(x.runtimeSeconds) && ...
    isscalar(x.runtimeSeconds) && isfinite(x.runtimeSeconds) && x.runtimeSeconds>0,r)), ...
    "observerEfficiency:Runtime","Every selected run needs a finite, positive saved runtimeSeconds.");
runTimings=table([r.requestedBudget].',[r.runIndex].',[r.seed].',[r.runtimeSeconds].', ...
    'VariableNames',{'RequestedFE','RunIndex','Seed','RuntimeSeconds'});
runTimings=sortrows(runTimings,{'RequestedFE','RunIndex'});
summaryRows={}; intervalRows={};
for observer=1:3
    for k=1:numel(budgets)
        d=locations.DistanceFromBestKm(locations.Observer==observer & locations.RequestedFE==budgets(k));
        t=runTimings.RuntimeSeconds(runTimings.RequestedFE==budgets(k));
        summaryRows{end+1,1}=struct("Observer",observer,"RequestedFE",budgets(k), ...
            "IndependentRuns",numel(d),"MedianRuntimeSeconds",median(t), ...
            "MedianDistanceKm",median(d),"IQRKm",iqr(d)); %#ok<AGROW>
        if k>1
            previous=summaryRows{end-1}; current=summaryRows{end};
            gain=previous.IQRKm-current.IQRKm;
            cost=current.MedianRuntimeSeconds-previous.MedianRuntimeSeconds;
            efficiency=NaN; if cost>0, efficiency=gain/cost; end
            intervalRows{end+1,1}=struct("Observer",observer,"FromFE",budgets(k-1), ...
                "ToFE",budgets(k),"IQRReductionKm",gain,"AdditionalMedianRuntimeSeconds",cost, ...
                "IQRReductionKmPerSecond",efficiency,"RuntimeIncreaseValid",cost>0); %#ok<AGROW>
        end
    end
end
report.summary=struct2table(vertcat(summaryRows{:}));
if isempty(intervalRows)
    report.efficiency=table('Size',[0 7],'VariableTypes', ...
        {'double','double','double','double','double','double','logical'}, ...
        'VariableNames',{'Observer','FromFE','ToFE','IQRReductionKm', ...
        'AdditionalMedianRuntimeSeconds','IQRReductionKmPerSecond','RuntimeIncreaseValid'});
else
    report.efficiency=struct2table(vertcat(intervalRows{:}));
end
report.runTimings=runTimings;
report.runtimeRule="median of saved per-run solver runtimeSeconds; excludes shared preparation, post-processing and file export; reused checkpoints retain original timings";
report.efficiencyRule="(previous IQR - next IQR) / (next median runtime - previous median runtime); NaN when runtime change is nonpositive";
fig=figure("Name","Observer IQR versus runtime","Color","white", ...
    "Units","inches","Position",[0.5 0.5 13 4.8],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
limit=max(1,1.2*max(report.summary.IQRKm));
for observer=1:3
    ax=nexttile(layout); t=report.summary(report.summary.Observer==observer,:);
    plot(ax,t.MedianRuntimeSeconds,t.IQRKm,"-o","Color",[0.05 0.35 0.65],"LineWidth",1.5);
    for k=1:height(t)
        text(ax,t.MedianRuntimeSeconds(k),t.IQRKm(k),sprintf("  %d",t.RequestedFE(k)), ...
            "FontSize",9,"VerticalAlignment","bottom");
    end
    title(ax,sprintf("Observer %d",observer),"FontSize",12);
    xlabel(ax,"Median solver runtime per run (s)"); ylabel(ax,"IQR of distance from best-run site (km)");
    xlim(ax,[0 max(1,1.2*max(t.MedianRuntimeSeconds))]); ylim(ax,[0 limit]);
    grid(ax,"on"); ax.FontSize=10;
end
title(layout,sprintf("%d runs/FE | Reference: seed %d, FE %d, J = %.6f", ...
    report.independentRuns,report.referenceSeed,report.referenceRequestedFE,report.referenceObjective), ...
    "FontSize",12);
out=report.outputDirectory; if ~isfolder(out), mkdir(out); end
report.pngFile=fullfile(out,"observer_iqr_vs_runtime.png");
report.pdfFile=fullfile(out,"observer_iqr_vs_runtime.pdf");
report.summaryCsvFile=fullfile(out,"observer_iqr_runtime_summary.csv");
report.efficiencyCsvFile=fullfile(out,"observer_marginal_efficiency.csv");
report.timingsCsvFile=fullfile(out,"observer_run_timings.csv");
exportgraphics(fig,report.pngFile,"Resolution",220);
exportgraphics(fig,report.pdfFile,"ContentType","vector");
writetable(report.summary,report.summaryCsvFile);
writetable(report.efficiency,report.efficiencyCsvFile);
writetable(runTimings,report.timingsCsvFile);
disp(report.summary); disp(report.efficiency);
fprintf("Observer IQR/runtime figure saved to:\n  %s\n",report.pngFile);
end

function [summary, observers]=summarizeGaSearchSettings(report,records)
% Summarize saved objectives, solver times and matched distances by setting.
assert(isfield(records,"runtimeSeconds"),"observerEfficiency:Runtime", ...
    "Saved runs must include solver runtimes.");
settings=report.groupValues(:);
counts=report.groupRunCounts(:);
n=numel(settings);
meanObjective=zeros(n,1);
meanRuntime=meanObjective;
campaignRuntime=meanObjective;
spread=meanObjective;
observerRows=cell(n,1);
locations=report.locations;
for k=1:n
    fe=settings(k);
    if report.groupSuffix=="runs", fe=report.requestedFE; end
    cohort=records([records.requestedBudget]==fe & [records.runIndex]<=counts(k));
    timings=[cohort.runtimeSeconds];
    assert(numel(timings)==counts(k) && isreal(timings) && all(isfinite(timings) & timings>0), ...
        "observerEfficiency:Runtime","Each selected run needs a positive saved solver runtime.");
    meanObjective(k)=mean([cohort.objective]);
    meanRuntime(k)=mean(timings);
    campaignRuntime(k)=sum(timings);
    quartiles=zeros(3,3);
    for observer=1:3
        selected=locations.(report.groupVariable)==settings(k) & locations.Observer==observer;
        quartiles(observer,:)=reshape(prctile(locations.DistanceFromBestKm(selected),[25 50 75]),1,3);
    end
    widths=quartiles(:,3)-quartiles(:,1);
    spread(k)=mean(widths);
    observerRows{k}=table(repmat(settings(k),3,1),(1:3).',quartiles(:,1),quartiles(:,2), ...
        quartiles(:,3),widths,'VariableNames',{'Setting','Observer','Q25Km','MedianKm','Q75Km','IQRKm'});
end
values=[meanObjective,meanRuntime,spread];
minima=min(values,[],1);
ranges=max(values,[],1)-minima;
loss=zeros(size(values));
varying=ranges>0;
loss(:,varying)=(values(:,varying)-minima(varying))./ranges(varying);
efficiency=1-mean(loss,2);
summary=table(settings,counts,meanObjective,meanRuntime,campaignRuntime,spread, ...
    loss(:,1),loss(:,2),loss(:,3),efficiency,'VariableNames',{'Setting','IndependentRuns', ...
    'MeanFinalObjective','MeanSolverSecondsPerRun','CumulativeSolverSeconds','MeanIQRKm', ...
    'ObjectiveLoss','RuntimeLoss','SpreadLoss','Efficiency'});
observers=vertcat(observerRows{:});
end

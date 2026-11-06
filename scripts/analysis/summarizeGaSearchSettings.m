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
previousObjective=meanObjective(1:end-1);
previousSpread=spread(1:end-1);
previousRuntime=meanRuntime(1:end-1);
objectiveGain=relativeDecrease(previousObjective,meanObjective(2:end));
spreadGain=relativeDecrease(previousSpread,spread(2:end));
runtimeIncrease=(meanRuntime(2:end)-previousRuntime)./previousRuntime;

% Each score belongs to the transition into the setting on that row.
score=NaN(size(runtimeIncrease));
valid=runtimeIncrease>0 & isfinite(objectiveGain) & isfinite(spreadGain);
score(valid)=(objectiveGain(valid)+spreadGain(valid))./(2*runtimeIncrease(valid));
summary=table(settings,counts,meanObjective,meanRuntime,campaignRuntime,spread, ...
    [NaN;settings(1:end-1)],[NaN;objectiveGain],[NaN;spreadGain], ...
    [NaN;runtimeIncrease],[NaN;score],'VariableNames',{'Setting','IndependentRuns', ...
    'MeanFinalObjective','MeanSolverSecondsPerRun','CumulativeSolverSeconds','MeanIQRKm', ...
    'PreviousSetting','RelativeObjectiveImprovement','RelativeIQRImprovement', ...
    'RelativeRuntimeIncrease','Efficiency'});
observers=vertcat(observerRows{:});
end


function improvement=relativeDecrease(previous,current)
improvement=NaN(size(previous));
nonzero=previous~=0;
improvement(nonzero)=(previous(nonzero)-current(nonzero))./abs(previous(nonzero));
improvement(previous==0 & current==0)=0;
end

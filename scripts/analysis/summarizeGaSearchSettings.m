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
observers=vertcat(observerRows{:});
summary=table(settings,counts,meanObjective,meanRuntime,campaignRuntime,spread, ...
    'VariableNames',{'Setting','IndependentRuns','MeanFinalObjective', ...
    'MeanSolverSecondsPerRun','CumulativeSolverSeconds','MeanIQRKm'});

qualityObjective=meanObjective;
qualityDistance=spread;
cost=meanRuntime;
isRunStudy=report.groupSuffix=="runs";
if isRunStudy
    % Compare each nested prefix with the largest prefix using all nine
    % observer statistics (three observers times median, Q75, and IQR).
    qualityObjective=abs(meanObjective-meanObjective(end));
    qualityDistance=zeros(n,1);
    columns=["MedianKm","Q75Km","IQRKm"];
    referenceRows=observerRows{end};
    reference=referenceRows{:,columns};
    for k=1:n
        rows=observerRows{k};
        qualityDistance(k)=max(abs(rows{:,columns}-reference),[],"all");
    end
    cost=campaignRuntime;
    summary.MeanObjectiveError=qualityObjective;
    summary.MaxDistanceStatisticErrorKm=qualityDistance;
end

objectiveGain=relativeDecrease(qualityObjective(1:end-1),qualityObjective(2:end));
distanceGain=relativeDecrease(qualityDistance(1:end-1),qualityDistance(2:end));
previousCost=cost(1:end-1);
runtimeIncrease=(cost(2:end)-previousCost)./previousCost;
score=NaN(size(runtimeIncrease));
valid=runtimeIncrease>0 & isfinite(objectiveGain) & isfinite(distanceGain);
score(valid)=(objectiveGain(valid)+distanceGain(valid))./(2*runtimeIncrease(valid));

summary.PreviousSetting=[NaN;settings(1:end-1)];
if isRunStudy
    summary.RelativeObjectiveErrorReduction=[NaN;objectiveGain];
    summary.RelativeDistanceErrorReduction=[NaN;distanceGain];
else
    summary.RelativeObjectiveImprovement=[NaN;objectiveGain];
    summary.RelativeIQRImprovement=[NaN;distanceGain];
end
summary.RelativeRuntimeIncrease=[NaN;runtimeIncrease];
summary.Efficiency=[NaN;score];
if isRunStudy
    % The reference errors are zero by construction.
    summary.Efficiency(end)=NaN;
end
end

function improvement=relativeDecrease(previous,current)
improvement=NaN(size(previous));
nonzero=previous~=0;
improvement(nonzero)=(previous(nonzero)-current(nonzero))./abs(previous(nonzero));
improvement(previous==0 & current==0)=0;
end

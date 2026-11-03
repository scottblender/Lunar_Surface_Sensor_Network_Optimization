function efficiency=plotGaObserverEfficiency(studyDirectory,independentRuns,options)
% PLOTGAOBSERVEREFFICIENCY - Print FE and cumulative IQR efficiency only.
% Equal observer weights; baseline is the lowest selected FE; units are km/s.
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
meanIQR=zeros(numel(budgets),1); runtime=meanIQR;
for k=1:numel(budgets)
    widths=zeros(3,1);
    for observer=1:3
        selected=locations.Observer==observer & locations.RequestedFE==budgets(k);
        widths(observer)=iqr(locations.DistanceFromBestKm(selected));
    end
    meanIQR(k)=mean(widths);
    runtime(k)=median([r([r.requestedBudget]==budgets(k)).runtimeSeconds]);
end
addedTime=runtime-runtime(1);
value=NaN(size(runtime)); valid=addedTime>0;
value(valid)=(meanIQR(1)-meanIQR(valid))./addedTime(valid);
efficiency=table(budgets(:),value,'VariableNames',{'FE','EfficiencyKmPerSecond'});
out=report.outputDirectory; if ~isfolder(out), mkdir(out); end
writetable(efficiency,fullfile(out,"fe_efficiency.csv"));
disp(efficiency);
end

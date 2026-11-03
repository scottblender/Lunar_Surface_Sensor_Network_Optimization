function report=loadGaObserverLocations(studyDirectory,independentRuns,requestedFE)
% LOADGAOBSERVERLOCATIONS - Align saved sites to one fixed highest-FE best run.
% Shared by the polar and distance-distribution plots. No files are changed.
arguments
    studyDirectory (1,1) string
    independentRuns (1,1) double = Inf
    requestedFE (1,:) double = []
end
file=fullfile(studyDirectory,"ga_convergence_study.mat");
assert(isfile(file),"plotGaLocationConvergence:Missing","Missing completed sweep: %s",file);
saved=load(file,"result"); result=saved.result;
assert(result.status=="complete" && ~isempty(result.records), ...
    "plotGaLocationConvergence:Incomplete","Use a completed convergence sweep.");
budgets=requestedFE;
if isempty(budgets), budgets=unique([result.records.requestedBudget]); end
if isequal(budgets,Inf), budgets=max([result.records.requestedBudget]); end
validateattributes(budgets,{'double'},{'vector','integer','positive','finite'});
budgets=sort(unique(budgets));
assert(all(ismember(budgets,[result.records.requestedBudget])), ...
    "plotGaLocationConvergence:Budget","A requested FE budget has no saved runs.");
records=result.records(ismember([result.records.requestedBudget],budgets));
if isinf(independentRuns) && independentRuns>0, independentRuns=max([records.runIndex]); end
validateattributes(independentRuns,{'double'},{'scalar','integer','positive','finite'});
records=records([records.runIndex]<=independentRuns);
[~,order]=sortrows([[records.requestedBudget].' [records.runIndex].'],[1 2]); records=records(order);
seeds=[];
for budget=budgets
    cohort=records([records.requestedBudget]==budget);
    assert(numel(cohort)==independentRuns && isequal([cohort.runIndex],1:independentRuns) && ...
        numel(unique([cohort.seed]))==independentRuns, ...
        "plotGaLocationConvergence:Runs","Expected one distinct seed for every run at each FE budget.");
    if isempty(seeds), seeds=[cohort.seed]; end
    assert(isequal([cohort.seed],seeds),"plotGaLocationConvergence:Runs", ...
        "Every displayed FE budget must contain the same independent-run seed cohort.");
end
for k=1:numel(records)
    ids=double(records(k).candidateIds(:)); sites=records(k).locations;
    assert(numel(ids)==3 && numel(unique(ids))==3 && all(isfinite(ids) & ids>0 & ids==round(ids)) && ...
        isequal(size(sites),[3 2]) && all(isfinite(sites),"all") && all(abs(sites(:,1))<=90), ...
        "plotGaLocationConvergence:Network","Each run must contain three valid physical sites.");
    records(k).locations(:,2)=mod(sites(:,2),360);
end
objectives=[records.objective];
assert(all(isfinite(objectives)),"plotGaLocationConvergence:Objective","Objectives must be finite.");
% Records are run-index sorted: ties choose the lowest run index.
referenceRuns=records([records.requestedBudget]==max(budgets));
[~,bestIndex]=min([referenceRuns.objective]); best=referenceRuns(bestIndex);
% Observer numbers are display labels anchored to this best network.
[reference,order]=sortrows(best.locations,[1 2]); referenceIds=best.candidateIds(order);
rows=cell(numel(records),1);
for k=1:numel(records)
    [order,distance]=matchThreeObserverLocations(reference,records(k).locations);
    sites=records(k).locations(order,:); ids=records(k).candidateIds(order);
    hemisphere=repmat("south",3,1); hemisphere(sites(:,1)>=0)="north";
    rows{k}=table(repmat(records(k).requestedBudget,3,1),repmat(records(k).runIndex,3,1), ...
        repmat(records(k).seed,3,1),(1:3).',ids(:),sites(:,1),sites(:,2),distance,hemisphere, ...
        'VariableNames',{'RequestedFE','RunIndex','Seed','Observer','CandidateId', ...
        'LatitudeDeg','LongitudeDeg','DistanceFromBestKm','Hemisphere'});
end
locations=vertcat(rows{:});
feFolder="fe_"+join(string(budgets),"_");
out=fullfile(studyDirectory,"observer_location_plots",sprintf("n_%d",independentRuns),feFolder);
report=struct("outputDirectory",out,"requestedFE",budgets,"referenceRequestedFE",best.requestedBudget,"independentRuns",independentRuns, ...
    "referenceSeed",best.seed,"referenceRunIndex",best.runIndex,"referenceObjective",best.objective, ...
    "reference",reference,"referenceCandidateIds",referenceIds(:),"locations",locations, ...
    "referenceRule","lowest objective at largest displayed FE in selected run prefix; fixed across all FE; ties use lowest run index; observers sorted by latitude then longitude", ...
    "matchingRule","one-to-one assignment minimizing total great-circle distance to the best network");
end

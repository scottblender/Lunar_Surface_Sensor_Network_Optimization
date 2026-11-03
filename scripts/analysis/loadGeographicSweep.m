function data=loadGeographicSweep(studyDirectory)
% LOADGEOGRAPHICSWEEP - Require one complete paired seed cohort across FE.
file=fullfile(studyDirectory,"ga_convergence_study.mat");
s=load(file,"result"); result=s.result;
assert(result.status=="complete" && ~isempty(result.records), ...
    "geographicDiagnostics:Incomplete","Use a completed three-observer convergence sweep.");
r=result.records(:); budget=double([r.requestedBudget].'); seed=double([r.seed].');
assert(size(unique([budget seed],'rows'),1)==numel(r), ...
    "geographicDiagnostics:Seeds","Duplicate seed within a budget.");
budgets=unique(budget).'; seeds=unique(seed); index=zeros(numel(seeds),numel(budgets));
for k=1:numel(budgets)
    rows=find(budget==budgets(k)); [known,position]=ismember(seed(rows),seeds);
    assert(all(known) && numel(rows)==numel(seeds),"geographicDiagnostics:SeedCohort", ...
        "Every FE budget must contain the same complete seed cohort.");
    index(position,k)=rows;
end
assert(all(index>0,"all"),"geographicDiagnostics:SeedCohort","Incomplete paired seed cohort.");
ids=zeros(numel(r),3); coordinates=zeros(3,2,numel(r)); shape=zeros(numel(r),3);
for k=1:numel(r)
    assert(numel(r(k).candidateIds)==3 && isequal(size(r(k).locations),[3 2]), ...
        "geographicDiagnostics:Network","Expected three observers per network.");
    [ids(k,:),order]=sort(double(r(k).candidateIds(:).'));
    assert(all(isfinite(ids(k,:))) && all(ids(k,:)>0 & ids(k,:)==round(ids(k,:))) && ...
        numel(unique(ids(k,:)))==3,"geographicDiagnostics:Network","Invalid candidate IDs.");
    coordinates(:,:,k)=r(k).locations(order,:); coordinates(:,2,k)=mod(coordinates(:,2,k),360);
    shape(k,:)=networkShapeSignature(coordinates(:,:,k));
end
objective=double([r.objective].'); assert(all(isfinite(objective)),"geographicDiagnostics:Objective","Nonfinite objective.");
data=struct("studyDirectory",studyDirectory,"studyFile",file,"studySha256",analysisFileSha256(file), ...
    "records",r,"budgets",budgets,"seeds",seeds,"index",index,"ids",ids, ...
    "coordinates",coordinates,"shapeAnglesDeg",shape,"objective",objective);
end

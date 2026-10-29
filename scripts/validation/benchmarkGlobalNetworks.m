function benchmark = benchmarkGlobalNetworks(database,networkSize,numberOfSamples,seed,selectedMasterIds)
% BENCHMARKGLOBALNETWORKS - Uniform networks evaluated with the same information objective.
arguments
    database (1,1) struct
    networkSize (1,1) double {mustBeInteger,mustBePositive}
    numberOfSamples (1,1) double {mustBeInteger,mustBePositive}
    seed (1,1) double {mustBeInteger,mustBeNonnegative,mustBeLessThan(seed,4294967296)}
    selectedMasterIds (:,1) double
end
assert(database.config.domainComparison.domain=="global", ...
    "benchmarkGlobalNetworks:Domain","Benchmark must use the global view.");
assert(~database.config.domainComparison.enforceSiteGroups, ...
    "benchmarkGlobalNetworks:Constraint","Global sampling cannot enforce CLPS groups.");
masterIds=database.meta.sharedSourceCandidateIds(:);
[present,selected]=ismember(selectedMasterIds,masterIds);
assert(all(present) && numel(selected)==networkSize && numel(unique(selected))==networkSize, ...
    "benchmarkGlobalNetworks:Selected","Selected network is not in this global candidate set.");
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(seed,"twister");
networkIds=zeros(numberOfSamples,networkSize);
objectives=zeros(numberOfSamples,1);
for k=1:numberOfSamples
    ids=sampleGlobalCandidateNetwork(database.meta.numberOfCandidates,networkSize);
    networkIds(k,:)=masterIds(ids).';
    objectives(k)=optimization.networkObjective(ids,database,"information");
end
assert(all(isfinite(objectives) & objectives<database.objective.infeasiblePenalty), ...
    "benchmarkGlobalNetworks:Invalid","Random network has no finite feasible information objective.");
selectedObjective=optimization.networkObjective(selected,database,"information");
benchmark=struct("networkSize",networkSize,"numberOfSamples",numberOfSamples,"seed",seed, ...
    "masterCandidateIds",networkIds,"objectives",objectives, ...
    "selectedMasterIds",selectedMasterIds,"selectedObjective",selectedObjective, ...
    "fractionRandomNoBetter",mean(objectives>=selectedObjective), ...
    "numberRandomStrictlyBetter",nnz(objectives<selectedObjective), ...
    "minimumRandomObjective",min(objectives), ...
    "sampling","uniform subsets without replacement within each network; independent samples may repeat", ...
    "interpretation","negative information gain: lower is better; empirical comparison, not an optimality proof");
end

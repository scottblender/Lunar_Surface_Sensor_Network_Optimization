function report=evaluateGaGeographicLandscape(studyDirectory,databaseFile,options)
% EVALUATEGAGEOGRAPHICLANDSCAPE - GPU conditional maps and per-RSO trade-offs.
% No optimization, changed grid or selected-network refinement. Existing GPU
% scorer stays unchanged; one-hot weights isolate per-object scores and their
% weighted sum must reproduce the original score and independent CPU details.
arguments
    studyDirectory (1,1) string
    databaseFile (1,1) string
    options.RequestedFE (1,1) double = Inf
    options.MaxRepresentatives (1,1) double {mustBeInteger,mustBePositive} = 3
    options.RepresentativeSeeds (1,:) double = []
    options.ObjectiveGap (1,1) double {mustBeNonnegative,mustBeFinite} = 0.025
    options.MinimumSeparationKm (1,1) double {mustBeNonnegative,mustBeFinite} = 250
    options.GlobalSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
    options.LocalSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
    options.LocalRadiusKm (1,1) double {mustBePositive,mustBeFinite} = 250
    options.ProbeSeed (1,1) double {mustBeInteger,mustBeNonnegative} = 271828
    options.JointSamplesPerSite (1,1) double {mustBeInteger,mustBeNonnegative} = 0
    options.ComputePerRso (1,1) logical = true
    options.ExecutionDevice (1,1) string {mustBeMember(options.ExecutionDevice,["cpu","gpu"])} = "gpu"
    options.OutputDirectory (1,1) string = ""
    options.MakePlots (1,1) logical = true
end
timer=tic; d=loadGeographicSweep(studyDirectory); [database,signature]=verifyFrozenDiagnosticDatabase(studyDirectory,databaseFile);
fe=options.RequestedFE; if isinf(fe), fe=max(d.budgets); end
rows=find([d.records.requestedBudget].'==fe); assert(~isempty(rows),"geographicDiagnostics:Budget","Requested FE not in sweep.");
[~,order]=sortrows([d.objective(rows),double([d.records(rows).seed].')],[1 2]); rows=rows(order);
if isempty(options.RepresentativeSeeds)
    pool=rows(d.objective(rows)-min(d.objective(rows))<=options.ObjectiveGap+1e-12); chosen=pool(1);
    while numel(chosen)<min(options.MaxRepresentatives,numel(pool))
        distance=-Inf(numel(pool),1);
        for k=1:numel(pool)
            if ismember(pool(k),chosen), continue; end
            distance(k)=Inf;
            for c=chosen(:).'
                [~,x]=matchThreeObserverLocations(d.coordinates(:,:,pool(k)),d.coordinates(:,:,c),database.config.moon.radiusKm,"max");
                distance(k)=min(distance(k),max(x));
            end
        end
        [largest,k]=max(distance); if largest<options.MinimumSeparationKm, break; end
        chosen(end+1,1)=pool(k); %#ok<AGROW>
    end
    selectionRule="best observed plus greedy geographically separated near-best networks at chosen FE";
else
    seeds=double([d.records(rows).seed].'); [present,k]=ismember(options.RepresentativeSeeds,seeds);
    assert(all(present) && numel(unique(k))==numel(k),"geographicDiagnostics:Representatives","Unknown/duplicate representative seeds.");
    chosen=rows(k); selectionRule="explicit seeds; no near-best quality claim imposed";
end
reps=struct("Ids",d.ids(chosen,:),"SavedObjective",d.objective(chosen), ...
    "Seeds",double([d.records(chosen).seed].'),"SelectionRule",selectionRule);
[probes,contexts,joint]=buildGeographicProbeNetworks(reps,database,GlobalSamples=options.GlobalSamples, ...
    LocalSamples=options.LocalSamples,LocalRadiusKm=options.LocalRadiusKm,ProbeSeed=options.ProbeSeed, ...
    JointSamplesPerSite=options.JointSamplesPerSite);
nr=size(reps.Ids,1); ids=[reps.Ids;probes{:,{'Candidate1','Candidate2','Candidate3'}}];
validJoint=[];
if ~isempty(joint)
    validJoint=find(joint.ValidDistinctSites); ids=[ids;joint{validJoint,{'Candidate1','Candidate2','Candidate3'}}];
end
[uniqueIds,~,back]=unique(sort(ids,2),'rows','sorted');
fprintf("Evaluating %d distinct frozen-grid networks on %s; %d conditional contexts.\n",height(uniqueIds),options.ExecutionDevice,height(contexts));
[score,metadata]=createBatchedInformationObjective(database,options.ExecutionDevice);
values=score(uniqueIds); base=values(back(1:nr));
probes.Objective=values(back(nr+(1:height(probes))));
probes.ChangeFromSavedObjective=probes.Objective-reps.SavedObjective(probes.Representative);
if ~isempty(joint)
    joint.Objective=NaN(height(joint),1); joint.Objective(validJoint)=values(back(nr+height(probes)+(1:numel(validJoint))));
    joint.ChangeFromSavedObjective=joint.Objective-reps.SavedObjective(joint.Representative);
end
clear score
cpuByObject=zeros(nr,database.meta.numberOfObjects);
for k=1:nr
    [checked,detail]=optimization.networkObjective(reps.Ids(k,:),database,"information");
    assert(abs(base(k)-reps.SavedObjective(k))<=1e-8*max(1,abs(reps.SavedObjective(k))) && ...
        abs(base(k)-checked)<=1e-8*max(1,abs(checked)),"geographicDiagnostics:Agreement", ...
        "Representative scores disagree with frozen saved/CPU scores.");
    cpuByObject(k,:)=detail.informationByObject(:).';
end
contributions=table(); tradeoffs=table(); componentScores=[]; reconstructed=[];
weights=double(database.estimation.objectWeights(:).'); weights=weights/sum(weights);
preparationCount=1;
if options.ComputePerRso
    no=database.meta.numberOfObjects; componentScores=zeros(nr,no);
    for object=1:no
        fprintf("Per-RSO decomposition %d of %d (%s; unchanged GPU scorer).\n",object,no,options.ExecutionDevice);
        isolated=database; isolated.estimation.objectWeights=zeros(no,1); isolated.estimation.objectWeights(object)=1;
        component=createBatchedInformationObjective(isolated,options.ExecutionDevice);
        componentScores(:,object)=-component(reps.Ids); clear component isolated
        preparationCount=preparationCount+1;
    end
    assert(all(abs(componentScores-cpuByObject)<=1e-8*max(1,abs(cpuByObject)),"all"), ...
        "geographicDiagnostics:Contributions","Per-RSO decomposition disagrees with CPU components.");
    reconstructed=-sum(componentScores.*weights,2);
    assert(all(abs(reconstructed-base)<=1e-8*max(1,abs(base))), ...
        "geographicDiagnostics:Contributions","Components do not reconstruct original weighted objective.");
    contributionRows={}; pairRows={};
    for rep=1:nr
        for object=1:no
            contributionRows{end+1,1}=struct("Representative",rep,"Seed",reps.Seeds(rep),"RSO",object, ...
                "NormalizedWeight",weights(object),"InformationScore",componentScores(rep,object), ...
                "WeightedContribution",weights(object)*componentScores(rep,object)); %#ok<AGROW>
        end
    end
    for a=1:nr
        for b=a+1:nr
            difference=(componentScores(a,:)-componentScores(b,:)).*weights;
            pairRows{end+1,1}=struct("RepresentativeA",a,"RepresentativeB",b, ...
                "AbsoluteTotalScoreDifference",abs(sum(difference)),"L1ContributionDifference",sum(abs(difference)), ...
                "CompensatingDifference",max(0,sum(abs(difference))-abs(sum(difference)))); %#ok<AGROW>
        end
    end
    contributions=struct2table(vertcat(contributionRows{:}));
    if ~isempty(pairRows), tradeoffs=struct2table(vertcat(pairRows{:})); end
end
summaryRows={};
for c=1:height(contexts)
    t=probes(probes.Context==contexts.Context(c),:); local=t.DistanceFromOriginalKm<=options.LocalRadiusKm;
    [best,k]=min(t.Objective);
    summaryRows{end+1,1}=struct("Context",contexts.Context(c),"Representative",contexts.Representative(c), ...
        "MovingSlot",contexts.MovingSlot(c),"EvaluatedProbes",height(t),"LocalProbes",nnz(local), ...
        "SavedObjective",reps.SavedObjective(contexts.Representative(c)),"BestSampledObjective",best, ...
        "BestSampledCandidateId",t.ProbeCandidateId(k),"BestProbeDistanceKm",t.DistanceFromOriginalKm(k), ...
        "LargestSampledImprovement",reps.SavedObjective(contexts.Representative(c))-best, ...
        "LocalP10ObjectiveChange",diagnosticQuantile(t.ChangeFromSavedObjective(local),.1), ...
        "LocalP90ObjectiveChange",diagnosticQuantile(t.ChangeFromSavedObjective(local),.9)); %#ok<AGROW>
end
out=options.OutputDirectory; if strlength(out)==0, out=fullfile(studyDirectory,"geographic_landscape_diagnostics"); end
if ~isfolder(out), mkdir(out); end
representatives=table((1:nr).',reps.Seeds,reps.SavedObjective,reps.Ids(:,1),reps.Ids(:,2),reps.Ids(:,3), ...
    'VariableNames',{'Representative','Seed','SavedObjective','Candidate1','Candidate2','Candidate3'});
report=struct("version","geographic_landscape_diagnostics_v1","options",options,"studySha256",d.studySha256, ...
    "databaseSignature",signature,"metadata",metadata,"representatives",representatives,"selectionRule",selectionRule, ...
    "contexts",contexts,"probes",probes,"conditionalSummary",struct2table(vertcat(summaryRows{:})), ...
    "jointProbes",joint,"perRsoContributions",contributions,"contributionTradeoffs",tradeoffs, ...
    "normalizedWeights",weights,"componentInformationScores",componentScores, ...
    "weightedRepresentativeObjectives",base,"reconstructedObjectives",reconstructed, ...
    "uniqueWeightedDiagnosticEvaluations",height(uniqueIds),"oneHotDiagnosticEvaluations",nr*size(componentScores,2), ...
    "cpuValidationEvaluations",nr,"scorerPreparations",preparationCount,"elapsedSeconds",toc(timer), ...
    "outputDirectory",out,"interpretation", ...
    "conditional frozen-grid samples, not optimized profiles or confidence regions; slots are contextual; new diagnostic work is separate from GA FEs");
for field=["representatives","contexts","probes","conditionalSummary","jointProbes","perRsoContributions","contributionTradeoffs"]
    if ~isempty(report.(field)), writetable(report.(field),fullfile(out,field+".csv")); end
end
save(fullfile(out,"geographic_landscape_diagnostics.mat"),"report","-v7.3");
if options.MakePlots, plotGaGeographicLandscape(report); end
fprintf("Conditional maps and per-RSO diagnostics saved to: %s\n",out);
end

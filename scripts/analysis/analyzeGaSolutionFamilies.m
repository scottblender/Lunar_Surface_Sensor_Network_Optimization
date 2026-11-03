function report=analyzeGaSolutionFamilies(studyDirectory,options)
% ANALYZEGASOLUTIONFAMILIES - Retrospective families of near-best saved networks.
% No optimization/objective evaluations. Fixed observed-best score and pooled,
% deduplicated family definitions are shared by every FE budget. Score tolerances
% are ABSOLUTE objective units, not percentages of a logarithmic score.
arguments
    studyDirectory (1,1) string
    options.ObjectiveGap (1,1) double {mustBeNonnegative,mustBeFinite} = 0.025
    options.DistanceMetric (1,1) string {mustBeMember(options.DistanceMetric,["mean","max"])} = "max"
    options.DemFile (1,1) string = ""
    options.DistanceKm (1,1) double {mustBePositive,mustBeFinite} = 250
    options.GapScan (1,:) double {mustBeNonnegative,mustBeFinite} = [0.01 0.025 0.05]
    options.DistanceScanKm (1,:) double {mustBePositive,mustBeFinite} = [100 250 500]
    options.RadiusKm (1,1) double {mustBePositive,mustBeFinite} = 1737.4
    options.OutputDirectory (1,1) string = ""
    options.MakePlots (1,1) logical = true
end
inputFile=fullfile(studyDirectory,"ga_convergence_study.mat");
s=load(inputFile,"result"); result=s.result;
assert(result.status=="complete","networkFamilies:Incomplete","Use a completed convergence sweep.");
r=result.records(:); n=numel(r);
assert(n>0,"networkFamilies:Incomplete","Completed sweep contains no runs."); ids=zeros(n,3); coordinates=zeros(3,2,n);
for k=1:n
    [ids(k,:),order]=sort(double(r(k).candidateIds(:).'));
    assert(numel(unique(ids(k,:)))==3 && all(isfinite(ids(k,:))) && isequal(size(r(k).locations),[3 2]), ...
        "networkFamilies:Network","Expected three distinct physical candidate IDs and coordinates.");
    coordinates(:,:,k)=r(k).locations(order,:); coordinates(:,2,k)=mod(coordinates(:,2,k),360);
end
objective=double([r.objective].'); budget=double([r.requestedBudget].');
seed=double([r.seed].'); runIndex=double([r.runIndex].');
assert(all(isfinite(objective)),"networkFamilies:Objective","Nonfinite objective values.");
assert(size(unique([budget seed],'rows'),1)==n,"networkFamilies:Seeds","Duplicate seed within an FE budget.");
[networkIds,first,uniqueId]=unique(ids,'rows','sorted'); nu=size(networkIds,1);
uniqueCoordinates=coordinates(:,:,first); uniqueObjective=accumarray(uniqueId,objective,[],@min);
for k=1:n
    assert(max(abs(coordinates(:,:,k)-uniqueCoordinates(:,:,uniqueId(k))),[],"all")<1e-7, ...
        "networkFamilies:Coordinates","One candidate network has inconsistent saved coordinates.");
end
[bestObjective,bestRecord]=min(objective); bestUnique=uniqueId(bestRecord); gap=objective-bestObjective;
meanDistances=zeros(nu); bottleneckDistances=zeros(nu);
for i=1:nu
    for j=i+1:nu
        [~,d]=matchThreeObserverLocations(uniqueCoordinates(:,:,i),uniqueCoordinates(:,:,j),options.RadiusKm);
        meanDistances(i,j)=mean(d); meanDistances(j,i)=mean(d);
        [~,d]=matchThreeObserverLocations(uniqueCoordinates(:,:,i),uniqueCoordinates(:,:,j),options.RadiusKm,"max");
        bottleneckDistances(i,j)=max(d); bottleneckDistances(j,i)=max(d);
    end
end
D=bottleneckDistances; if options.DistanceMetric=="mean", D=meanDistances; end
gaps=unique([options.GapScan options.ObjectiveGap]); thresholds=unique([options.DistanceScanKm options.DistanceKm]);
budgets=unique(budget).'; scenarios={}; assignments=zeros(n,numel(gaps)*numel(thresholds)); scenario=0;
primaryLabels=[]; primaryUnique=[];
for e=gaps
    eligibleUnique=find(uniqueObjective-bestObjective<=e+1e-12);
    for threshold=thresholds
        scenario=scenario+1; labels=completeLinkNetworkFamilies(D(eligibleUnique,eligibleUnique),threshold);
        % Number families by best objective; ties follow canonical network ID.
        orderKey=zeros(max(labels),2);
        for c=1:max(labels)
            m=eligibleUnique(labels==c); orderKey(c,:)=[min(uniqueObjective(m)),min(m)];
        end
        [~,order]=sortrows(orderKey,[1 2]); map=zeros(numel(order),1); map(order)=1:numel(order);
        labels=map(labels); fullLabels=zeros(nu,1); fullLabels(eligibleUnique)=labels;
        qualifies=gap<=e+1e-12; rowLabels=fullLabels(uniqueId); rowLabels(~qualifies)=0;
        assignments(:,scenario)=rowLabels;
        counts=accumarray(labels,1);
        final=budget==max(budgets); finalLabels=rowLabels(final);
        finalCounts=accumarray(finalLabels(finalLabels>0),1,[max(labels) 1]);
        scenarios{end+1,1}=struct("ObjectiveGap",e,"DistanceKm",threshold, ...
            "QualifiedUniqueNetworks",numel(eligibleUnique),"NumberOfFamilies",max(labels), ...
            "SingletonFamilies",sum(counts==1),"FinalBudgetQualifyingPercent",100*mean(qualifies(final)), ...
            "LargestFinalFamilyPercentAllRuns",100*max(finalCounts)/nnz(final)); %#ok<AGROW>
        if e==options.ObjectiveGap && threshold==options.DistanceKm
            primaryLabels=rowLabels; primaryUnique=fullLabels;
        end
    end
end
nf=max(primaryUnique); medoids=zeros(nf,1); representatives=zeros(nf,1); familyRows={}; coordinateRows={}; frequencyRows={};
for c=1:nf
    members=find(primaryUnique==c); [~,m]=min(sum(D(members,members),2)); medoids(c)=members(m);
    [~,b]=min(uniqueObjective(members)); representatives(c)=members(b);
    values=objective(primaryLabels==c);
    familyRows{end+1,1}=struct("Family",c,"UniqueNetworks",numel(members), ...
        "BestObjective",min(values),"MedianObjective",median(values),"WorstObjective",max(values), ...
        "NetworkDiameterKm",max(D(members,members),[],"all"), ...
        "LargestMatchedSensorSeparationKm",max(bottleneckDistances(members,members),[],"all"), ...
        "MedoidNetworkId",medoids(c),"BestNetworkId",representatives(c)); %#ok<AGROW>
    [bestOrder,~]=matchThreeObserverLocations(uniqueCoordinates(:,:,medoids(c)),uniqueCoordinates(:,:,representatives(c)),options.RadiusKm);
    for observer=1:3
        bestObserver=bestOrder(observer);
        coordinateRows{end+1,1}=struct("Family",c,"Observer",observer, ...
            "MedoidCandidateId",networkIds(medoids(c),observer), ...
            "MedoidLatitudeDeg",uniqueCoordinates(observer,1,medoids(c)), ...
            "MedoidLongitudeDeg",uniqueCoordinates(observer,2,medoids(c)), ...
            "BestCandidateId",networkIds(representatives(c),bestObserver), ...
            "BestLatitudeDeg",uniqueCoordinates(bestObserver,1,representatives(c)), ...
            "BestLongitudeDeg",uniqueCoordinates(bestObserver,2,representatives(c))); %#ok<AGROW>
    end
end
for fe=budgets
    selected=budget==fe; qualified=selected & primaryLabels>0; nq=nnz(qualified); total=nnz(selected);
    for c=0:nf
        count=nnz(selected & primaryLabels==c); conditional=NaN;
        if c>0 && nq>0, conditional=100*count/nq; end
        frequencyRows{end+1,1}=struct("RequestedFE",fe,"Family",c,"RunCount",count, ...
            "TotalRuns",total,"QualifyingRuns",nq,"PercentAllRuns",100*count/total, ...
            "PercentQualifyingRuns",conditional); %#ok<AGROW>
    end
end
distanceToMedoid=NaN(n,1);
for k=find(primaryLabels>0).', distanceToMedoid(k)=D(uniqueId(k),medoids(primaryLabels(k))); end
runs=table(budget,runIndex,seed,objective,gap,uniqueId,primaryLabels>0,primaryLabels, ...
    distanceToMedoid,'VariableNames', ...
    {'RequestedFE','RunIndex','Seed','Objective','ObjectiveGap','UniqueNetworkId','NearBest','Family', ...
    'DistanceToFamilyMedoidKm'});
% Reference-free dispersion: all unordered network pairs within EACH budget.
% Pair counts describe dependent distances, not independent statistical samples.
dispersionRows={}; binRows={}; rawFrequency=zeros(18,12,numel(budgets));
latitudeEdges=-90:10:90; longitudeEdges=0:30:360;
for k=1:numel(budgets)
    allRows=find(budget==budgets(k)); states=cell(numel(allRows),1);
    for j=1:numel(allRows)
        coord=r(allRows(j)).locations;
        states{j}=struct("bestSensorLatitudesRad",deg2rad(coord(:,1)), ...
            "bestSensorLongitudesRad",deg2rad(coord(:,2)));
    end
    rawFrequency(:,:,k)=binNetworkSelectionFrequency(states,struct(),latitudeEdges,longitudeEdges);
    for i=1:18
        for j=1:12
            binRows{end+1,1}=struct("RequestedFE",budgets(k),"IndependentRuns",numel(allRows), ...
                "LatitudeLowerDeg",latitudeEdges(i),"LongitudeLowerDeg",longitudeEdges(j), ...
                "SelectionPercent",rawFrequency(i,j,k)); %#ok<AGROW>
        end
    end
    for subset=["all","near_best"]
        selected=allRows; if subset=="near_best", selected=selected(primaryLabels(selected)>0); end
        u=uniqueId(selected); m=meanDistances(u,u); b=bottleneckDistances(u,u);
        mask=triu(true(numel(u)),1); m=m(mask); b=b(mask);
        dispersionRows{end+1,1}=struct("RequestedFE",budgets(k),"Subset",subset, ...
            "IndependentRuns",numel(selected),"DependentPairCount",numel(m), ...
            "MedianMeanMatchedKm",sampleQuantile(m,0.5),"P90MeanMatchedKm",sampleQuantile(m,0.9), ...
            "MedianBottleneckKm",sampleQuantile(b,0.5),"P90BottleneckKm",sampleQuantile(b,0.9)); %#ok<AGROW>
    end
end
% FE budgets use paired seeds. Export paired transitions rather than treating
% the pooled 400 results as 400 independent samples of family probabilities.
transitions=table('Size',[0 6],'VariableTypes',repmat({'double'},1,6),'VariableNames', ...
    {'FromFE','ToFE','Seed','FromFamily','ToFamily','ObjectiveImprovement'});
for k=1:numel(budgets)-1
    a=find(budget==budgets(k)); b=find(budget==budgets(k+1));
    [common,ia,ib]=intersect(seed(a),seed(b)); a=a(ia); b=b(ib);
    transitions=[transitions;table(repmat(budgets(k),numel(common),1),repmat(budgets(k+1),numel(common),1), ...
        common,primaryLabels(a),primaryLabels(b),objective(a)-objective(b), ...
        'VariableNames',transitions.Properties.VariableNames)]; %#ok<AGROW>
end
out=options.OutputDirectory;
if strlength(out)==0, out=fullfile(studyDirectory,"solution_families"); end
if ~isfolder(out), mkdir(out); end
sourceSignature=struct(); manifestFile=fullfile(studyDirectory,"ga_sweep_manifest.mat");
if isfile(manifestFile)
    m=load(manifestFile,"manifest"); sourceSignature=m.manifest.signature;
end
report=struct("version","reference_free_solution_families_v1","options",options,"outputDirectory",out,"studyFile",inputFile, ...
    "studySha256",analysisFileSha256(inputFile),"sourceSignature",sourceSignature, ...
    "observedBestObjective",bestObjective,"bestUniqueNetworkId",bestUnique, ...
    "runs",runs,"families",struct2table(vertcat(familyRows{:})), ...
    "representativeLocations",struct2table(vertcat(coordinateRows{:})), ...
    "frequency",struct2table(vertcat(frequencyRows{:})), ...
    "sensitivity",struct2table(vertcat(scenarios{:})),"scenarioAssignments",assignments, ...
    "pairedTransitions",transitions,"networkIds",networkIds,"networkCoordinates",uniqueCoordinates, ...
    "uniqueObjective",uniqueObjective,"distanceMatrixKm",D, ...
    "meanDistanceMatrixKm",meanDistances,"bottleneckDistanceMatrixKm",bottleneckDistances, ...
    "pairwiseDispersion",struct2table(vertcat(dispersionRows{:})), ...
    "geographicFrequency",struct2table(vertcat(binRows{:})),"frequencyPercent",rawFrequency, ...
    "latitudeEdges",latitudeEdges,"longitudeEdges",longitudeEdges, ...
    "medoidNetworkIds",medoids,"representativeNetworkIds",representatives, ...
    "interpretation","retrospective geometric solution families, not confirmed modes; Family 0 is outside the common score tolerance");
writetable(report.pairwiseDispersion,fullfile(out,"reference_free_dispersion_vs_fe.csv"));
writetable(report.geographicFrequency,fullfile(out,"unlabeled_geographic_frequency.csv"));
writetable(report.runs,fullfile(out,"network_family_assignments.csv"));
writetable(report.families,fullfile(out,"family_summary.csv"));
writetable(report.representativeLocations,fullfile(out,"family_representatives.csv"));
writetable(report.frequency,fullfile(out,"family_frequency_vs_fe.csv"));
writetable(report.sensitivity,fullfile(out,"family_threshold_sensitivity.csv"));
writetable(report.pairedTransitions,fullfile(out,"paired_seed_transitions.csv"));
save(fullfile(out,"solution_family_report.mat"),"report","-v7.3");
if options.MakePlots, plotGaSolutionFamilies(report); end
fprintf("Solution-family report: %d geometric families at gap %.4g and %.1f km.\n%s\n",nf,options.ObjectiveGap,options.DistanceKm,out);
end

function value=sampleQuantile(values,q)
if isempty(values), value=NaN; return; end
values=sort(values); x=1+q*(numel(values)-1);
value=values(floor(x))+(x-floor(x))*(values(ceil(x))-values(floor(x)));
end

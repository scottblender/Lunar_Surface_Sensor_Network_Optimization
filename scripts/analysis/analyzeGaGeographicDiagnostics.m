function report=analyzeGaGeographicDiagnostics(studyDirectory,options)
% ANALYZEGAGEOGRAPHICDIAGNOSTICS - Shape, paired movements and seed bootstrap.
% Saved results only, no reference observers. Complete seed trajectories are
% resampled jointly across FE; pairwise distances are dependent U-statistics.
arguments
    studyDirectory (1,1) string
    options.BootstrapSamples (1,1) double {mustBeInteger,mustBePositive} = 1000
    options.BootstrapSeed (1,1) double {mustBeInteger,mustBeNonnegative} = 314159
    options.RadiusKm (1,1) double {mustBePositive,mustBeFinite} = 1737.4
    options.OutputDirectory (1,1) string = ""
    options.MakePlots (1,1) logical = true
end
assert(options.BootstrapSamples>=20,"geographicDiagnostics:Bootstrap","Use at least 20 bootstrap samples.");
d=loadGeographicSweep(studyDirectory); n=numel(d.seeds); nb=numel(d.budgets);
assert(n>=2,"geographicDiagnostics:Samples","At least two independent seeds are required.");
previous=rng; restore=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(options.BootstrapSeed,'twister'); draws=randi(n,n,options.BootstrapSamples);
shapeRows={}; shapeSummaryRows={}; movementRows={}; movementSummaryRows={};
frequencyRows={}; spreadRows={}; changeRows={};
metrics=zeros(n,n,nb,3); occupancy=false(n,216,nb); edgesLat=-90:10:90; edgesLon=0:30:360;
for b=1:nb
    rows=d.index(:,b);
    for i=1:n
        k=rows(i); a=d.shapeAnglesDeg(k,:);
        shapeRows{end+1,1}=struct("RequestedFE",d.budgets(b),"Seed",d.seeds(i), ...
            "ShortestSideDeg",a(1),"MiddleSideDeg",a(2),"LongestSideDeg",a(3)); %#ok<AGROW>
        coords=d.coordinates(:,:,k);
        state=struct("bestSensorLatitudesRad",deg2rad(coords(:,1)),"bestSensorLongitudesRad",deg2rad(coords(:,2)));
        f=binNetworkSelectionFrequency({state},struct(),edgesLat,edgesLon);
        occupancy(i,:,b)=f(:).'>0;
        for j=i+1:n
            [~,meanDistance]=matchThreeObserverLocations(coords,d.coordinates(:,:,rows(j)),options.RadiusKm);
            [~,maxDistance]=matchThreeObserverLocations(coords,d.coordinates(:,:,rows(j)),options.RadiusKm,"max");
            metrics(i,j,b,1)=mean(meanDistance); metrics(j,i,b,1)=metrics(i,j,b,1);
            metrics(i,j,b,2)=max(maxDistance); metrics(j,i,b,2)=metrics(i,j,b,2);
            metrics(i,j,b,3)=max(abs(a-d.shapeAnglesDeg(rows(j),:))); metrics(j,i,b,3)=metrics(i,j,b,3);
        end
    end
    for side=1:3
        q=diagnosticQuantile(d.shapeAnglesDeg(rows,side),[.1 .5 .9]);
        shapeSummaryRows{end+1,1}=struct("RequestedFE",d.budgets(b),"SortedSide",side, ...
            "P10Deg",q(1),"MedianDeg",q(2),"P90Deg",q(3)); %#ok<AGROW>
    end
end
for b=1:nb-1
    stepMean=zeros(n,1); stepMax=zeros(n,1); changed=false(n,1); gain=zeros(n,1);
    for i=1:n
        a=d.index(i,b); z=d.index(i,b+1); changed(i)=~isequal(d.ids(a,:),d.ids(z,:));
        gain(i)=d.objective(a)-d.objective(z);
        if changed(i)
            [~,x]=matchThreeObserverLocations(d.coordinates(:,:,a),d.coordinates(:,:,z),options.RadiusKm);
            [~,y]=matchThreeObserverLocations(d.coordinates(:,:,a),d.coordinates(:,:,z),options.RadiusKm,"max");
            stepMean(i)=mean(x); stepMax(i)=max(y);
        end
        movementRows{end+1,1}=struct("FromFE",d.budgets(b),"ToFE",d.budgets(b+1),"Seed",d.seeds(i), ...
            "ChangedCandidateNetwork",changed(i),"MeanMatchedMovementKm",stepMean(i), ...
            "BottleneckMovementKm",stepMax(i),"ObjectiveImprovement",gain(i), ...
            "ShapeChangeDeg",max(abs(d.shapeAnglesDeg(a,:)-d.shapeAnglesDeg(z,:)))); %#ok<AGROW>
    end
    changedMedian=NaN; if any(changed), changedMedian=median(stepMean(changed)); end
    movementSummaryRows{end+1,1}=struct("FromFE",d.budgets(b),"ToFE",d.budgets(b+1), ...
        "IndependentSeeds",n,"UnchangedNetworks",nnz(~changed),"ChangedNetworks",nnz(changed), ...
        "ImprovedRuns",nnz(gain>1e-9),"WorsenedRuns",nnz(gain< -1e-9), ...
        "MedianMeanMovementKm",median(stepMean),"P90MeanMovementKm",diagnosticQuantile(stepMean,.9), ...
        "MedianMeanMovementChangedOnlyKm",changedMedian,"MedianObjectiveImprovement",median(gain)); %#ok<AGROW>
end
mask=triu(true(n),1); bootSpread=zeros(options.BootstrapSamples,nb,3);
bootOccupancy=zeros(options.BootstrapSamples,216,nb);
for sample=1:options.BootstrapSamples
    rows=draws(:,sample);
    for b=1:nb
        bootOccupancy(sample,:,b)=100*mean(occupancy(rows,:,b),1);
        for metric=1:3
            matrix=metrics(rows,rows,b,metric); bootSpread(sample,b,metric)=median(matrix(mask));
        end
    end
end
names=["MeanMatchedKm","BottleneckKm","MaxShapeSideChangeDeg"];
for b=1:nb
    for metric=1:3
        matrix=metrics(:,:,b,metric); values=matrix(mask); ci=diagnosticQuantile(bootSpread(:,b,metric),[.025 .975]);
        deltaCI=diagnosticQuantile(bootSpread(:,b,metric)-bootSpread(:,1,metric),[.025 .975]);
        base=metrics(:,:,1,metric); base=median(base(mask));
        spreadRows{end+1,1}=struct("RequestedFE",d.budgets(b),"Metric",names(metric), ...
            "IndependentSeeds",n,"DependentPairs",numel(values),"Median",median(values), ...
            "P90",diagnosticQuantile(values,.9),"BootstrapLower95",ci(1),"BootstrapUpper95",ci(2), ...
            "MedianChangeFromFirstFE",median(values)-base,"PairedChangeLower95",deltaCI(1),"PairedChangeUpper95",deltaCI(2)); %#ok<AGROW>
    end
    count=sum(occupancy(:,:,b),1); p=count/n; z=1.959963984540054;
    center=(p+z^2/(2*n))/(1+z^2/n); half=z*sqrt(p.*(1-p)/n+z^2/(4*n^2))/(1+z^2/n);
    limits=diagnosticQuantile(bootOccupancy(:,:,b),[.025 .975]);
    deltaLimits=diagnosticQuantile(bootOccupancy(:,:,b)-bootOccupancy(:,:,1),[.025 .975]);
    [ilat,ilon]=ind2sub([18 12],1:216);
    for bin=1:216
        frequencyRows{end+1,1}=struct("RequestedFE",d.budgets(b),"LatitudeLowerDeg",edgesLat(ilat(bin)), ...
            "LongitudeLowerDeg",edgesLon(ilon(bin)),"IndependentSeeds",n,"RunsSelectingBin",count(bin), ...
            "SelectionPercent",100*p(bin),"BootstrapLower95",limits(1,bin),"BootstrapUpper95",limits(2,bin), ...
            "WilsonLower95",100*max(0,center(bin)-half(bin)),"WilsonUpper95",100*min(1,center(bin)+half(bin))); %#ok<AGROW>
        changeRows{end+1,1}=struct("RequestedFE",d.budgets(b),"LatitudeLowerDeg",edgesLat(ilat(bin)), ...
            "LongitudeLowerDeg",edgesLon(ilon(bin)),"ChangeFromFirstFEPercent", ...
            100*mean(occupancy(:,bin,b)-double(occupancy(:,bin,1))), ...
            "PairedBootstrapLower95",deltaLimits(1,bin),"PairedBootstrapUpper95",deltaLimits(2,bin)); %#ok<AGROW>
    end
end
out=options.OutputDirectory; if strlength(out)==0, out=fullfile(studyDirectory,"geographic_diagnostics"); end
if ~isfolder(out), mkdir(out); end
movement=table(); movementSummary=table();
if ~isempty(movementRows), movement=struct2table(vertcat(movementRows{:})); movementSummary=struct2table(vertcat(movementSummaryRows{:})); end
report=struct("version","geographic_diagnostics_v1","options",options,"studySha256",d.studySha256, ...
    "budgets",d.budgets,"seeds",d.seeds,"shape",struct2table(vertcat(shapeRows{:})), ...
    "shapeSummary",struct2table(vertcat(shapeSummaryRows{:})),"movement",movement,"movementSummary",movementSummary, ...
    "spread",struct2table(vertcat(spreadRows{:})),"frequency",struct2table(vertcat(frequencyRows{:})), ...
    "frequencyChanges",struct2table(vertcat(changeRows{:})),"bootstrapSeedRows",draws, ...
    "outputDirectory",out,"interpretation", ...
    "seed-level pointwise bootstrap uncertainty conditional on fixed model; pair distances are dependent; shape signatures also ignore reflection");
for field=["shape","shapeSummary","movement","movementSummary","spread","frequency","frequencyChanges"]
    if ~isempty(report.(field)), writetable(report.(field),fullfile(out,field+".csv")); end
end
save(fullfile(out,"geographic_diagnostics.mat"),"report","-v7.3");
if options.MakePlots, plotGaGeographicDiagnostics(report); end
fprintf("Saved shape, paired movement and seed bootstrap diagnostics: %s\n",out);
end

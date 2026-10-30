function analysis = analyzeGaLocationConvergence(records,runCounts,radiusKm)
% ANALYZEGALOCATIONCONVERGENCE - Align observers to one empirical reference network.
% The reference is the location medoid among runs at the largest requested FE
% budget, not a known optimum. Every prefix/budget uses that same reference.
arguments
    records (:,1) struct
    runCounts (1,:) double {mustBeInteger,mustBePositive}
    radiusKm (1,1) double {mustBePositive} = 1737.4
end
budgets=sort(unique([records.requestedBudget]));
referenceRuns=find([records.requestedBudget]==max(budgets));
[~,sorted]=sort([records(referenceRuns).runIndex]); referenceRuns=referenceRuns(sorted);
totals=zeros(numel(referenceRuns),1);
for i=1:numel(referenceRuns)
    for j=i+1:numel(referenceRuns)
        [~,d]=matchThreeObserverLocations(records(referenceRuns(i)).locations,records(referenceRuns(j)).locations,radiusKm);
        totals(i)=totals(i)+mean(d); totals(j)=totals(j)+mean(d);
    end
end
[~,chosen]=min(totals); referenceIndex=referenceRuns(chosen);
[reference,order]=sortrows(records(referenceIndex).locations,[1 2]);
referenceIds=records(referenceIndex).candidateIds(order);
aligned=records; rows=struct([]); summary=struct([]);
for k=1:numel(records)
    [order,d]=matchThreeObserverLocations(reference,records(k).locations,radiusKm);
    aligned(k).locations=records(k).locations(order,:);
    aligned(k).candidateIds=records(k).candidateIds(order);
    aligned(k).distanceKm=d;
    for observer=1:3
        rows(end+1)=struct("RequestedFE",records(k).requestedBudget,"RunIndex",records(k).runIndex, ...
            "Seed",records(k).seed,"Observer",observer,"CandidateId",aligned(k).candidateIds(observer), ...
            "LatitudeDeg",aligned(k).locations(observer,1),"LongitudeDeg",mod(aligned(k).locations(observer,2),360), ...
            "DistanceFromReferenceKm",d(observer)); %#ok<AGROW>
    end
end
for budget=budgets
    for count=runCounts
        ids=find([aligned.requestedBudget]==budget & [aligned.runIndex]<=count);
        assert(numel(ids)==count,"analyzeGaLocationConvergence:MissingRuns","Incomplete independent-run prefix.");
        for observer=1:3
            d=arrayfun(@(r)r.distanceKm(observer),aligned(ids));
            siteIds=arrayfun(@(r)r.candidateIds(observer),aligned(ids));
            summary(end+1)=struct("RequestedFE",budget,"IndependentRuns",count,"Observer",observer, ...
                "MedianDistanceKm",median(d),"P90DistanceKm",percentile90(d), ...
                "MaximumDistanceKm",max(d),"SameCandidateFraction",mean(siteIds==referenceIds(observer))); %#ok<AGROW>
        end
    end
end
analysis=struct("reference",reference,"referenceCandidateIds",referenceIds, ...
    "referenceSeed",records(referenceIndex).seed,"referenceRequestedFE",max(budgets), ...
    "referenceRule","location medoid at largest requested FE; labels sorted by latitude then longitude", ...
    "alignedRecords",aligned,"locations",struct2table(rows),"summary",struct2table(summary));
end
function value=percentile90(values)
values=sort(values(:)); x=1+0.9*(numel(values)-1);
value=values(floor(x))+(x-floor(x))*(values(ceil(x))-values(floor(x)));
end

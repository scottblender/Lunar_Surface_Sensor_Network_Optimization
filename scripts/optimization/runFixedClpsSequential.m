function result = runFixedClpsSequential(database,sideOrder)
% RUNFIXEDCLPSSEQUENTIAL - Greedily select three fixed sites in an explicit side order.
% sideOrder contains three entries, "nearside" or "farside", including both.
% Ties use the smallest candidate ID. This is sequential selection, not a
% guarantee of the best jointly selected three-site network.
arguments
    database (1,1) struct
    sideOrder (1,3) string {mustBeMember(sideOrder,["nearside","farside"])}
end
assert(all(ismember(["nearside","farside"],sideOrder)), ...
    "runFixedClpsSequential:SideOrder","Specify a sequence containing both sides.");
assert(database.config.domainComparison.domain == "clps_fixed", ...
    "runFixedClpsSequential:Domain","Use a clps_fixed database, not neighborhood candidates.");
longitude = mod(database.candidates.longitudesRad(:)+pi,2*pi)-pi;
sides = repmat("farside",numel(longitude),1);
sides(abs(longitude)<=pi/2) = "nearside";
for side = ["nearside","farside"]
    assert(nnz(sides==side)>=nnz(sideOrder==side), ...
        "runFixedClpsSequential:InsufficientSites", ...
        "Enabled retained CLPS sites cannot support the requested %s stages.",side);
end
selected = zeros(0,1);
result.stageObjectives = nan(3,1);
result.stageCandidateIds = cell(3,1);
result.stageCandidateObjectives = cell(3,1);
for stage = 1:3
    ids = find(sides==sideOrder(stage) & ~ismember((1:numel(sides)).',selected));
    values = nan(numel(ids),1);
    for k = 1:numel(ids)
        values(k) = optimization.networkObjective([selected;ids(k)],database,"information");
    end
    [value,best] = min(values);
    assert(isfinite(value) && value<database.objective.infeasiblePenalty, ...
        "runFixedClpsSequential:NoFeasibleSite","No feasible site at stage %d.",stage);
    selected(end+1,1) = ids(best); %#ok<AGROW>
    result.stageObjectives(stage) = value;
    result.stageCandidateIds{stage} = ids;
    result.stageCandidateObjectives{stage} = values;
end
result.selectionOrder = selected;
result.sensorIndices = sort(selected);
result.sideOrder = sideOrder;
[result.objective,result.diagnostics] = optimization.networkObjective(result.sensorIndices,database,"information");
end

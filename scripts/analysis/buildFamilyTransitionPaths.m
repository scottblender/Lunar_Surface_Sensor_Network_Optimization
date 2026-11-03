function paths=buildFamilyTransitionPaths(report,database,maxFamilies,points)
% BUILDFAMILYTRANSITIONPATHS - Sample matched great-circle paths on the grid.
% Nearest candidates use true spherical distance. Duplicate-site intermediate
% networks are marked invalid, never repaired into a different path or scored
% as a large penalty. Chosen paths do not establish global basin separation.
arguments
    report (1,1) struct
    database (1,1) struct
    maxFamilies (1,1) double {mustBeInteger,mustBePositive} = 4
    points (1,1) double {mustBeInteger,mustBePositive} = 21
end
assert(points>=3,"networkFamilies:PathPoints","Use at least three path points.");
freq=report.frequency; final=freq(freq.RequestedFE==max(freq.RequestedFE)&freq.Family>0&freq.RunCount>0,:);
final=sortrows(final,{'RunCount','Family'},{'descend','ascend'});
families=final.Family(1:min(maxFamilies,height(final)));
lat=double(database.candidates.latitudesRad(:)); lon=double(database.candidates.longitudesRad(:));
xyz=[cos(lat).*cos(lon),cos(lat).*sin(lon),sin(lat)]; rows={}; pair=0;
for i=1:numel(families)
    for j=i+1:numel(families)
        pair=pair+1; a=families(i); b=families(j);
        ua=report.representativeNetworkIds(a); ub=report.representativeNetworkIds(b);
        first=report.networkCoordinates(:,:,ua); last=report.networkCoordinates(:,:,ub);
        metric="mean"; if isfield(report.options,"DistanceMetric"), metric=report.options.DistanceMetric; end
        [order,~]=matchThreeObserverLocations(first,last,report.options.RadiusKm,metric);
        firstIds=report.networkIds(ua,:); lastIds=report.networkIds(ub,order);
        source=xyz(firstIds,:); target=xyz(lastIds,:);
        angles=acos(max(-1,min(1,sum(source.*target,2))));
        assert(all(angles<pi-1e-8),"networkFamilies:Antipodal", ...
            "An antipodal sensor pair has no unique shortest arc; choose another representative path.");
        for alpha=linspace(0,1,points)
            position=zeros(3,3);
            for sensor=1:3
                if angles(sensor)<1e-10
                    position(sensor,:)=source(sensor,:);
                else
                    theta=angles(sensor);
                    position(sensor,:)=(sin((1-alpha)*theta)*source(sensor,:)+sin(alpha*theta)*target(sensor,:))/sin(theta);
                end
            end
            position=position./vecnorm(position,2,2);
            [dots,ids]=max(xyz*position.',[],1);
            if alpha==0, ids=firstIds; elseif alpha==1, ids=lastIds; end
            valid=numel(unique(ids))==3;
            rows{end+1,1}=struct("Pair",pair,"FromFamily",a,"ToFamily",b,"Fraction",alpha, ...
                "Candidate1",ids(1),"Candidate2",ids(2),"Candidate3",ids(3), ...
                "ValidDistinctSites",valid, ...
                "MaxSnapDistanceKm",report.options.RadiusKm*max(acos(max(-1,min(1,dots)))), ...
                "FromSavedObjective",report.uniqueObjective(ua),"ToSavedObjective",report.uniqueObjective(ub)); %#ok<AGROW>
        end
    end
end
if isempty(rows)
    paths=table('Size',[0 12],'VariableTypes',[repmat({'double'},1,7),{'logical'},repmat({'double'},1,4)], ...
        'VariableNames',{'Pair','FromFamily','ToFamily','Fraction','Candidate1','Candidate2','Candidate3', ...
        'ValidDistinctSites','MaxSnapDistanceKm','FromSavedObjective','ToSavedObjective','Objective'});
else
    paths=struct2table(vertcat(rows{:})); paths.Objective=NaN(height(paths),1);
end
end

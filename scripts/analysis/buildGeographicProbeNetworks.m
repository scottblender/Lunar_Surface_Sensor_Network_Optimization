function [probes,contexts,joint]=buildGeographicProbeNetworks(representatives,database,options)
% BUILDGEOGRAPHICPROBENETWORKS - Frozen-grid global/local conditional probes.
% Representatives contain Ids (N x 3). MovingSlot is a contextual slot, never an
% identity assigned across independent networks. Same global sample everywhere.
arguments
    representatives (1,1) struct
    database (1,1) struct
    options.GlobalSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
    options.LocalSamples (1,1) double {mustBeInteger,mustBeNonnegative} = 1000
    options.LocalRadiusKm (1,1) double {mustBePositive,mustBeFinite} = 250
    options.ProbeSeed (1,1) double {mustBeInteger,mustBeNonnegative} = 271828
    options.JointSamplesPerSite (1,1) double {mustBeInteger,mustBeNonnegative} = 0
end
previous=rng; restore=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(options.ProbeSeed,'twister'); n=database.meta.numberOfCandidates;
globalIds=randperm(n,min(options.GlobalSamples,n)).';
lat=double(database.candidates.latitudesRad(:)); lon=double(database.candidates.longitudesRad(:));
radius=database.config.moon.radiusKm; rows={}; contextRows={}; jointRows={}; context=0;
for rep=1:size(representatives.Ids,1)
    ids=representatives.Ids(rep,:); localSets=cell(3,1);
    for slot=1:3
        context=context+1; site=ids(slot); held=ids(setdiff(1:3,slot));
        h=sin((lat-lat(site))/2).^2+cos(lat).*cos(lat(site)).*sin((lon-lon(site))/2).^2;
        distance=2*radius*asin(sqrt(min(1,max(0,h))));
        pool=find(distance<=options.LocalRadiusKm); sampleCount=min(options.LocalSamples,numel(pool));
        localIds=pool(randperm(numel(pool),sampleCount));
        candidates=unique([globalIds;localIds;site]); candidates=candidates(~ismember(candidates,held));
        [~,nearOrder]=sortrows([distance (1:n).'],[1 2]);
        localSets{slot}=nearOrder(distance(nearOrder)<=options.LocalRadiusKm & ~ismember(nearOrder,held));
        localSets{slot}=unique([site;localSets{slot}],'stable');
        contextRows{end+1,1}=struct("Context",context,"Representative",rep,"MovingSlot",slot, ...
            "OriginalCandidateId",site,"HeldCandidate1",held(1),"HeldCandidate2",held(2), ...
            "OriginalLatitudeDeg",rad2deg(lat(site)),"OriginalLongitudeDeg",mod(rad2deg(lon(site)),360), ...
            "Held1LatitudeDeg",rad2deg(lat(held(1))),"Held1LongitudeDeg",mod(rad2deg(lon(held(1))),360), ...
            "Held2LatitudeDeg",rad2deg(lat(held(2))),"Held2LongitudeDeg",mod(rad2deg(lon(held(2))),360)); %#ok<AGROW>
        for candidate=candidates.'
            network=ids; network(slot)=candidate;
            rows{end+1,1}=struct("Context",context,"Representative",rep,"MovingSlot",slot,"ProbeCandidateId",candidate, ...
                "LatitudeDeg",rad2deg(lat(candidate)),"LongitudeDeg",mod(rad2deg(lon(candidate)),360), ...
                "DistanceFromOriginalKm",distance(candidate),"GlobalSample",ismember(candidate,globalIds), ...
                "LocalSample",ismember(candidate,localIds),"IsOriginal",candidate==site, ...
                "Candidate1",network(1),"Candidate2",network(2),"Candidate3",network(3)); %#ok<AGROW>
        end
    end
    % Optional coordinated movement of two sites: nearest frozen candidates,
    % not score-selected probes. The third site remains fixed.
    if options.JointSamplesPerSite>0
        a=localSets{1}(1:min(options.JointSamplesPerSite,numel(localSets{1})));
        b=localSets{2}(1:min(options.JointSamplesPerSite,numel(localSets{2})));
        for i=1:numel(a)
            for j=1:numel(b)
                network=[a(i),b(j),ids(3)];
                jointRows{end+1,1}=struct("Representative",rep,"FirstProbeIndex",i,"SecondProbeIndex",j, ...
                    "Candidate1",network(1),"Candidate2",network(2),"Candidate3",network(3), ...
                    "ValidDistinctSites",numel(unique(network))==3); %#ok<AGROW>
            end
        end
    end
end
probes=struct2table(vertcat(rows{:})); contexts=struct2table(vertcat(contextRows{:}));
joint=table(); if ~isempty(jointRows), joint=struct2table(vertcat(jointRows{:})); end
end

function [views,report] = derivePaperDomains(shared)
% DERIVEPAPERDOMAINS - Reuse one physical database and choose a visibility proxy.
assert(shared.config.domainComparison.domain=="paper_shared", ...
    "derivePaperDomains:Domain","Supply the paper_shared master manifest.");
sites=shared.config.domainComparison.sites;
lat=shared.candidates.latitudesRad(:); lon=shared.candidates.longitudesRad(:);
dist=zeros(numel(lat),height(sites));
for k=1:height(sites)
    a=sin((lat-deg2rad(sites.LatitudeDeg(k)))/2).^2 + ...
        cos(lat).*cosd(sites.LatitudeDeg(k)).*sin((lon-deg2rad(sites.LongitudeDeg(k)))/2).^2;
    dist(:,k)=2*shared.config.moon.radiusKm*asin(sqrt(min(1,max(0,a))));
end
[nearest,anchorIds]=min(dist,[],1);
assert(all(nearest<1e-6),"derivePaperDomains:MissingAnchor", ...
    "Exact anchors were removed or are missing. Build paper_shared with candidate filtering disabled.");
options=find(sites.Role=="south_pole_option");
scores=zeros(numel(options),1);
for k=1:numel(options)
    id=anchorIds(options(k));
    if isfield(shared.visibility,"candidateChunks") && ~isempty(shared.visibility.candidateChunks)
        available=optimization.loadChunkedCandidateData(shared,double(id),"filteredAvailability");
    else
        available=shared.visibility.filteredAvailability(id,:,:);
    end
    scores(k)=nnz(available);
end
% Same terrain/bright-body gates, population and epochs for both proxies.
% Ties use CSV order, documented in the report rather than hidden randomness.
[~,winner]=max(scores);
selectedPole=options(winner);
active=sites.Role=="anchor"; active(selectedPole)=true;
activeSites=sites(active,:);
membership=dist(:,active)<=100+1e-8;
fixedIds=unique(anchorIds(active).',"stable");
views.clps_fixed=optimization.createPaperDomainView(shared,fixedIds,"clps_fixed",membership,activeSites);
views.clps=optimization.createPaperDomainView(shared,find(any(membership,2)),"clps",membership,activeSites);
views.global=optimization.createPaperDomainView(shared,(1:numel(lat)).',"global",membership,activeSites);
report=struct("selectedSiteId",sites.SiteId(selectedPole), ...
    "criterion","maximum accepted sensor-object-epochs at exact proxy; ties use CSV order", ...
    "comparison",table(sites.SiteId(options),sites.LatitudeDeg(options),sites.LongitudeDeg(options),scores, ...
    'VariableNames',{'SiteId','LatitudeDeg','LongitudeDeg','AcceptedSensorObjectEpochs'}), ...
    "activeSites",activeSites,"anchorMasterIds",anchorIds(active).', ...
    "assumption","regional polar study proxies, not certified or mission-specific landing sites");
end

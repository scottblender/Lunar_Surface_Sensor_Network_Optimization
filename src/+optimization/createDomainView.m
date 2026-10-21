function database = createDomainView(shared,indices,domain)
% CREATEDOMAINVIEW - Restrict candidate IDs while sharing immutable on-disk chunks.
indices = indices(:);
assert(~isempty(indices) && all(indices>=1 & indices<=shared.meta.numberOfCandidates), ...
    "createDomainView:Empty","Domain has no retained candidates or invalid IDs.");
database = shared;
n = shared.meta.numberOfCandidates;
fields = fieldnames(shared.candidates);
for k = 1:numel(fields)
    value = shared.candidates.(fields{k});
    if ~isstruct(value) && size(value,1)==n
        database.candidates.(fields{k}) = value(indices,:);
    end
end
lat = shared.candidates.prefilter.latitudesRad;
site = shared.config.domainComparison.prefilterSiteIds;
mask = strlength(site)==0;
if domain == "clps", mask = strlength(site)>0; end
if domain == "south75", mask = mask & lat<=deg2rad(-75); end
if domain == "south0", mask = mask & lat<=0; end
mapping = zeros(numel(mask),1,"uint32");
mapping(mask) = uint32(1:nnz(mask));
database.candidates.originalIndices = mapping(shared.candidates.originalIndices(indices));
assert(all(database.candidates.originalIndices>0),"createDomainView:Membership","IDs do not belong to domain.");
fields = fieldnames(shared.candidates.prefilter);
for k = 1:numel(fields)
    value = shared.candidates.prefilter.(fields{k});
    if size(value,1)==numel(mask), database.candidates.prefilter.(fields{k}) = value(mask,:); end
end
database.meta.numberOfCandidates = numel(indices);
database.meta.numberOfCandidatesBeforeFiltering = nnz(mask);
database.meta.sharedSourceFile = string(shared.config.outputFile);
database.meta.sharedSourceCandidateIds = indices;
database.config.domainComparison.domain = domain;
if domain == "south75", database.config.candidates.latitudeBandRad = deg2rad([-90 -75]); end
if domain == "south0", database.config.candidates.latitudeBandRad = deg2rad([-90 0]); end
if domain == "global", database.config.candidates.latitudeBandRad = deg2rad([-90 90]); end
database.config.domainComparison.enforceSiteGroups = domain == "clps";
database.config.domainComparison.prefilterSiteIds = site(mask);
database.config.candidates.customLatitudesRad = lat(mask);
database.config.candidates.customLongitudesRad = shared.candidates.prefilter.longitudesRad(mask);
if isfield(shared.config.domainComparison,"localFlatness")
    report = shared.config.domainComparison.localFlatness;
    if ~isempty(report)
        report = report(mask(report.prefilterCandidateIndex),:);
        report.prefilterCandidateIndex = double(mapping(report.prefilterCandidateIndex));
    end
    database.config.domainComparison.localFlatness = report;
end
if domain == "clps"
    database.study.networkSizes = shared.study.networkSizes(shared.study.networkSizes<=height(shared.config.domainComparison.sites));
end
database.config.study.networkSizes = database.study.networkSizes;
if isfield(shared,"measurement") && size(shared.measurement.covariance,3)==n
    database.measurement.covariance = shared.measurement.covariance(:,:,indices);
end
summary = shared.visibility.summary;
if isfield(summary,"acceptedByCandidateObject")
    summary.acceptedByCandidateObject = summary.acceptedByCandidateObject(indices,:);
    summary.acceptedByObject = sum(summary.acceptedByCandidateObject,1).';
    summary.totalAccepted = sum(summary.acceptedByObject);
end
database.visibility.summary = summary;
end

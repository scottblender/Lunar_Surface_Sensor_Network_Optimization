function view = createPaperDomainView(shared,ids,domain,membership,sites)
% CREATEPAPERDOMAINVIEW - Slice candidate metadata; retain shared physical IDs/chunks.
ids = ids(:); n = shared.meta.numberOfCandidates;
assert(~isempty(ids) && numel(unique(ids))==numel(ids) && all(ids>=1 & ids<=n), ...
    "createPaperDomainView:Ids","Invalid or empty domain.");
view = shared;
fields = fieldnames(shared.candidates);
for k=1:numel(fields)
    value = shared.candidates.(fields{k});
    if ~isstruct(value) && size(value,1)==n, view.candidates.(fields{k})=value(ids,:); end
end
view.meta.numberOfCandidates = numel(ids);
view.meta.sharedSourceCandidateIds = ids;
view.meta.sharedSourceFile = string(shared.config.outputFile);
view.config.domainComparison.domain = domain;
view.config.domainComparison.enforceSiteGroups = domain=="clps";
view.config.domainComparison.anchorMembership = membership(ids,:);
view.config.domainComparison.activeSites = sites;
if isfield(shared.visibility,"filteredAvailability") && ~isempty(shared.visibility.filteredAvailability)
    view.visibility.filteredAvailability = shared.visibility.filteredAvailability(ids,:,:);
end
if isfield(shared.tracking,"measurementJacobianHistories") && ~isempty(shared.tracking.measurementJacobianHistories)
    view.tracking.measurementJacobianHistories = shared.tracking.measurementJacobianHistories(:,:,ids,:,:);
end
if isfield(shared,"measurement") && size(shared.measurement.covariance,3)==n
    view.measurement.covariance=shared.measurement.covariance(:,:,ids);
end
if isfield(shared.visibility,"summary") && isfield(shared.visibility.summary,"acceptedByCandidateObject")
    counts=shared.visibility.summary.acceptedByCandidateObject(ids,:);
    view.visibility.summary.acceptedByCandidateObject=counts;
    view.visibility.summary.acceptedByObject=sum(counts,1).';
    view.visibility.summary.totalAccepted=sum(counts,"all");
end
view.study.objectiveModes="information";
if domain=="clps_fixed", view.study.networkSizes=3; end
if domain=="clps", view.study.networkSizes=3; end
end

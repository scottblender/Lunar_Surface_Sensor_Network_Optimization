function plan = planPaperDatabase(userOptions)
% PLANPAPERDATABASE - One global discrete grid augmented by exact CLPS anchors.
arguments
    userOptions (1,1) struct = struct()
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
defaults = struct("siteFile",string(fullfile(root,"config","paper_clps_sites.csv")), ...
    "clpsRadiusKm",100,"requestedDomains",["clps","global"]);
options = utilities.overrideConfig(defaults,userOptions);
assert(options.clpsRadiusKm==100,"planPaperDatabase:Radius","Paper circles have a 100-km radius.");
plan = planDomainDatabase("global",options);
sites = readtable(options.siteFile,"TextType","string");
required = ["SiteId","LatitudeDeg","LongitudeDeg","Enabled","CoordinateType","Role","SourceURL"];
assert(all(ismember(required,string(sites.Properties.VariableNames))),"planPaperDatabase:Schema","Missing paper site metadata.");
sites = sites(sites.Enabled==1,:);
assert(numel(unique(sites.SiteId))==height(sites) && height(sites)>=3, ...
    "planPaperDatabase:Sites","Supply at least three unique enabled anchors.");
assert(all(isfinite(sites.LatitudeDeg) & abs(sites.LatitudeDeg)<=90 & ...
    isfinite(sites.LongitudeDeg) & abs(sites.LongitudeDeg)<=360), ...
    "planPaperDatabase:Coordinates","Invalid enabled coordinates.");
assert(all(ismember(sites.Role,["anchor","south_pole_option"])) && ...
    nnz(sites.Role=="south_pole_option")==2 && all(strlength(sites.SourceURL)>0), ...
    "planPaperDatabase:Roles","Provide sourced anchors and exactly two polar options.");
lat = [plan.latitudesRad;deg2rad(sites.LatitudeDeg)];
lon = mod([plan.longitudesRad;deg2rad(sites.LongitudeDeg)],2*pi);
% Cartesian keys deduplicate poles and longitude seams as well as exact anchors.
keys = round([cos(lat).*cos(lon),cos(lat).*sin(lon),sin(lat)],12);
[~,keep] = unique(keys,"rows","stable");
plan.latitudesRad = lat(keep); plan.longitudesRad = lon(keep);
plan.domain = "paper_shared";
plan.sites = sites;
plan.siteIds = repmat("",numel(keep),1);
plan.numberOfCandidates = numel(keep);
plan.numberOfChunks = max(1,ceil(numel(keep)/plan.options.maximumCandidatesPerChunk));
% All candidates, including zero-visibility sites, remain in the global benchmark.
plan.legacyJacobianDiskGiB = 12*8*numel(keep)*432*20/2^30;
plan.estimatedVisibilityDiskGiB = numel(keep)*432*20/2^30;
plan.estimatedTerrainDiskGiB = numel(keep)*3601*8/2^30;
plan.estimatedJacobianDiskGiB = 0;
if plan.options.jacobianStorage=="full", plan.estimatedJacobianDiskGiB=plan.legacyJacobianDiskGiB; end
if plan.options.jacobianStorage=="position", plan.estimatedJacobianDiskGiB=plan.legacyJacobianDiskGiB/2; end
end

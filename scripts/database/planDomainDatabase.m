function plan = planDomainDatabase(domain,userOptions)
% PLANDOMAINDATABASE - Plan nested geographic grids or CLPS neighborhoods without loading a DEM.
% Outputs include prefilter candidate-to-site IDs and bounded equal-count chunks.
arguments
    domain (1,1) string {mustBeMember(domain,["clps","south75","south0","global","shared"])}
    userOptions (1,1) struct = struct()
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
defaults = struct("spacingKm",15,"maximumCandidatesPerChunk",500, ...
    "clpsRadiusKm",0.1,"clpsSpacingKm",0.025, ...
    "siteFile",string(fullfile(root,"config","clps_sites.csv")), ...
    "seed",1000,"networkSizes",3,"jacobianStorage","on_demand", ...
    "requestedDomains",["clps","south75","south0","global"]);
options = utilities.overrideConfig(defaults,userOptions);
validateattributes(options.spacingKm,{'numeric'},{'scalar','positive','finite'});
validateattributes(options.maximumCandidatesPerChunk,{'numeric'}, ...
    {'scalar','integer','positive','finite'});
validateattributes(options.clpsRadiusKm,{'numeric'},{'scalar','positive','finite','<=',0.1});
validateattributes(options.clpsSpacingKm,{'numeric'},{'scalar','positive','finite'});
validateattributes(options.seed,{'numeric'},{'scalar','integer','nonnegative','<=',2^32-1});
validateattributes(options.networkSizes,{'numeric'},{'vector','integer','positive','finite'});
moonRadiusKm = 1737.4;
siteIds = strings(0,1);
sites = table();
if domain == "clps"
    sites = readtable(options.siteFile,"TextType","string");
    required = ["SiteId","Mission","LatitudeDeg","LongitudeDeg","Enabled","CoordinateType","SourceURL"];
    assert(all(ismember(required,string(sites.Properties.VariableNames))), ...
        "planDomainDatabase:SiteSchema","CLPS CSV is missing required columns.");
    assert(all(ismember(sites.Enabled,[0 1])), ...
        "planDomainDatabase:Enabled","Enabled must contain only 0 or 1.");
    sites = sites(sites.Enabled == 1,:);
    assert(~isempty(sites),"planDomainDatabase:NoSites","Enable at least one CLPS site.");
    assert(numel(unique(sites.SiteId)) == height(sites), ...
        "planDomainDatabase:DuplicateSite","Enabled SiteId values must be unique.");
    assert(all(isfinite(sites.LatitudeDeg) & abs(sites.LatitudeDeg)<=90 & ...
        isfinite(sites.LongitudeDeg) & abs(sites.LongitudeDeg)<=360), ...
        "planDomainDatabase:Coordinates","Enabled sites require finite valid coordinates.");
    assert(~any(ismember(sites.CoordinateType,["unresolved","no_landing"])), ...
        "planDomainDatabase:Unresolved","Unresolved/nonlanding sites cannot be enabled.");
    lat = []; lon = [];
    radii = (options.clpsSpacingKm:options.clpsSpacingKm:options.clpsRadiusKm).';
    radii = unique([radii;options.clpsRadiusKm]);
    for k = 1:height(sites)
        centerLat = deg2rad(sites.LatitudeDeg(k));
        centerLon = deg2rad(sites.LongitudeDeg(k));
        localLat = centerLat; localLon = mod(centerLon,2*pi);
        for r = radii.'
            bearings = (0:max(7,ceil(2*pi*r/options.clpsSpacingKm))-1).';
            bearings = bearings*2*pi/numel(bearings);
            delta = r/moonRadiusKm;
            ringLat = asin(sin(centerLat)*cos(delta) + cos(centerLat)*sin(delta)*cos(bearings));
            ringLon = centerLon + atan2(sin(bearings)*sin(delta)*cos(centerLat), ...
                cos(delta)-sin(centerLat)*sin(ringLat));
            localLat = [localLat;ringLat]; %#ok<AGROW>
            localLon = [localLon;mod(ringLon,2*pi)]; %#ok<AGROW>
        end
        lat = [lat;localLat]; lon = [lon;localLon]; %#ok<AGROW>
        siteIds = [siteIds;repmat(sites.SiteId(k),numel(localLat),1)]; %#ok<AGROW>
    end
    % Overlapping neighborhoods share one physical candidate, assigned to the first site.
    [~,keep] = unique(round([lat lon],12),"rows","stable");
    lat = lat(keep); lon = lon(keep); siteIds = siteIds(keep);
    band = [-90 90];
else
    % Subsets of exactly the same global rings, rather than independently shifted grids.
    [lat,lon] = digitalElevationModel.buildCandidateSensorGrid( ...
        [-pi/2 pi/2],[0 2*pi],options.spacingKm,moonRadiusKm);
    band = [-90 90];
    if domain == "south75", band = [-90 -75]; end
    if domain == "south0", band = [-90 0]; end
    keep = lat >= deg2rad(band(1))-1e-12 & lat <= deg2rad(band(2))+1e-12;
    lat = lat(keep); lon = lon(keep);
end
if domain == "shared"
    requested = string(options.requestedDomains);
    assert(all(ismember(requested,["clps","south75","south0","global"])), ...
        "planDomainDatabase:Domains","Unknown shared domain.");
    keep = false(size(lat));
    if any(requested=="south75"), keep = keep | lat<=deg2rad(-75); end
    if any(requested=="south0"), keep = keep | lat<=0; end
    if any(requested=="global"), keep(:) = true; end
    lat = lat(keep); lon = lon(keep);
    siteIds = repmat("",numel(lat),1);
    if any(requested=="clps")
        clps = planDomainDatabase("clps",options);
        lat = [lat;clps.latitudesRad]; lon = [lon;clps.longitudesRad];
        siteIds = [siteIds;clps.siteIds]; sites = clps.sites;
    end
end
count = numel(lat);
assert(count > 0,"planDomainDatabase:Empty","No candidates in requested domain.");
plan = struct("domain",domain,"options",options,"latitudeBandDeg",band, ...
    "latitudesRad",lat,"longitudesRad",lon,"siteIds",siteIds,"sites",sites, ...
    "numberOfCandidates",count, ...
    "numberOfChunks",max(1,ceil(count/options.maximumCandidatesPerChunk)));
% Arrays that scale with candidates stay within the cap. The DEM and fixed RSO arrays
% are additional resident memory; this estimate is not a whole-process RAM guarantee.
plan.legacyJacobianDiskGiB = 12*8*count*432*20/2^30;
plan.estimatedJacobianDiskGiB = 0;
mode = string(options.jacobianStorage);
assert(ismember(mode,["on_demand","position","full"]),"planDomainDatabase:Storage","Unknown Jacobian storage mode.");
if mode == "full", plan.estimatedJacobianDiskGiB = plan.legacyJacobianDiskGiB; end
if mode == "position", plan.estimatedJacobianDiskGiB = plan.legacyJacobianDiskGiB/2; end
plan.estimatedVisibilityDiskGiB = count*432*20/2^30;
plan.estimatedTerrainDiskGiB = count*3601*8/2^30;
end

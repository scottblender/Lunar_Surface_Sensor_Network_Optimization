function outputFile = buildDomainDatabase(domain,userOptions)
% BUILDDOMAINDATABASE - Build one resumable, serial, chunked domain database.
% Use planDomainDatabase for a data-free preview. Existing outputs are never overwritten.
arguments
    domain (1,1) string
    userOptions (1,1) struct = struct()
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
defaults = struct("outputRoot",string(fullfile(root,"results","domain_databases_compact")), ...
    "demFile",string(fullfile(root,"data","Synthetic_Lunar_DEM.mat")), ...
    "planOnly",false,"preflightOnly",false,"maximumDemSpacingMeters",[], ...
    "localDemFile","","flatnessFootprintMeters",10,"maximumSlopeDeg",5, ...
    "maximumRoughnessMeters",0.1,"jacobianStorage","on_demand","assessLocalFlatness",false);
options = utilities.overrideConfig(defaults,userOptions);
plan = planDomainDatabase(domain,options);
options = plan.options;
folder = fullfile(options.outputRoot,domain);
outputFile = string(fullfile(folder,"optimization_database.mat"));
fprintf("\nDomain %s: %d candidates, %d chunks, <= %d candidates/chunk\n", ...
    domain,plan.numberOfCandidates,plan.numberOfChunks,options.maximumCandidatesPerChunk);
fprintf("Jacobian storage %s: %.2f GiB payload (legacy full estimate %.2f GiB).\n", ...
    options.jacobianStorage,plan.estimatedJacobianDiskGiB,plan.legacyJacobianDiskGiB);
fprintf("Visibility + horizon payload estimate: %.2f + %.2f GiB before compression/overhead.\n", ...
    plan.estimatedVisibilityDiskGiB,plan.estimatedTerrainDiskGiB);
if options.planOnly, return; end
assert(isfile(options.demFile),"buildDomainDatabase:DemMissing", ...
    "DEM not found: %s",options.demFile);
% Validate native coverage and granularity before creating output/chunk directories.
[dem,demModel] = digitalElevationModel.loadTriaxialLunarDem(options.demFile,1737.4,24,48);
config = productionDatabaseConfiguration(options.demFile,demModel,folder);
requirements = struct("candidateSpacingKm",plan.options.spacingKm, ...
    "maximumDemSpacingMeters",options.maximumDemSpacingMeters, ...
    "terrainRangeKm",config.terrain.maximumRangeKm, ...
    "terrainRangeStepKm",config.terrain.rangeStepKm, ...
    "azimuthStepRad",config.terrain.horizonAzimuthStepRad);
if domain == "clps"
    requirements.candidateSpacingKm = plan.options.clpsSpacingKm;
    if isempty(options.maximumDemSpacingMeters)
        requirements.maximumDemSpacingMeters = 1000*plan.options.spacingKm;
    end
end
demReport = digitalElevationModel.checkDemCompatibility( ...
    demModel,plan.latitudesRad,plan.longitudesRad,requirements);
flatness = table();
validateattributes(options.assessLocalFlatness,{'logical'},{'scalar'});
assessFlatness = options.assessLocalFlatness || strlength(string(options.localDemFile))>0;
if assessFlatness && ~isempty(plan.siteIds)
    ids = find(strlength(plan.siteIds)>0);
    localDem = dem; localModel = demModel;
    if strlength(string(options.localDemFile)) > 0
        [localDem,localModel] = digitalElevationModel.loadTriaxialLunarDem(string(options.localDemFile));
    end
    flatness = digitalElevationModel.evaluateLocalFlatness(localDem,localModel, ...
        plan.latitudesRad(ids),plan.longitudesRad(ids), ...
        struct("footprintMeters",options.flatnessFootprintMeters,"maximumSlopeDeg",options.maximumSlopeDeg, ...
        "maximumRoughnessMeters",options.maximumRoughnessMeters));
    flatness.prefilterCandidateIndex = ids;
    fprintf("Local flatness: %d pass, %d fail, %d unresolved; footprint %.1f m.\n", ...
        nnz(flatness.status=="pass"),nnz(flatness.status=="fail"), ...
        nnz(flatness.status=="unresolved"),options.flatnessFootprintMeters);
end
if ~assessFlatness
    fprintf("Local flatness not assessed; installation and leveling/site preparation are study assumptions.\n");
end
if options.preflightOnly
    disp(rmfield(demReport,"flatnessCertified"));
    return
end
% Resolve paths before writing the persistent request guard.
[~,demAttributes] = fileattrib(options.demFile);
options.demFile = string(demAttributes.Name);
if ~isfolder(folder), mkdir(folder); end
[~,folderAttributes] = fileattrib(folder);
folder = string(folderAttributes.Name);
outputFile = fullfile(folder,"optimization_database.mat");
requestFile = fullfile(folder,"build_request.mat");
completionFile = fullfile(folder,"build_complete.mat");
demInfo = dir(options.demFile);
localDemInfo = [];
if assessFlatness && strlength(string(options.localDemFile)) > 0
    localDemInfo = dir(options.localDemFile);
end
request = struct("schemaVersion",1,"domain",domain,"options",options, ...
    "demBytes",demInfo.bytes,"demModified",demInfo.datenum,"localDemInfo",localDemInfo, ...
    "latitudesRad",plan.latitudesRad,"longitudesRad",plan.longitudesRad, ...
    "sites",plan.sites,"siteIds",plan.siteIds,"chunks",plan.numberOfChunks);
% Guard resume against changes to any scientific implementation/defaults.
sourceFiles = [dir(fullfile(root,"src","**","*.m")); ...
    dir(fullfile(root,"scripts","database","*.m"))];
request.sourceSignature = strings(numel(sourceFiles),2);
for k = 1:numel(sourceFiles)
    sourcePath = fullfile(sourceFiles(k).folder,sourceFiles(k).name);
    request.sourceSignature(k,:) = [string(sourcePath),string(fileread(sourcePath))];
end
if isfile(requestFile)
    previous = load(requestFile,"request");
    assert(isequaln(previous.request,request),"buildDomainDatabase:RequestChanged", ...
        "Build inputs changed. Use a new OutputRoot; existing chunks were not modified.");
else
    assert(~isfile(outputFile) && ~isfolder(fullfile(folder,"candidate_chunks")), ...
        "buildDomainDatabase:UnownedOutput","Existing output has no matching build request.");
    save(requestFile,"request","-v7.3");
end
if isfile(outputFile)
    assert(isfile(completionFile),"buildDomainDatabase:IncompleteManifest", ...
        "Database exists without a completion marker. Inspect it before removing the manifest to resume.");
    finalizeDomainDatabase(outputFile);
    fprintf("Completed database validated and skipped: %s\n",outputFile);
    return
end
assert(~isfile(completionFile),"buildDomainDatabase:MissingManifest", ...
    "Completion marker exists but database manifest is missing.");
config.outputFile = outputFile;
config.candidates.customLatitudesRad = plan.latitudesRad;
config.candidates.customLongitudesRad = plan.longitudesRad;
config.candidates.latitudeBandRad = deg2rad(plan.latitudeBandDeg);
config.candidates.spacingKm = plan.options.spacingKm;
config.study.networkSizes = plan.options.networkSizes;
if domain == "clps"
    assert(max(config.study.networkSizes) <= height(plan.sites), ...
        "buildDomainDatabase:NetworkSize","CLPS network sizes cannot exceed enabled site count.");
    warning("buildDomainDatabase:ClpsGeometryOnly", ...
        "CLPS neighborhoods are geometric candidates, not certified flat locations. " + ...
         "At most one sensor per CLPS anchor is allowed in this view.");
end
config.chunking.jacobianStorage = string(options.jacobianStorage);
config.chunking.enabled = true;
config.chunking.numberOfChunks = plan.numberOfChunks;
config.chunking.directoryName = "candidate_chunks";
config.chunking.useParallel = false;
config.chunking.maximumParallelWorkers = 1;
config.chunking.resumeExisting = true;
config.domainComparison = struct("domain",domain,"sites",plan.sites, ...
    "prefilterSiteIds",plan.siteIds,"clpsRadiusKm",plan.options.clpsRadiusKm, ...
    "flatnessCertified",false,"seed",plan.options.seed, ...
    "maximumCandidatesPerChunk",plan.options.maximumCandidatesPerChunk, ...
    "demCompatibility",demReport,"localFlatness",flatness,"enforceSiteGroups",domain=="clps", ...
    "requestedDomains",plan.options.requestedDomains,"flatnessAssessmentEnabled",assessFlatness, ...
    "installationAssumption","mounting, leveling, and site preparation are feasible");
% The same population/calibration seed is reset for every domain and retry.
previousRng = rng;
cleanup = onCleanup(@()rng(previousRng)); %#ok<NASGU>
rng(plan.options.seed,"twister");
optimization.buildOptimizationDatabase(dem,config);
finalizeDomainDatabase(outputFile);
fprintf("Completed: %s\n",outputFile);
end

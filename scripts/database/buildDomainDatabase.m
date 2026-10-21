function outputFile = buildDomainDatabase(domain,userOptions)
% BUILDDOMAINDATABASE - Build one resumable, serial, chunked domain database.
% Use planDomainDatabase for a data-free preview. Existing outputs are never overwritten.
arguments
    domain (1,1) string
    userOptions (1,1) struct = struct()
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
defaults = struct("outputRoot",string(fullfile(root,"results","domain_databases")), ...
    "demFile",string(fullfile(root,"data","Synthetic_Lunar_DEM.mat")), ...
    "planOnly",false);
options = utilities.overrideConfig(defaults,userOptions);
plan = planDomainDatabase(domain,options);
options = plan.options;
folder = fullfile(options.outputRoot,domain);
outputFile = string(fullfile(folder,"optimization_database.mat"));
fprintf("\nDomain %s: %d candidates, %d chunks, <= %d candidates/chunk\n", ...
    domain,plan.numberOfCandidates,plan.numberOfChunks,options.maximumCandidatesPerChunk);
fprintf("Uncompressed full Jacobian disk estimate: %.2f GiB\n",plan.estimatedJacobianDiskGiB);
if options.planOnly, return; end
assert(isfile(options.demFile),"buildDomainDatabase:DemMissing", ...
    "DEM not found: %s",options.demFile);
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
request = struct("schemaVersion",1,"domain",domain,"options",options, ...
    "demBytes",demInfo.bytes,"demModified",demInfo.datenum, ...
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
    saved = load(outputFile,"database");
    validateChunks(saved.database);
    fprintf("Completed database validated and skipped: %s\n",outputFile);
    return
end
assert(~isfile(completionFile),"buildDomainDatabase:MissingManifest", ...
    "Completion marker exists but database manifest is missing.");
[dem,demModel] = digitalElevationModel.loadTriaxialLunarDem(options.demFile,1737.4,24,48);
config = productionDatabaseConfiguration(options.demFile,demModel,folder);
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
        ["CLPS neighborhoods are geometric candidates, not certified flat locations. " ...
         "Site IDs are metadata; the generic optimizer does not enforce one sensor per site."]);
end
config.chunking.enabled = true;
config.chunking.numberOfChunks = plan.numberOfChunks;
config.chunking.directoryName = "candidate_chunks";
config.chunking.useParallel = false;
config.chunking.maximumParallelWorkers = 1;
config.chunking.resumeExisting = true;
config.domainComparison = struct("domain",domain,"sites",plan.sites, ...
    "prefilterSiteIds",plan.siteIds,"clpsRadiusKm",plan.options.clpsRadiusKm, ...
    "flatnessCertified",false,"seed",plan.options.seed, ...
    "maximumCandidatesPerChunk",plan.options.maximumCandidatesPerChunk);
% The same population/calibration seed is reset for every domain and retry.
previousRng = rng;
cleanup = onCleanup(@()rng(previousRng)); %#ok<NASGU>
rng(plan.options.seed,"twister");
database = optimization.buildOptimizationDatabase(dem,config);
validateChunks(database);
save(completionFile,"outputFile");
fprintf("Completed: %s\n",outputFile);
end

function validateChunks(database)
assert(database.meta.numberOfOptimizationEpochs == 432, ...
    "buildDomainDatabase:Epochs","Expected 432 epochs over three days.");
chunks = database.visibility.candidateChunks;
assert(~isempty(chunks),"buildDomainDatabase:NotChunked","Chunked storage is required.");
assert(numel(chunks) == database.config.chunking.numberOfChunks && ...
    sum([chunks.numberOfOriginalCandidates]) == database.meta.numberOfCandidatesBeforeFiltering && ...
    sum([chunks.numberOfRetainedCandidates]) == database.meta.numberOfCandidates, ...
    "buildDomainDatabase:ChunkCoverage","Chunk counts do not cover the candidate set.");
assert(max([chunks.numberOfOriginalCandidates]) <= ...
    database.config.domainComparison.maximumCandidatesPerChunk, ...
    "buildDomainDatabase:ChunkCap","Candidate chunk cap was exceeded.");
assert(isempty(database.tracking.measurementJacobianHistories) && ...
    isempty(database.visibility.filteredAvailability) && ...
    isempty(database.terrain.maximumTerrainElevationRad), ...
    "buildDomainDatabase:MonolithicStorage","Manifest contains unchunked candidate arrays.");
for k = 1:numel(chunks)
    path = string(chunks(k).filePath);
    assert(isfile(path),"buildDomainDatabase:MissingChunk","Missing chunk: %s",path);
    variables = string(who("-file",path));
    marker = load(path,"finalChunkComplete");
    assert(isfield(marker,"finalChunkComplete") && isequal(marker.finalChunkComplete,true), ...
        "buildDomainDatabase:IncompleteChunk","Chunk has no completion marker: %s",path);
    assert(ismember("filteredAvailability",variables), ...
        "buildDomainDatabase:MissingVisibility","Incomplete visibility chunk: %s",path);
    if chunks(k).numberOfRetainedCandidates > 0
        assert(ismember("measurementJacobianHistories",variables), ...
            "buildDomainDatabase:MissingJacobians","Incomplete Jacobian chunk: %s",path);
        chunk = matfile(path);
        actual = size(chunk,"measurementJacobianHistories");
        expected = [2 6 chunks(k).numberOfRetainedCandidates 432 database.meta.numberOfObjects];
        assert(isequal(actual,expected),"buildDomainDatabase:ChunkShape", ...
            "Wrong Jacobian dimensions in %s",path);
    end
end
end

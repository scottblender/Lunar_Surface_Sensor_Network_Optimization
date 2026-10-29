function outputFile = finalizeDomainDatabase(outputFile)
% FINALIZEDOMAINDATABASE - Validate saved physical chunks and finish domain manifests.
% Recover a post-build validation failure without rebuilding terrain or Jacobians.
% Only duplicated metadata from JSON cell-list expansion can be repaired here.
arguments
    outputFile (1,1) string
end
assert(isfile(outputFile),"finalizeDomainDatabase:MissingDatabase", ...
    "Saved optimization database not found: %s",outputFile);
[~,attributes] = fileattrib(outputFile);
outputFile = string(attributes.Name);
saved = load(outputFile,"database");
assert(isfield(saved,"database"),"finalizeDomainDatabase:MissingDatabase", ...
    "MAT file does not contain database: %s",outputFile);
database = saved.database;
comparison = database.config.domainComparison;
assert(~isempty(comparison),"finalizeDomainDatabase:Metadata", ...
    "Domain metadata is missing.");
repaired = ~isscalar(comparison);
if repaired
    % Cell-valued requestedDomains expands struct(), duplicating every other
    % field. Never collapse inconsistent scientific metadata or chunk caps.
    reference = rmfield(comparison(1),"requestedDomains");
    domains = strings(1,0);
    for k = 1:numel(comparison)
        assert(isequaln(rmfield(comparison(k),"requestedDomains"),reference), ...
            "finalizeDomainDatabase:ConflictingMetadata", ...
            "Domain metadata differs beyond requestedDomains; refusing repair.");
        domains = [domains,string(comparison(k).requestedDomains)]; %#ok<AGROW>
    end
    comparison = comparison(1);
    comparison.requestedDomains = domains;
end
comparison.requestedDomains = unique(string(comparison.requestedDomains(:)).',"stable");
assert(~isempty(comparison.requestedDomains) && ...
    all(ismember(comparison.requestedDomains,["clps","south75","south0","global"])), ...
    "finalizeDomainDatabase:Domains","Invalid requested domain list in saved database.");
database.config.domainComparison = comparison;
validateChunks(database);
if repaired
    % Finish writing a replacement before touching the saved manifest. Chunk
    % files and the original build_request provenance remain unchanged.
    temporaryFile = string(tempname(fileparts(outputFile)))+".mat";
    cleanup = onCleanup(@()deleteTemporary(temporaryFile)); %#ok<NASGU>
    save(temporaryFile,"database","-v7.3");
    movefile(temporaryFile,outputFile,"f");
    fprintf("Repaired duplicated domain metadata: %s\n",outputFile);
end
save(fullfile(fileparts(outputFile),"build_complete.mat"),"outputFile");
if comparison.domain == "paper_shared"
    [views,polarSelection] = derivePaperDomains(database);
    outputRoot=fileparts(fileparts(outputFile));
    for domain=["clps_fixed","clps","global"]
        folder=fullfile(outputRoot,domain); if ~isfolder(folder), mkdir(folder); end
        database=views.(domain); %#ok<NASGU>
        file=fullfile(folder,"optimization_database.mat");
        if isfile(file)
            old=load(file,"database");
            assert(isfield(old.database.meta,"sharedSourceFile") && old.database.meta.sharedSourceFile==outputFile, ...
                "finalizeDomainDatabase:ViewConflict","Use a fresh output root; an unrelated view exists.");
        end
        save(file,"database","-v7.3");
    end
    save(fullfile(outputRoot,"polar_selection.mat"),"polarSelection");
elseif comparison.domain == "shared"
    writeDomainViews(database,fileparts(fileparts(outputFile)));
end
fprintf("Validated saved database and completed domain manifests: %s\n",outputFile);
end

function deleteTemporary(file)
if isfile(file), delete(file); end
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
    if chunks(k).numberOfRetainedCandidates > 0 && database.meta.measurementJacobianStorage ~= "on_demand"
        assert(ismember("measurementJacobianHistories",variables), ...
            "buildDomainDatabase:MissingJacobians","Incomplete Jacobian chunk: %s",path);
        chunk = matfile(path);
        actual = size(chunk,"measurementJacobianHistories");
        expected = [2 database.meta.measurementJacobianStateColumns chunks(k).numberOfRetainedCandidates 432 database.meta.numberOfObjects];
        assert(isequal(actual,expected),"buildDomainDatabase:ChunkShape", ...
            "Wrong Jacobian dimensions in %s",path);
    end
end
end

function writeDomainViews(shared,outputRoot)
% Small manifests share the same immutable physical chunks; candidate IDs are local to each view.
siteIds = shared.config.domainComparison.prefilterSiteIds(shared.candidates.originalIndices);
for domain = string(shared.config.domainComparison.requestedDomains(:)).'
    keep = shared.candidates.latitudesRad<=0;
    if domain == "south75", keep = shared.candidates.latitudesRad<=deg2rad(-75); end
    if domain == "global", keep = true(shared.meta.numberOfCandidates,1); end
    if domain == "clps", keep = strlength(siteIds)>0; end
    % Geographic views exclude the independently sampled CLPS neighborhoods.
    if domain ~= "clps", keep = keep & strlength(siteIds)==0; end
    database = optimization.createDomainView(shared,find(keep),domain);
    folder = fullfile(outputRoot,domain);
    if ~isfolder(folder), mkdir(folder); end
    file = fullfile(folder,"optimization_database.mat");
    if isfile(file)
        existing = load(file,"database");
        assert(isfield(existing.database.meta,"sharedSourceFile") && ...
            existing.database.meta.sharedSourceFile == shared.config.outputFile, ...
            "buildDomainDatabase:ExistingView","Existing independent database at %s; use a new OutputRoot.",file);
    end
    database.config.outputFile = string(file);
    save(file,"database","-v7.3");
end
end

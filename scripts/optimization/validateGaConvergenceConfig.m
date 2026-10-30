function [config,database,signature] = validateGaConvergenceConfig(request)
% VALIDATEGACONVERGENCECONFIG - Stable JSON contract for Ava's PowerShell launcher.
arguments
    request (1,1) struct
end
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
required=["schemaVersion","databaseFile","outputDirectory","runCounts", ...
    "functionEvaluationBudgets","populationSize","baseSeed"];
defaults=struct("parallelMode","serial","maxWorkers",2,"resume",true,"makePlots",true,"validateOnly",false);
allowed=[required,string(fieldnames(defaults)).'];
assert(all(isfield(request,cellstr(required))) && all(ismember(string(fieldnames(request)),allowed)), ...
    "gaConvergence:Config","Missing required fields or unknown request fields. See the PowerShell contract.");
config=utilities.overrideConfig(defaults,request);
assert(isequal(config.schemaVersion,1),"gaConvergence:Schema","schemaVersion must be 1.");
validateattributes(config.runCounts,{'numeric'},{'vector','integer','>=',2,'finite'});
validateattributes(config.functionEvaluationBudgets,{'numeric'},{'vector','integer','positive','finite'});
validateattributes(config.populationSize,{'numeric'},{'scalar','integer','>=',2,'finite'});
validateattributes(config.baseSeed,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(config.maxWorkers,{'numeric'},{'scalar','integer','positive','finite'});
for field=["resume","makePlots","validateOnly"]
    validateattributes(config.(field),{'logical'},{'scalar'});
end
config.runCounts=sort(unique(config.runCounts(:).'));
config.functionEvaluationBudgets=sort(unique(config.functionEvaluationBudgets(:).'));
assert(config.baseSeed+max(config.runCounts)-1<=4294967295,"gaConvergence:Seeds","Seed range exceeds uint32.");
assert(all(config.functionEvaluationBudgets>=config.populationSize & ...
    mod(config.functionEvaluationBudgets,config.populationSize)==0), ...
    "gaConvergence:Budget","Each GA budget must be at least one population and divisible by populationSize.");
config.parallelMode=lower(string(config.parallelMode));
assert(isscalar(config.parallelMode) && ismember(config.parallelMode,["serial","runs","population"]), ...
    "gaConvergence:ParallelMode","Use serial, runs, or population. GPU execution is not implemented.");
for field=["databaseFile","outputDirectory"]
    value=string(config.(field));
    assert(isscalar(value) && strlength(value)>0,"gaConvergence:Path","Paths must be nonempty strings.");
    if isempty(regexp(char(value),'^([A-Za-z]:[\\/]|[\\/]{2}|/)','once')), value=fullfile(root,value); end
    config.(field)=string(java.io.File(char(value)).getCanonicalPath());
end
assert(isfile(config.databaseFile),"gaConvergence:Database","Frozen global database is missing.");
saved=load(config.databaseFile,"database");
assert(isfield(saved,"database"),"gaConvergence:Database","MAT file must contain database."); database=saved.database;
assert(isfield(database.config,"domainComparison") && database.config.domainComparison.domain=="global" && ...
    ~database.config.domainComparison.enforceSiteGroups && database.meta.numberOfCandidates>=3, ...
    "gaConvergence:Domain","Use a global domain manifest with at least three candidates.");
assert(~isempty(ver('globaloptim')),"gaConvergence:Toolbox","Global Optimization Toolbox is required.");
if config.parallelMode~="serial"
    assert(~isempty(ver('parallel')),"gaConvergence:Toolbox","Parallel Computing Toolbox is required.");
end
chunks=struct('path',{},'bytes',{},'modified',{});
if isfield(database.visibility,"candidateChunks")
    for k=1:numel(database.visibility.candidateChunks)
        path=string(database.visibility.candidateChunks(k).filePath); info=dir(path);
        assert(isscalar(info) && ~info.isdir,"gaConvergence:Chunk","Missing physical chunk: %s",path);
        chunks(k)=struct("path",path,"bytes",info.bytes,"modified",info.datenum);
    end
end
sources=[dir(fullfile(root,"src","**","*.m"));dir(fullfile(root,"scripts","optimization","*.m"))];
sourceHashes=strings(numel(sources),2);
for k=1:numel(sources)
    path=string(fullfile(sources(k).folder,sources(k).name)); sourceHashes(k,:)=[path,sha256(path)];
end
signature=struct("schemaVersion",1,"databaseFile",config.databaseFile,"databaseSha256",sha256(config.databaseFile), ...
    "chunkMetadata",chunks,"sourceHashes",sourceHashes,"populationSize",config.populationSize, ...
    "baseSeed",config.baseSeed,"parallelMode",config.parallelMode,"maxWorkers",config.maxWorkers);
end
function hash=sha256(file)
fid=fopen(file,'rb'); assert(fid>=0,"gaConvergence:Read","Cannot read %s",file);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
digest=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes=fread(fid,1048576,'*uint8'); if ~isempty(bytes), digest.update(bytes); end
end
hash=string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[])));
end

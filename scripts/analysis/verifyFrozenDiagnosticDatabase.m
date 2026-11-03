function [database,signature]=verifyFrozenDiagnosticDatabase(studyDirectory,databaseFile)
% VERIFYFROZENDIAGNOSTICDATABASE - Reuse the original source/database contract.
m=load(fullfile(studyDirectory,"ga_sweep_manifest.mat"),"manifest"); signature=m.manifest.signature;
assert(analysisFileSha256(databaseFile)==signature.databaseSha256, ...
    "geographicDiagnostics:DatabaseMismatch","Database differs from the frozen sweep.");
for k=1:numel(signature.chunkMetadata)
    expected=signature.chunkMetadata(k); actual=dir(expected.path);
    assert(isscalar(actual) && actual.bytes==expected.bytes && actual.datenum==expected.modified, ...
        "geographicDiagnostics:ChunkMismatch","Changed or missing physical chunk: %s",expected.path);
end
if isfield(signature,"sourceHashes")
    hashes=string(signature.sourceHashes);
    for k=1:size(hashes,1)
        assert(isfile(hashes(k,1)) && analysisFileSha256(hashes(k,1))==hashes(k,2), ...
            "geographicDiagnostics:SourceMismatch","Frozen selection source changed: %s",hashes(k,1));
    end
end
s=load(databaseFile,"database"); database=s.database;
assert(database.config.domainComparison.domain=="global" && ~database.config.domainComparison.enforceSiteGroups, ...
    "geographicDiagnostics:Domain","Expected the same frozen global database.");
end

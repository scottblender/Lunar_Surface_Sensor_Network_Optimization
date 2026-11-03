function hash=analysisFileSha256(file)
% ANALYSISFILESHA256 - Freeze provenance for post-processing and diagnostics.
fid=fopen(file,'rb'); assert(fid>=0,"networkFamilies:Read","Cannot read %s",file);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
digest=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes=fread(fid,1048576,'*uint8'); if ~isempty(bytes), digest.update(bytes); end
end
hash=string(lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[])));
end

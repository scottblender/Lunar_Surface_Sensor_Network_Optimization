function selectedJacobians = ...
    loadChunkedMeasurementJacobians(database,sensorIndices)
% LOADCHUNKEDMEASUREMENTJACOBIANS Load selected full 2x6 Jacobian histories.
%
% Uses the global-candidate -> chunk/local-index maps stored in the core
% optimization database, then MATFILE partial indexing to load only the
% selected candidates from the required chunk files. Persistent MATFILE
% handles are worker-local when called inside process-based parallel pools.

arguments
    database (1,1) struct
    sensorIndices (:,1) double
end

assert(isfield(database,"candidates") && ...
    isfield(database.candidates,"jacobianChunkIndex") && ...
    isfield(database.candidates,"jacobianChunkLocalIndex"), ...
    "Chunked Jacobian candidate maps are missing.");

assert(isfield(database,"tracking") && ...
    isfield(database.tracking,"measurementJacobianChunks"), ...
    "Chunked Jacobian metadata are missing.");

numberOfCandidates = database.meta.numberOfCandidates;
numberOfTimes = database.meta.numberOfOptimizationEpochs;
numberOfObjects = database.meta.numberOfObjects;

sensorIndices = round(sensorIndices(:));
assert(all(sensorIndices >= 1 & sensorIndices <= numberOfCandidates), ...
    "Requested candidate index is outside the optimization database.");

numberOfSelectedSensors = numel(sensorIndices);
selectedJacobians = zeros( ...
    2,6,numberOfSelectedSensors,numberOfTimes,numberOfObjects);

chunkIndices = double(database.candidates.jacobianChunkIndex(sensorIndices));
localIndices = double(database.candidates.jacobianChunkLocalIndex(sensorIndices));

assert(all(chunkIndices >= 1), ...
    "A selected candidate does not have a valid Jacobian chunk mapping.");
assert(all(localIndices >= 1), ...
    "A selected candidate does not have a valid Jacobian local index.");

uniqueChunks = unique(chunkIndices(:).',"stable");

for chunkIndex = uniqueChunks
    selectionPositions = find(chunkIndices == chunkIndex);
    chunkMetadata = database.tracking.measurementJacobianChunks(chunkIndex);
    chunkFile = string(chunkMetadata.filePath);

    assert(isfile(chunkFile), ...
        "Measurement-Jacobian chunk file was not found: %s",chunkFile);

    chunkMat = getMatFile(chunkFile);
    requestedLocalIndices = localIndices(selectionPositions);

    chunkBlock = chunkMat.measurementJacobianHistories( ...
        :,:,requestedLocalIndices,:,:);

    chunkBlock = reshape( ...
        chunkBlock, ...
        2,6,numel(selectionPositions),numberOfTimes,numberOfObjects);

    selectedJacobians(:,:,selectionPositions,:,:) = chunkBlock;
end

end

function chunkMat = getMatFile(chunkFile)
% Reuse worker-local MATFILE handles across repeated objective evaluations.

persistent matFileCache

if isempty(matFileCache)
    matFileCache = containers.Map( ...
        "KeyType","char", ...
        "ValueType","any");
end

cacheKey = char(chunkFile);

if isKey(matFileCache,cacheKey)
    chunkMat = matFileCache(cacheKey);
else
    chunkMat = matfile(cacheKey);
    matFileCache(cacheKey) = chunkMat;
end

end

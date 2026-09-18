function data = loadChunkedCandidateData(database,sensorIndices,fieldName)
% LOADCHUNKEDCANDIDATEDATA Partially load selected candidate data by index.
%
% Supported fields:
%   "measurementJacobianHistories" - 2x6xNsxNtxNobj double
%   "filteredAvailability"         - NsxNtxNobj logical
%   "maximumTerrainElevationRad"   - NsxNaz double
%
% The optimizer decision variable remains the retained global candidate
% index. This function maps each requested global index to its chunk and
% local row, then uses MATFILE partial indexing so only selected candidates
% are read from disk.

arguments
    database (1,1) struct
    sensorIndices (:,1) double
    fieldName (1,1) string
end

sensorIndices = round(sensorIndices(:));
numberOfCandidates = database.meta.numberOfCandidates;

assert(all(sensorIndices >= 1 & sensorIndices <= numberOfCandidates), ...
    "Requested candidate index is outside the optimization database.");

assert(isfield(database.candidates,"chunkIndex") && ...
    isfield(database.candidates,"chunkLocalIndex") && ...
    isfield(database.candidates,"originalChunkLocalIndex"), ...
    "Chunked candidate index maps are missing.");

chunkIndices = double(database.candidates.chunkIndex(sensorIndices));

switch fieldName
    case "measurementJacobianHistories"
        localIndices = double(database.candidates.chunkLocalIndex(sensorIndices));
        chunkMetadata = database.tracking.measurementJacobianChunks;
        data = zeros( ...
            2,6,numel(sensorIndices), ...
            database.meta.numberOfOptimizationEpochs, ...
            database.meta.numberOfObjects);

    case "filteredAvailability"
        localIndices = double(database.candidates.chunkLocalIndex(sensorIndices));
        chunkMetadata = database.visibility.candidateChunks;
        data = false( ...
            numel(sensorIndices), ...
            database.meta.numberOfOptimizationEpochs, ...
            database.meta.numberOfObjects);

    case "maximumTerrainElevationRad"
        localIndices = ...
            double(database.candidates.originalChunkLocalIndex(sensorIndices));
        chunkMetadata = database.terrain.candidateChunks;
        data = zeros( ...
            numel(sensorIndices), ...
            numel(database.terrain.horizonAzimuthsRad));

    otherwise
        error( ...
            "loadChunkedCandidateData:UnsupportedField", ...
            "Unsupported chunked candidate field: %s",fieldName);
end

assert(all(chunkIndices >= 1 & chunkIndices <= numel(chunkMetadata)), ...
    "A selected candidate has an invalid chunk index.");
assert(all(localIndices >= 1), ...
    "A selected candidate has an invalid local chunk index.");

uniqueChunks = unique(chunkIndices(:).',"stable");

for chunkIndex = uniqueChunks
    selectionPositions = find(chunkIndices == chunkIndex);
    requestedLocalIndices = localIndices(selectionPositions);
    chunkFile = string(chunkMetadata(chunkIndex).filePath);

    assert(isfile(chunkFile), ...
        "Candidate chunk file was not found: %s",chunkFile);

    chunkMat = getMatFile(chunkFile);

    try
        switch fieldName
            case "measurementJacobianHistories"
                chunkBlock = chunkMat.measurementJacobianHistories( ...
                    :,:,requestedLocalIndices,:,:);
                chunkBlock = reshape( ...
                    chunkBlock, ...
                    2,6,numel(selectionPositions), ...
                    database.meta.numberOfOptimizationEpochs, ...
                    database.meta.numberOfObjects);
                data(:,:,selectionPositions,:,:) = chunkBlock;

            case "filteredAvailability"
                chunkBlock = chunkMat.filteredAvailability( ...
                    requestedLocalIndices,:,:);
                chunkBlock = reshape( ...
                    chunkBlock, ...
                    numel(selectionPositions), ...
                    database.meta.numberOfOptimizationEpochs, ...
                    database.meta.numberOfObjects);
                data(selectionPositions,:,:) = chunkBlock;

            case "maximumTerrainElevationRad"
                chunkBlock = chunkMat.maximumTerrainElevationRad( ...
                    requestedLocalIndices,:);
                data(selectionPositions,:) = chunkBlock;
        end

    catch groupedReadError
        % Fall back to one candidate at a time for MATLAB/HDF5 versions
        % that reject noncontiguous partial indexing.
        for selectionIndex = 1:numel(selectionPositions)
            outputPosition = selectionPositions(selectionIndex);
            localIndex = requestedLocalIndices(selectionIndex);

            try
                switch fieldName
                    case "measurementJacobianHistories"
                        block = chunkMat.measurementJacobianHistories( ...
                            :,:,localIndex,:,:);
                        data(:,:,outputPosition,:,:) = reshape( ...
                            block, ...
                            2,6,1, ...
                            database.meta.numberOfOptimizationEpochs, ...
                            database.meta.numberOfObjects);

                    case "filteredAvailability"
                        block = chunkMat.filteredAvailability( ...
                            localIndex,:,:);
                        data(outputPosition,:,:) = reshape( ...
                            block, ...
                            1, ...
                            database.meta.numberOfOptimizationEpochs, ...
                            database.meta.numberOfObjects);

                    case "maximumTerrainElevationRad"
                        data(outputPosition,:) = ...
                            chunkMat.maximumTerrainElevationRad(localIndex,:);
                end
            catch singleReadError
                singleReadError = addCause(singleReadError,groupedReadError);
                rethrow(singleReadError);
            end
        end
    end
end

end

function chunkMat = getMatFile(chunkFile)
% Reuse one worker-local MATFILE handle per chunk file.

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

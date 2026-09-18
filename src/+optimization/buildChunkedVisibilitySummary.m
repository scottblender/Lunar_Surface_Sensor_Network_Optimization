function summary = buildChunkedVisibilitySummary( ...
    chunkMetadata,numberOfCandidates,numberOfObjects)
% BUILDCHUNKEDVISIBILITYSUMMARY Summarize final chunked availability.
%
% Only the final accepted-measurement masks are retained in production
% chunks. Large intermediate geometric/terrain/celestial diagnostic masks
% are intentionally not persisted.

arguments
    chunkMetadata (:,1) struct
    numberOfCandidates (1,1) double {mustBeInteger,mustBeNonnegative}
    numberOfObjects (1,1) double {mustBeInteger,mustBePositive}
end

acceptedByCandidateObject = zeros(numberOfCandidates,numberOfObjects);
acceptedByObject = zeros(numberOfObjects,1);
totalAccepted = 0;

for chunkIndex = 1:numel(chunkMetadata)
    if chunkMetadata(chunkIndex).numberOfRetainedCandidates == 0
        continue
    end

    chunkMat = matfile(string(chunkMetadata(chunkIndex).filePath));
    globalIndices = double(chunkMat.retainedGlobalCandidateIndices(:,1));
    availability = chunkMat.filteredAvailability(:,:,:);

    chunkCounts = reshape( ...
        sum(availability,2), ...
        numel(globalIndices),numberOfObjects);

    acceptedByCandidateObject(globalIndices,:) = chunkCounts;
    acceptedByObject = acceptedByObject + sum(chunkCounts,1).';
    totalAccepted = totalAccepted + nnz(availability);
end

summary = struct();
summary.totalAccepted = totalAccepted;
summary.acceptedByCandidateObject = acceptedByCandidateObject;
summary.acceptedByObject = acceptedByObject;

% These diagnostic totals are intentionally omitted from the lean chunked
% production build to avoid retaining several multi-gigabyte masks.
summary.totalGeometric = NaN;
summary.totalTerrainAccepted = NaN;
summary.totalEarthBlocked = NaN;
summary.totalSunBlocked = NaN;
summary.diagnosticsPersisted = false;

end

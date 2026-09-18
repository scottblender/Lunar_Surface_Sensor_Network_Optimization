function chunkMetadata = createCandidateChunkPlan( ...
    numberOfCandidates,numberOfChunks,chunkDirectory)
% CREATECANDIDATECHUNKPLAN Partition the global candidate list equally.
%
% Chunks are contiguous in the original global candidate ordering and differ
% in size by at most one candidate. The partition is created immediately
% after the candidate grid so every large candidate-dependent production
% quantity can be built and saved chunk-by-chunk.

arguments
    numberOfCandidates (1,1) double {mustBeInteger,mustBePositive}
    numberOfChunks (1,1) double {mustBeInteger,mustBePositive}
    chunkDirectory (1,1) string
end

assert(numberOfChunks <= numberOfCandidates, ...
    "Number of chunks cannot exceed the candidate count.");

baseCount = floor(numberOfCandidates/numberOfChunks);
remainder = mod(numberOfCandidates,numberOfChunks);

chunkCounts = baseCount*ones(numberOfChunks,1);
chunkCounts(1:remainder) = chunkCounts(1:remainder) + 1;

chunkStarts = cumsum([1;chunkCounts(1:end-1)]);
chunkEnds = cumsum(chunkCounts);

chunkMetadata = repmat(struct( ...
    "chunkNumber",0, ...
    "filePath","", ...
    "firstOriginalCandidateIndex",0, ...
    "lastOriginalCandidateIndex",0, ...
    "numberOfOriginalCandidates",0, ...
    "numberOfRetainedCandidates",0),numberOfChunks,1);

for chunkIndex = 1:numberOfChunks
    chunkMetadata(chunkIndex).chunkNumber = chunkIndex;
    chunkMetadata(chunkIndex).filePath = string(fullfile( ...
        chunkDirectory, ...
        sprintf("candidate_chunk_%02d.mat",chunkIndex)));
    chunkMetadata(chunkIndex).firstOriginalCandidateIndex = chunkStarts(chunkIndex);
    chunkMetadata(chunkIndex).lastOriginalCandidateIndex = chunkEnds(chunkIndex);
    chunkMetadata(chunkIndex).numberOfOriginalCandidates = chunkCounts(chunkIndex);
end

assert(sum([chunkMetadata.numberOfOriginalCandidates]) == numberOfCandidates);
assert(max(chunkCounts)-min(chunkCounts) <= 1);

end

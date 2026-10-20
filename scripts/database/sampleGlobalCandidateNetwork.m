function indices = sampleGlobalCandidateNetwork(numberOfCandidates,networkSize)
% SAMPLEGLOBALCANDIDATENETWORK - Sample distinct candidate-site IDs uniformly.

arguments
    numberOfCandidates (1,1) double {mustBeInteger,mustBePositive}
    networkSize (1,1) double {mustBeInteger,mustBePositive}
end
assert(networkSize<=numberOfCandidates,"Network exceeds candidate count.");
indices = sort(randperm(numberOfCandidates,networkSize)).';
end

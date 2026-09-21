function indices = sampleGlobalCandidateNetwork(numberOfCandidates,networkSize)
% Uniform global candidate subset; no duplicate sites within a network.
arguments
    numberOfCandidates (1,1) double {mustBeInteger,mustBePositive}
    networkSize (1,1) double {mustBeInteger,mustBePositive}
end
assert(networkSize<=numberOfCandidates,"Network exceeds candidate count.");
indices = sort(randperm(numberOfCandidates,networkSize)).';
end

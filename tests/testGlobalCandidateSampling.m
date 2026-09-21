function tests = testGlobalCandidateSampling
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
end

function testUniqueGlobalSamplesAndReproducibility(testCase)
previous = rng; cleanup = onCleanup(@()rng(previous)); %#ok<NASGU>
rng(7000,"twister");
a = zeros(10,1000);
for k=1:1000
    a(:,k) = sampleGlobalCandidateNetwork(100,10);
    verifyEqual(testCase,numel(unique(a(:,k))),10);
end
verifyEqual(testCase,unique(a(:)),(1:100).');
rng(7000,"twister");
verifyEqual(testCase,sampleGlobalCandidateNetwork(100,10),a(:,1));
% No nominal-site exclusions: even a network containing every site is valid.
verifyEqual(testCase,sampleGlobalCandidateNetwork(10,10),(1:10).');
end

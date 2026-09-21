function tests = testNetworkSelectionBins
tests = functiontests(localfunctions);
end

function testRunFrequencyAndLongitudeWrap(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
a = struct("bestSensorLatitudesRad",deg2rad([-89 -89 -1]), ...
    "bestSensorLongitudesRad",deg2rad([0 360 -1]));
b = struct("bestSensorLatitudesRad",deg2rad(-1), ...
    "bestSensorLongitudesRad",deg2rad(359));
percent = binNetworkSelectionFrequency({a,b},struct(),-90:5:0,0:15:360);
verifyEqual(testCase,percent(1,1),50); % Two sensors in one run count once.
verifyEqual(testCase,percent(end,end),100); % -1 and 359 share a bin.
verifyEqual(testCase,nnz(percent),2);
end

function testCandidateIndexFallbackAndDomainEndpoints(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
database.candidates.latitudesRad = deg2rad([-90 0]);
database.candidates.longitudesRad = deg2rad([0 360]);
state = struct("bestSensorIndices",[1 2]);
percent = binNetworkSelectionFrequency({state},database,-90:5:0,0:15:360);
verifyEqual(testCase,percent(1,1),100);
verifyEqual(testCase,percent(end,1),100);
end

function tests = testAnalysisUtilities
% TESTANALYSISUTILITIES - Verify configuration, frozen-time alignment, and candidate matching.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root); setupProject;
end

function testConfigOverrides(testCase)
defaults = struct('a',1,'nested',struct('x',2,'y',3));
override = struct('nested',struct('x',4),'newField',5);
shallow = utilities.overrideConfig(defaults,override);
deep = utilities.mergeConfig(defaults,override);
verifyEqual(testCase,shallow.nested,struct('x',4));
verifyEqual(testCase,deep.nested,struct('x',4,'y',3));
verifyEqual(testCase,deep.newField,5);
verifyEqual(testCase,deep.a,1);
cleared = utilities.mergeConfig(deep,struct('nested',[]));
verifyEqual(testCase,cleared.nested,[]);
end

function testEphemerisSelectionAndTimeMismatch(testCase)
database.truth.times = [0;10;20;30];
database.ephemeris.earthPositionsMci = reshape(1:12,3,4);
database.ephemeris.sunPositionsMci = reshape(21:32,3,4);
[earth,sun] = optimization.selectEphemerides(database,[30;10]);
verifyEqual(testCase,earth,double(database.ephemeris.earthPositionsMci(:,[4 2])));
verifyEqual(testCase,sun,double(database.ephemeris.sunPositionsMci(:,[4 2])));
verifyError(testCase,@()optimization.selectEphemerides(database,15), ...
    'selectEphemerides:TimeMismatch');
end

function testCoordinateMatchingAcrossLongitudeSeam(testCase)
database.candidates.latitudesRad = deg2rad([-80;-85;-90]);
database.candidates.longitudesRad = deg2rad([359;1;0]);
[ids,exact] = optimization.matchCandidateLocations(database, ...
    deg2rad([-85;-80]),deg2rad([361;-1]));
verifyEqual(testCase,ids,[2;1]);
verifyTrue(testCase,exact);
[ids,exact] = optimization.matchCandidateLocations(database,deg2rad(-80.1),deg2rad(-1));
verifyEqual(testCase,ids,1);
verifyFalse(testCase,exact);
end

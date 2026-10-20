function tests = testRefineDiscreteNetwork
% TESTREFINEDISCRETENETWORK - Fast, dependency-free discrete search tests.

tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root,"src"));
end

function testZeroRadiusPreservesNetwork(testCase)
database = makeDatabase([0;0;0],[0;0.01;0.02],100);
options = struct("objectiveFcn",@(ids)sum(double(ids).^2));
result = optimization.refineDiscreteNetwork( ...
    [3;1],database,"information",0,options);
verifyEqual(testCase,result.initialSensorIndices,[1;3]);
verifyEqual(testCase,result.bestSensorIndices,[1;3]);
verifyEqual(testCase,result.initialObjective,10);
verifyEqual(testCase,result.bestObjective,10);
verifyEqual(testCase,result.improvement,0);
verifyEqual(testCase,result.numberOfCombinations,1);
verifyEqual(testCase,result.numberOfObjectiveEvaluations,1);
verifyTrue(testCase,result.exhaustiveWithinOriginalNeighborhoods);
end

function testExhaustiveSearchFindsJointOnlyImprovement(testCase)
% Start at [1,4], where every one-site replacement is worse.
% The joint change [2,5] is nevertheless globally best in the radius.
database = makeDatabase(zeros(5,1),(0:0.01:0.04).',100);
options = struct("objectiveFcn",@jointOnlyObjective);
result = optimization.refineDiscreteNetwork( ...
    [1;4],database,"coverage",1.01,options);
verifyEqual(testCase,result.neighborhoodSizes,[2;3]);
verifyEqual(testCase,result.numberOfCombinations,6);
verifyEqual(testCase,result.numberOfUniqueNetworks,6);
verifyEqual(testCase,result.numberOfObjectiveEvaluations,6);
verifyEqual(testCase,result.numberOfDuplicateCombinations,0);
verifyEqual(testCase,result.initialObjective,10);
verifyEqual(testCase,result.bestSensorIndices,[2;5]);
verifyEqual(testCase,result.bestObjective,0);
verifyEqual(testCase,result.improvement,10);
verifyTrue(testCase,result.improved);
end

function testOverlappingNeighborhoodsCacheEquivalentNetworks(testCase)
% Both observers can reach all three sites. A 3x3 Cartesian product has
% three invalid duplicate-site cases and three distinct valid networks.
database = makeDatabase(zeros(3,1),[0;0.001;0.002],100);
options = struct("objectiveFcn",@(ids)sum((ids(:)-[2;3]).^2));
result = optimization.refineDiscreteNetwork( ...
    [1;2],database,"information",0.25,options);
verifyEqual(testCase,result.numberOfCombinations,9);
verifyEqual(testCase,result.numberOfDuplicateCombinations,3);
verifyEqual(testCase,result.numberOfValidCombinations,6);
verifyEqual(testCase,result.numberOfUniqueNetworks,3);
verifyEqual(testCase,result.numberOfRepeatedNetworks,4);
verifyEqual(testCase,result.numberOfObjectiveEvaluations,3);
verifyEqual(testCase,result.bestSensorIndices,[2;3]);
end

function testLongitudeSeamUsesGeographicDistance(testCase)
% 359deg and 1deg are close at high latitude; 180deg is not.
database = makeDatabase(deg2rad([-80;-80;-80]), ...
    deg2rad([359;1;180]),1737.4);
options = struct("objectiveFcn",@(ids)double(ids(1)));
result = optimization.refineDiscreteNetwork( ...
    1,database,"coverage",11,options);
verifyEqual(testCase,result.neighborhoodIndices{1},[1;2]);
verifyEqual(testCase,result.numberOfCombinations,2);
end

function testCombinationLimitFailsBeforeObjective(testCase)
database = makeDatabase(zeros(5,1),(0:0.01:0.04).',100);
options = struct("maximumCombinations",5, ...
    "objectiveFcn",@(~)error("test:CalledEarly", ...
    "Objective must not be evaluated."));
verifyError(testCase,@()optimization.refineDiscreteNetwork( ...
    [1;4],database,"information",1.01,options), ...
    "refineDiscreteNetwork:TooManyCombinations");
end

function testInfiniteLimitAllowsExplicitExhaustiveSearch(testCase)
database = makeDatabase(zeros(5,1),(0:0.01:0.04).',100);
options = struct("maximumCombinations",Inf, ...
    "objectiveFcn",@jointOnlyObjective);
result = optimization.refineDiscreteNetwork( ...
    [1;4],database,"coverage",1.01,options);
verifyEqual(testCase,result.bestSensorIndices,[2;5]);
verifyEqual(testCase,result.numberOfCombinations,6);
verifyEqual(testCase,result.numberOfObjectiveEvaluations,6);
end

function testInvalidInitialNetworkRejected(testCase)
database = makeDatabase(zeros(3,1),[0;0.01;0.02],100);
verifyError(testCase,@()optimization.refineDiscreteNetwork( ...
    [1;1],database,"coverage",1), ...
    "refineDiscreteNetwork:DuplicateInitialSites");
end

function testInitialIncumbentCannotGetWorse(testCase)
database = makeDatabase(zeros(3,1),[0;0.01;0.02],100);
options = struct("objectiveFcn",@(ids)sum((ids(:)-[1;3]).^2));
result = optimization.refineDiscreteNetwork( ...
    [1;3],database,"information",3,options);
verifyEqual(testCase,result.bestSensorIndices,[1;3]);
verifyEqual(testCase,result.bestObjective,result.initialObjective);
verifyFalse(testCase,result.improved);
end

function database = makeDatabase(latitudes,longitudes,moonRadiusKm)
database = struct();
database.meta.numberOfCandidates = numel(latitudes);
database.candidates.latitudesRad = latitudes(:);
database.candidates.longitudesRad = longitudes(:);
database.config.moon.radiusKm = moonRadiusKm;
end

function J = jointOnlyObjective(indices)
indices = sort(indices(:));
if isequal(indices,[2;5])
    J = 0;
elseif isequal(indices,[1;4])
    J = 10;
else
    J = 12;
end
end

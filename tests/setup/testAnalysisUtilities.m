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

function testDomainPlansAreNestedAndBounded(testCase)
options = struct("spacingKm",200,"maximumCandidatesPerChunk",17);
globalPlan = planDomainDatabase("global",options);
south = planDomainDatabase("south0",options);
polar = planDomainDatabase("south75",options);
verifyTrue(testCase,all(ismember([south.latitudesRad south.longitudesRad], ...
    [globalPlan.latitudesRad globalPlan.longitudesRad],"rows")));
verifyTrue(testCase,all(ismember([polar.latitudesRad polar.longitudesRad], ...
    [south.latitudesRad south.longitudesRad],"rows")));
chunks = optimization.createCandidateChunkPlan(globalPlan.numberOfCandidates, ...
    globalPlan.numberOfChunks,"unused");
verifyLessThanOrEqual(testCase,max([chunks.numberOfOriginalCandidates]),17);
verifyEqual(testCase,sum([chunks.numberOfOriginalCandidates]),globalPlan.numberOfCandidates);
end

function testClpsNeighborhoodDistancesAndProvenance(testCase)
plan = planDomainDatabase("clps");
verifyEqual(testCase,height(plan.sites),3);
for k = 1:height(plan.sites)
    ids = plan.siteIds == plan.sites.SiteId(k);
    lat0 = deg2rad(plan.sites.LatitudeDeg(k));
    lon0 = deg2rad(plan.sites.LongitudeDeg(k));
    % Haversine remains accurate for 100 km neighborhoods.
    a = sin((plan.latitudesRad(ids)-lat0)/2).^2 + ...
        cos(lat0)*cos(plan.latitudesRad(ids)).*sin((plan.longitudesRad(ids)-lon0)/2).^2;
    distance = 2*1737.4*asin(sqrt(a));
    verifyEqual(testCase,max(distance),100,'AbsTol',1e-9);
    verifyLessThan(testCase,min(distance),1e-9);
end
verifyTrue(testCase,all(strlength(plan.sites.SourceURL)>0));
end

function testInterruptedJacobianChunkIsRebuilt(testCase)
folder = string(tempname);
mkdir(folder);
testCase.addTeardown(@()rmdir(folder,'s'));
metadata = optimization.createCandidateChunkPlan(1,1,folder);
chunkFile = metadata.filePath;
originalCandidateIndices = uint32(1);
candidateLatitudesRad = 0;
candidateLongitudesRad = 0;
horizonAzimuthsRad = [0;pi;2*pi];
maximumTerrainElevationRad = zeros(1,3);
retainedOriginalCandidateIndices = uint32(1);
retainedGlobalCandidateIndices = uint32(1);
filteredAvailability = false(1,2,2);
% Simulate a stopped writer: final dimensions exist but contents are unwritten.
measurementJacobianHistories = zeros(2,6,1,2,2);
finalChunkComplete = false;
save(chunkFile,"originalCandidateIndices","candidateLatitudesRad", ...
    "candidateLongitudesRad","horizonAzimuthsRad","maximumTerrainElevationRad", ...
    "retainedOriginalCandidateIndices","retainedGlobalCandidateIndices", ...
    "filteredAvailability","measurementJacobianHistories","finalChunkComplete","-v7.3");
dem = griddedInterpolant({[-pi/2;pi/2],[0;2*pi]},zeros(2));
states = repmat([2000;100;200;0;1;0],1,2,2);
earth = repmat([0;384400;0],1,2);
sun = repmat([0;0;149597870],1,2);
visibility = struct("minimumElevationRad",0,"earthRadiusKm",6378, ...
    "sunRadiusKm",695700,"sunMinimumAngularSeparationRad",0, ...
    "earthMinimumAngularSeparationRad",0);
optimization.buildFinalCandidateChunks(metadata,true,uint32(1),states,[600;1200], ...
    dem,earth,sun,visibility,struct("horizonMarginRad",0),1737.4,0,0,false,1,true);
written = load(chunkFile,"finalChunkComplete","measurementJacobianHistories");
verifyTrue(testCase,written.finalChunkComplete);
verifyGreaterThan(testCase,nnz(written.measurementJacobianHistories),0);
expected = measurements.surfaceRaDecJacobian(states(:,1,1),600,0,0,dem,1737.4,0,0);
verifyEqual(testCase,written.measurementJacobianHistories(:,:,1,1,1),expected,'AbsTol',1e-14);
end

function testCompactChunksHaveNoJacobianPayload(testCase)
folder = string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
for mode = ["position","on_demand"]
    target = fullfile(folder,mode); mkdir(target);
    metadata = optimization.createCandidateChunkPlan(1,1,target);
    originalCandidateIndices = uint32(1); candidateLatitudesRad = 0; candidateLongitudesRad = 0;
    horizonAzimuthsRad = [0;pi;2*pi]; maximumTerrainElevationRad = zeros(1,3);
    save(metadata.filePath,"originalCandidateIndices","candidateLatitudesRad","candidateLongitudesRad", ...
        "horizonAzimuthsRad","maximumTerrainElevationRad","-v7.3");
    dem = griddedInterpolant({[-pi/2;pi/2],[0;2*pi]},zeros(2));
    states = repmat([2000;100;200;0;1;0],1,2,2);
    visibility = struct("minimumElevationRad",0,"earthRadiusKm",6378,"sunRadiusKm",695700, ...
        "sunMinimumAngularSeparationRad",0,"earthMinimumAngularSeparationRad",0);
    metadata = optimization.buildFinalCandidateChunks(metadata,true,uint32(1),states,[600;1200], ...
        dem,repmat([0;384400;0],1,2),repmat([0;0;149597870],1,2),visibility, ...
        struct("horizonMarginRad",0),1737.4,0,0,false,1,true,mode);
    data = load(metadata.filePath);
    verifyTrue(testCase,data.finalChunkComplete);
    if mode == "on_demand"
        verifyFalse(testCase,isfield(data,"measurementJacobianHistories"));
    else
        verifySize(testCase,data.measurementJacobianHistories,[2 3 1 2 2]);
        expected = measurements.surfaceRaDecJacobian(states(:,1,1),600,0,0,dem,1737.4,0,0);
        verifyEqual(testCase,data.measurementJacobianHistories(:,:,1,1,1),expected(:,1:3),'AbsTol',1e-14);
    end
    optimization.buildFinalCandidateChunks(metadata,true,uint32(1),states,[600;1200], ...
        dem,repmat([0;384400;0],1,2),repmat([0;0;149597870],1,2),visibility, ...
        struct("horizonMarginRad",0),1737.4,0,0,false,1,true,mode);
end
end

function testSharedDomainViewKeepsPhysicalChunkMapping(testCase)
plan = planDomainDatabase("shared",struct("spacingKm",500));
n = plan.numberOfCandidates;
db.meta.numberOfCandidates = n; db.meta.numberOfObjects = 2;
db.objective.infeasiblePenalty = 1e12;
db.study.objectiveModes = ["coverage","information"];
db.config.outputFile = "shared/optimization_database.mat";
db.config.domainComparison = struct("prefilterSiteIds",plan.siteIds,"sites",plan.sites);
db.candidates.latitudesRad = plan.latitudesRad; db.candidates.longitudesRad = plan.longitudesRad;
db.candidates.originalIndices = uint32((1:n).');
db.candidates.chunkIndex = ones(n,1,"uint16");
db.candidates.chunkLocalIndex = uint32((1:n).');
db.candidates.prefilter = struct("latitudesRad",plan.latitudesRad,"longitudesRad",plan.longitudesRad,"keepMask",true(n,1));
db.study.networkSizes = [3 5]; db.config.study.networkSizes = [3 5]; db.visibility.summary = struct("acceptedByCandidateObject",ones(n,2));
ids = find(strlength(plan.siteIds)>0);
view = optimization.createDomainView(db,ids,"clps");
verifyEqual(testCase,view.candidates.chunkLocalIndex,db.candidates.chunkLocalIndex(ids));
verifyEqual(testCase,view.candidates.originalIndices,uint32((1:numel(ids)).'));
verifyEqual(testCase,view.meta.sharedSourceCandidateIds,ids);
verifyEqual(testCase,view.study.networkSizes,3);
verifyEqual(testCase,view.visibility.summary.totalAccepted,2*numel(ids));
[value,details] = optimization.networkObjective([1;2],view,"coverage");
verifyEqual(testCase,value,1e12);
verifyEqual(testCase,details.reason,"duplicate_clps_site");
end

function testSharedBuildUsesOnlyRequestedCandidateUnion(testCase)
options = struct("spacingKm",500,"requestedDomains",["south75","south0"]);
shared = planDomainDatabase("shared",options);
south = planDomainDatabase("south0",options);
verifyEqual(testCase,shared.latitudesRad,south.latitudesRad);
verifyEqual(testCase,shared.longitudesRad,south.longitudesRad);
verifyTrue(testCase,all(strlength(shared.siteIds)==0));
verifyTrue(testCase,isempty(shared.sites));
options.requestedDomains = ["south75","clps"];
shared = planDomainDatabase("shared",options);
polar = planDomainDatabase("south75",options);
clps = planDomainDatabase("clps",options);
verifyEqual(testCase,shared.numberOfCandidates,polar.numberOfCandidates+clps.numberOfCandidates);
verifyEqual(testCase,shared.latitudesRad(1:polar.numberOfCandidates),polar.latitudesRad);
end

function testDomainListsFromLauncherJsonAreNormalized(testCase)
options = jsondecode('{"spacingKm":500,"requestedDomains":["south75","south0"]}');
actual = planDomainDatabase("shared",options);
expected = planDomainDatabase("shared",struct("spacingKm",500, ...
    "requestedDomains",["south75","south0"]));
verifyEqual(testCase,actual.options.requestedDomains,["south75","south0"]);
verifyEqual(testCase,actual.latitudesRad,expected.latitudesRad);
verifyEqual(testCase,actual.longitudesRad,expected.longitudesRad);
end

function testRecoverSavedDomainDatabaseWithoutRebuilding(testCase)
[file,chunks] = savedDomainFixture(testCase);
before = arrayfun(@(chunk)dir(chunk.filePath),chunks);
request = struct("sourceSignature","original build provenance");
requestFile = fullfile(fileparts(file),"build_request.mat");
save(requestFile,"request");
finalizeDomainDatabase(file);
saved = load(file,"database");
verifyTrue(testCase,isscalar(saved.database.config.domainComparison));
verifyEqual(testCase,saved.database.config.domainComparison.requestedDomains,["south75","south0"]);
verifyTrue(testCase,isfile(fullfile(fileparts(file),"build_complete.mat")));
root = fileparts(fileparts(file));
for domain = ["south75","south0"]
    view = load(fullfile(root,domain,"optimization_database.mat"),"database");
    verifyEqual(testCase,view.database.meta.sharedSourceFile,file);
    expectedIds = (1:2).';
    if domain=="south75", expectedIds=1; end
    verifyEqual(testCase,view.database.meta.sharedSourceCandidateIds,expectedIds);
end
% An interrupted view phase can be retried after the physical completion marker.
delete(fullfile(root,"south75","optimization_database.mat"));
finalizeDomainDatabase(file);
verifyTrue(testCase,isfile(fullfile(root,"south75","optimization_database.mat")));
verifyEqual(testCase,arrayfun(@(chunk)dir(chunk.filePath),chunks),before);
verifyEqual(testCase,load(requestFile,"request"),struct("request",request));
end

function testDomainRecoveryRejectsConflictingMetadata(testCase)
[file,~] = savedDomainFixture(testCase);
saved = load(file,"database"); database = saved.database;
database.config.domainComparison(2).maximumCandidatesPerChunk = 2;
save(file,"database","-v7.3");
verifyError(testCase,@()finalizeDomainDatabase(file), ...
    "finalizeDomainDatabase:ConflictingMetadata");
verifyFalse(testCase,isfile(fullfile(fileparts(file),"build_complete.mat")));
saved = load(file,"database");
verifyEqual(testCase,[saved.database.config.domainComparison.maximumCandidatesPerChunk],[1 2]);
end

function testDomainRecoveryRejectsUnfinishedChunksBeforeRepair(testCase)
[file,chunks] = savedDomainFixture(testCase);
finalChunkComplete = false;
save(chunks(1).filePath,"finalChunkComplete","-append");
verifyError(testCase,@()finalizeDomainDatabase(file),"buildDomainDatabase:IncompleteChunk");
saved = load(file,"database");
verifyNumElements(testCase,saved.database.config.domainComparison,2);
verifyFalse(testCase,isfile(fullfile(fileparts(file),"build_complete.mat")));
end

function [file,chunks] = savedDomainFixture(testCase)
root = string(tempname); mkdir(root);
testCase.addTeardown(@()rmdir(root,'s'));
folder = fullfile(root,"shared"); mkdir(folder);
chunkFolder = fullfile(folder,"candidate_chunks"); mkdir(chunkFolder);
file = fullfile(folder,"optimization_database.mat");
chunks = optimization.createCandidateChunkPlan(2,2,chunkFolder);
for k = 1:2
    chunks(k).numberOfRetainedCandidates = 1;
    filteredAvailability = true(1,432,2);
    measurementJacobianHistories = zeros(2,6,1,432,2);
    finalChunkComplete = true;
    save(chunks(k).filePath,"filteredAvailability","measurementJacobianHistories", ...
        "finalChunkComplete","-v7.3");
end
database.meta = struct("numberOfOptimizationEpochs",432,"numberOfObjects",2, ...
    "numberOfCandidatesBeforeFiltering",2,"numberOfCandidates",2, ...
    "measurementJacobianStorage","full","measurementJacobianStateColumns",6);
database.config.outputFile = file;
database.config.chunking.numberOfChunks = 2;
% Reproduce struct expansion from the launcher's JSON-decoded cell array.
database.config.domainComparison = struct("domain","shared", ...
    "requestedDomains",{'south75','south0'},"maximumCandidatesPerChunk",1, ...
    "prefilterSiteIds",strings(2,1),"sites",table());
database.study.networkSizes = 1;
database.config.study.networkSizes = 1;
database.config.candidates = struct();
database.candidates = struct("latitudesRad",deg2rad([-80;-10]), ...
    "longitudesRad",[0;0],"originalIndices",uint32([1;2]), ...
    "chunkIndex",uint16([1;2]),"chunkLocalIndex",uint32([1;1]));
database.candidates.prefilter = struct("latitudesRad",database.candidates.latitudesRad, ...
    "longitudesRad",[0;0],"keepMask",true(2,1));
database.visibility = struct("candidateChunks",chunks,"filteredAvailability",[], ...
    "summary",struct("acceptedByCandidateObject",ones(2,2)));
database.tracking.measurementJacobianHistories = [];
database.terrain.maximumTerrainElevationRad = [];
save(file,"database","-v7.3");
end

function tests=testGpuInformationHardware
% Explicit hardware suite: not part of CPU-only smoke CI. No silent fallback.
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
assert(canUseGPU,"gpuInformation:Unavailable","This suite requires a supported GPU.");
end
function testGpuMatchesCpuAndRunsVectorizedGa(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder,(600:600:3*86400).');
[views,~]=derivePaperDomains(db); database=views.global;
[gpuObjective,metadata]=createBatchedInformationObjective(database,"gpu",2,[3 5 7 10]);
networks=[1 2 3;4 5 6;2 8 10;10 2 8]; values=gpuObjective(networks);
for k=1:height(networks)
    expected=optimization.networkObjective(networks(k,:),database,"information");
    verifyEqual(testCase,values(k),expected,'AbsTol',1e-8,'RelTol',1e-9);
end
verifyEqual(testCase,gpuObjective([1 1 2]),database.objective.infeasiblePenalty);
verifyEqual(testCase,gpuObjective([3;2;1]),values(1),'AbsTol',1e-10);
verifyEqual(testCase,metadata.precision,"double");
for count=[5 7 10]
    ids=1:count;
    verifyEqual(testCase,gpuObjective(ids),optimization.networkObjective(ids,database,"information"), ...
        'AbsTol',1e-8,'RelTol',1e-9);
end
clps=views.clps;
[feasible,ids]=optimization.canAssignDistinctAnchors(clps.config.domainComparison.anchorMembership.');
verifyTrue(testCase,feasible);
ids=ids(1:3).';
clpsObjective=createBatchedInformationObjective(clps,"gpu",2);
verifyEqual(testCase,clpsObjective(ids),optimization.networkObjective(ids,clps,"information"), ...
    'AbsTol',1e-8,'RelTol',1e-9);
clear clpsObjective
file=fullfile(folder,"global.mat"); save(file,"database","-v7.3");
request=struct("schemaVersion",1,"databaseFile",file,"outputDirectory",fullfile(folder,"sweep"), ...
    "runCounts",2,"functionEvaluationBudgets",[8 12],"populationSize",4,"baseSeed",1000, ...
    "parallelMode","gpu","maxWorkers",2,"resume",true,"validateOnly",false);
% Release the first resident copy before preparing the sweep's device data.
clear gpuObjective
result=runGaConvergenceStudy(request);
verifyEqual(testCase,result.status,"complete"); verifyEqual(testCase,numel(result.records),4);
for k=1:4
    r=result.records(k);
    verifyEqual(testCase,r.objective,optimization.networkObjective(r.candidateIds,database,"information"), ...
        'AbsTol',1e-8,'RelTol',1e-8);
end
reused=runGaConvergenceStudy(request); verifyEqual(testCase,reused.reusedRuns,4);
end

function testLargeGlobalNetworksOnGpu(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[master,~]=createRevisedStudyFixture(folder,[600;1200;1800],500);
[views,~]=derivePaperDomains(master); database=views.global;
gpuObjective=createBatchedInformationObjective(database,"gpu",2,[25 100]);
for count=[25 100]
    networks=[1:count;2:count+1;count:-1:1];
    observed=gpuObjective(networks);
    for row=1:size(networks,1)
        verifyEqual(testCase,observed(row),optimization.networkObjective(networks(row,:),database,"information"), ...
            'AbsTol',1e-8,'RelTol',1e-9);
    end
end
end

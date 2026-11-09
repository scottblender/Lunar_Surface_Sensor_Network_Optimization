function tests=testBatchedInformationObjective
% CPU execution of the exact scalar GPU kernel; runs on ordinary CI hosts.
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
end
function testBenchmarkEntryBootstrapsFromCleanPath(testCase)
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
entry=fullfile(root,"scripts","batch","run_gpu_ga_benchmark_entry.m");
previousPath=path; previousFolder=pwd; previousRequest=getenv('LUNAR_GPU_BENCHMARK_REQUEST');
testCase.addTeardown(@()path(previousPath));
testCase.addTeardown(@()cd(previousFolder));
testCase.addTeardown(@()setenv('LUNAR_GPU_BENCHMARK_REQUEST',previousRequest));
restoredefaultpath; cd(tempdir); setenv('LUNAR_GPU_BENCHMARK_REQUEST','');
% Same run(absolute-entry-path) dispatch as a fresh -batch MATLAB process.
% The expected request error must occur after project path initialization.
verifyError(testCase,@()runBenchmarkEntry(entry),'gpuBenchmark:RequestFile');
verifyEqual(testCase,string(which('setupProject')),fullfile(root,"setupProject.m"));
verifyEqual(testCase,string(which('runGpuGaBenchmark')),fullfile(root,"scripts","optimization","runGpuGaBenchmark.m"));
end
function testKernelMatchesStackedJosephAcrossFullArc(testCase)
[db,~]=fixture(testCase,(600:600:3*86400).');
% Include correlated, candidate-specific measurement noise.
n=db.meta.numberOfCandidates;
db.measurement.covariance=repmat([1e-8 2e-9;2e-9 2e-8],1,1,n);
for k=1:n, db.measurement.covariance(:,:,k)=db.measurement.covariance(:,:,k)*(1+k/n); end
f=createBatchedInformationObjective(db,"cpu",2);
networks=[1 2 3;4 5 6;2 8 10;10 2 8];
actual=f(networks);
for k=1:size(networks,1)
    expected=optimization.networkObjective(networks(k,:),db,"information");
    verifyEqual(testCase,actual(k),expected,'AbsTol',1e-8,'RelTol',1e-9);
end
verifyEqual(testCase,actual(3),actual(4));
end
function testSharedNoiseAndNoMeasurements(testCase)
[db,folder]=fixture(testCase,[600;1200;1800]);
filteredAvailability=false(db.meta.numberOfCandidates,3,db.meta.numberOfObjects);
file=fullfile(folder,"no_measurements.mat"); save(file,"filteredAvailability","-v7.3");
db.visibility.candidateChunks.filePath=file;
f=createBatchedInformationObjective(db,"cpu");
verifyEqual(testCase,f([1 2 3]),optimization.networkObjective([1 2 3],db,"information"),'AbsTol',1e-9);
end
function testSingleRowBatchesAndInvalidNetworks(testCase)
[db,~]=fixture(testCase,[600;1200;1800]);
f=createBatchedInformationObjective(db,"cpu",1);
a=f([1 2 3]); verifyEqual(testCase,a,f([3;1;2]));
invalid=[1 1 2;0 2 3;1 2 Inf;1 2 3.5;1 2 db.meta.numberOfCandidates+1];
verifyEqual(testCase,f(invalid),repmat(db.objective.infeasiblePenalty,5,1));
verifyEqual(testCase,f(zeros(0,3)),zeros(0,1));
verifyError(testCase,@()f([1 2]),'gpuInformation:NetworkSize');
end
function testLargerNetworksAndClpsAnchorMatching(testCase)
[db,~]=fixture(testCase,[600;1200;1800]);
f=createBatchedInformationObjective(db,"cpu",2,[3 5 7 10]);
for count=[3 5 7 10]
    rows=[1:count;count:-1:1];
    expected=[optimization.networkObjective(rows(1,:),db,"information"); ...
        optimization.networkObjective(rows(2,:),db,"information")];
    verifyEqual(testCase,f(rows),expected,'AbsTol',1e-8,'RelTol',1e-9);
end
db.config.domainComparison.domain="clps";
db.config.domainComparison.enforceSiteGroups=true;
membership=false(db.meta.numberOfCandidates,3);
membership(1:4,:)=[1 1 0;1 0 0;0 0 1;1 0 0];
db.config.domainComparison.anchorMembership=membership;
f=createBatchedInformationObjective(db,"cpu");
verifyEqual(testCase,f([1 2 3]),optimization.networkObjective([1 2 3],db,"information"),'AbsTol',1e-8);
verifyEqual(testCase,f([1 2 4]),db.objective.infeasiblePenalty);
end
function testProductionLargeNetworks(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[master,~]=createRevisedStudyFixture(folder,[600;1200;1800],500);
[views,~]=derivePaperDomains(master); db=views.global;
score=createBatchedInformationObjective(db,"cpu",2,[25 100]);
for count=[25 100]
    networks=[1:count;2:count+1;count:-1:1];
    observed=score(networks);
    for row=1:size(networks,1)
        verifyEqual(testCase,observed(row),optimization.networkObjective(networks(row,:),db,"information"), ...
            'AbsTol',1e-8,'RelTol',1e-9);
    end
    verifyEqual(testCase,score(networks(1,:).'),observed(1));
end
end

function testAllSolversSaveCpuCheckedWinner(testCase)
[db,folder]=fixture(testCase,[600;1200;1800]);
file=fullfile(folder,"global.mat"); database=db; save(file,"database","-v7.3");
f=createBatchedInformationObjective(db,"cpu");
config=struct("databaseFile",file,"outputDirectory",fullfile(folder,"ga"),"optimizer","GA", ...
    "networkSize",3,"populationSize",8,"functionEvaluationBudget",120, ...
    "numberOfRuns",1,"baseSeed",1000,"useParallel",false,"useVectorizedObjective",true,"display","off");
for solver=["GA","PSO","ABC","SURROGATE"]
    config.useVectorizedObjective=solver~="SURROGATE";
    config.optimizer=solver; config.outputDirectory=fullfile(folder,lower(solver));
    a=runGlobalOptimization(config,f); r=a.runStates{1};
    verifyEqual(testCase,r.bestObjective,optimization.networkObjective(r.bestSensorIndices,db,"information"),'AbsTol',1e-8);
    verifyGreaterThanOrEqual(testCase,r.solverFunctionEvaluations,r.searchFunctionEvaluations);
    verifyLessThanOrEqual(testCase,r.searchFunctionEvaluations,120);
end
end
function [db,folder]=fixture(testCase,times)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[master,~]=createRevisedStudyFixture(folder,times); [views,~]=derivePaperDomains(master); db=views.global;
end

function runBenchmarkEntry(entry)
% Give run() an ordinary caller workspace, as the real batch dispatch does.
run(entry);
end

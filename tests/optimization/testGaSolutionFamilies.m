function tests=testGaSolutionFamilies
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
addpath(fullfile(root,"tests","fixtures"));
end
function testCompleteLinkDoesNotChainDistantNetworks(testCase)
d=[0 1 2;1 0 1;2 1 0]; labels=completeLinkNetworkFamilies(d,1.1);
verifyEqual(testCase,numel(unique(labels)),2);
for c=unique(labels).', verifyLessThanOrEqual(testCase,max(d(labels==c,labels==c),[],"all"),1.1); end
verifyEqual(testCase,numel(unique(completeLinkNetworkFamilies(d,2.1))),1);
end
function testPermutationAndSeamDoNotCreateNewFamilies(testCase)
a=[-30 359;0 120;30 240]; b=a([3 1 2],:); b(2,2)=-1;
[~,d]=matchThreeObserverLocations(a,b); verifyEqual(testCase,mean(d),0,'AbsTol',1e-9);
[~,maximum]=matchThreeObserverLocations(a,b,1737.4,"max");
verifyEqual(testCase,max(maximum),0,'AbsTol',1e-9);
labels=completeLinkNetworkFamilies([0 mean(d);mean(d) 0],1);
verifyEqual(testCase,labels,[1;1]);
end
function testBottleneckMatchingDoesNotHideOneLargeMovement(testCase)
a=[13 90;56 340;-53 68]; b=[-37 64;9 125;-3 82];
[~,meanMatched]=matchThreeObserverLocations(a,b);
[~,maxMatched]=matchThreeObserverLocations(a,b,1737.4,"max");
verifyLessThan(testCase,max(maxMatched),max(meanMatched)-100);
[~,permuted]=matchThreeObserverLocations(a([3 1 2],:),b([2 3 1],:),1737.4,"max");
verifyEqual(testCase,max(permuted),max(maxMatched),'AbsTol',1e-9);
end
function testFixedFamiliesDeduplicateAndExportCorrectDenominators(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
a=[-30 0;0 120;30 240]; networks=cat(3,a,a+[0 0.1],a+[0 30],a+[0 60]);
base=struct("requestedBudget",6000,"runIndex",1,"seed",1000, ...
    "candidateIds",[1;2;3],"locations",a,"objective",-10);
r=repmat(base,8,1); values=[-10 -9.995 -9.99 -9];
for k=1:8
    j=1+mod(k-1,4); r(k).requestedBudget=6000+9000*(k>4);
    r(k).runIndex=j; r(k).seed=999+j; r(k).candidateIds=(3*j-2:3*j).';
    r(k).locations=networks(:,:,j); r(k).objective=values(j);
end
r(6).candidateIds=r(6).candidateIds([3 1 2]); r(6).locations=r(6).locations([3 1 2],:);
result=struct("status","complete","records",r); save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
report=analyzeGaSolutionFamilies(folder,ObjectiveGap=0.025,DistanceKm=50,GapScan=0.025,DistanceScanKm=[50 5000]);
verifyEqual(testCase,height(report.families),2);
verifyEqual(testCase,sum(report.families.UniqueNetworks),3); % Not six repeated FE records.
f=report.frequency; verifyEqual(testCase,f.PercentAllRuns(f.Family==0),[25;25]);
verifyEqual(testCase,f.PercentAllRuns(f.Family==1),[50;50]);
verifyEqual(testCase,f.PercentQualifyingRuns(f.Family==1),[200/3;200/3],'AbsTol',1e-10);
verifyEqual(testCase,report.runs.Family(1:4),report.runs.Family(5:8));
verifyEqual(testCase,height(report.pairedTransitions),4);
verifyEqual(testCase,report.sensitivity.NumberOfFamilies,[2;1]);
verifyEqual(testCase,height(report.pairwiseDispersion),4);
verifyEqual(testCase,report.pairwiseDispersion.DependentPairCount,[6;3;6;3]);
verifyEqual(testCase,report.pairwiseDispersion.MedianMeanMatchedKm(1:2), ...
    report.pairwiseDispersion.MedianMeanMatchedKm(3:4),'AbsTol',1e-9);
verifyEqual(testCase,report.frequencyPercent(:,:,1),report.frequencyPercent(:,:,2));
for stem=["reference_free_dispersion_vs_fe","family_objective_distributions", ...
        "family_frequency_vs_fe","family_threshold_sensitivity","unlabeled_geographic_frequency"]
    for ext=[".png",".pdf"]
        info=dir(fullfile(report.outputDirectory,stem+ext)); verifyTrue(testCase,isscalar(info)); verifyGreaterThan(testCase,info.bytes,0);
    end
end
end
function testPathsUseMatchedEndpointsAndDetectDuplicateSites(testCase)
% Three observers are matched between opposite small triangles. At the halfway
% point all three nearest grid sites coincide: mark invalid, do not score a penalty.
db.candidates.latitudesRad=deg2rad([0;0;0;0;0;0;0]);
db.candidates.longitudesRad=deg2rad([0;120;240;20;140;260;10]);
a=[0 0;0 120;0 240]; b=[0 20;0 140;0 260];
report.frequency=table([15000;15000],[1;2],[2;2], ...
    'VariableNames',{'RequestedFE','Family','RunCount'});
report.representativeNetworkIds=[1;2]; report.networkCoordinates=cat(3,a,b);
report.networkIds=[1 2 3;4 5 6]; report.uniqueObjective=[-10;-9.99]; report.options.RadiusKm=1737.4;
p=buildFamilyTransitionPaths(report,db,2,3);
verifyEqual(testCase,[p.Candidate1(1) p.Candidate2(1) p.Candidate3(1)],[1 2 3]);
verifyEqual(testCase,sort([p.Candidate1(end) p.Candidate2(end) p.Candidate3(end)]),[4 5 6]);
verifyTrue(testCase,all(p.ValidDistinctSites)); verifyTrue(testCase,all(isnan(p.Objective)));
% Use very close triangles near one longitude, with one common midpoint site.
db.candidates.latitudesRad=deg2rad([0;1;2;0;1;2;1]);
db.candidates.longitudesRad=deg2rad([0;0;0;20;20;20;10]);
report.networkCoordinates=cat(3,[0 0;1 0;2 0],[0 20;1 20;2 20]);
p=buildFamilyTransitionPaths(report,db,2,3);
verifyFalse(testCase,p.ValidDistinctSites(2));
end
function testDiagnosticChecksFrozenDatabaseAndSavedEndpoints(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
[db,~]=createRevisedStudyFixture(folder); [views,~]=derivePaperDomains(db); database=views.global;
file=fullfile(folder,"global.mat"); save(file,"database","-v7.3");
ids=[1 2 3;4 5 6]; locations=zeros(3,2,2); scores=zeros(2,1);
for k=1:2
    locations(:,:,k)=[rad2deg(database.candidates.latitudesRad(ids(k,:))),rad2deg(database.candidates.longitudesRad(ids(k,:)))];
    scores(k)=optimization.networkObjective(ids(k,:),database,"information");
end
chunk=dir(database.visibility.candidateChunks.filePath);
report=struct("frequency",table([12;12],[1;2],[1;1],'VariableNames',{'RequestedFE','Family','RunCount'}), ...
    "representativeNetworkIds",[1;2],"networkCoordinates",locations,"networkIds",ids,"uniqueObjective",scores, ...
    "observedBestObjective",min(scores),"options",struct("RadiusKm",1737.4,"ObjectiveGap",0.025), ...
    "outputDirectory",folder,"sourceSignature",struct("databaseSha256",analysisFileSha256(file), ...
    "chunkMetadata",struct("path",string(database.visibility.candidateChunks.filePath),"bytes",chunk.bytes,"modified",chunk.datenum)));
reportFile=fullfile(folder,"report.mat"); save(reportFile,"report");
d=evaluateFamilyTransitions(reportFile,file,MaxFamilies=2,PathPoints=3,ExecutionDevice="cpu");
verifyTrue(testCase,all(isfinite(d.paths.Objective(d.paths.ValidDistinctSites))));
verifyEqual(testCase,height(d.summary),1);
report.sourceSignature.databaseSha256="wrong"; save(reportFile,"report");
verifyError(testCase,@()evaluateFamilyTransitions(reportFile,file,ExecutionDevice="cpu"),'networkFamilies:DatabaseMismatch');
report.sourceSignature.databaseSha256=analysisFileSha256(file);
report.sourceSignature.sourceHashes=[reportFile,"wrong"]; save(reportFile,"report");
verifyError(testCase,@()evaluateFamilyTransitions(reportFile,file,ExecutionDevice="cpu"),'networkFamilies:SourceMismatch');
end

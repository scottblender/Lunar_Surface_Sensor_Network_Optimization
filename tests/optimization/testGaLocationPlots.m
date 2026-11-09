function tests=testGaLocationPlots
% Reuse paper helpers; verify run-based frequency and full-global plotting.
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(fileparts(mfilename("fullpath")))); addpath(root); setupProject;
end
function testBinsCountRunsRatherThanSensors(testCase)
a=struct("bestSensorLatitudesRad",deg2rad([-85;-84;0]), ...
    "bestSensorLongitudesRad",deg2rad([5;10;360]));
b=struct("bestSensorLatitudesRad",deg2rad([-85;45;90]), ...
    "bestSensorLongitudesRad",deg2rad([5;60;359]));
f=binNetworkSelectionFrequency({a,b},struct(),-90:10:90,0:30:360);
verifyEqual(testCase,f(1,1),100); % Two sensors in run A count only once.
verifyEqual(testCase,f(10,1),50); % Equator and longitude seam count once, north.
verifyEqual(testCase,f(18,12),50); % North pole belongs to the final latitude bin.
verifyLessThanOrEqual(testCase,max(f,[],"all"),100);
end
function testBestRunScatterAllowsSwapsAndExportsOnlyOneFigure(testCase)
folder=fixture(testCase);
report=plotGaLocationConvergence(folder);
verifyEqual(testCase,report.requestedFE,[6000 12000]);
verifyEqual(testCase,report.independentRuns,2);
verifyEqual(testCase,report.referenceSeed,1001);
verifyEqual(testCase,report.referenceRequestedFE,12000);
verifyEqual(testCase,report.referenceObjective,-20);
verifyEqual(testCase,report.referenceCandidateIds,[1;2;3]);
verifyEqual(testCase,report.reference,[-85 359;0 0;90 180]);
verifyEqual(testCase,height(report.locations),12);
verifyEqual(testCase,report.locations.CandidateId,repmat([1;2;3],4,1));
verifyEqual(testCase,report.locations.DistanceFromBestKm,zeros(12,1),'AbsTol',1e-9);
verifyEqual(testCase,report.locations.Hemisphere,repmat(["south";"north";"north"],4,1));
verifyEqual(testCase,report.locations.LongitudeDeg,repmat([359;0;180],4,1));
files=dir(report.outputDirectory); names=sort(string({files(~[files.isdir]).name}));
verifyEqual(testCase,names,sort(["observer_locations.png","observer_locations.pdf"]));
verifyGreaterThan(testCase,[files(~[files.isdir]).bytes],[0 0]);
% Selecting a different FE cohort also changes which best run is displayed.
report=plotGaLocationConvergence(folder,"",1,RequestedFE=6000);
verifyEqual(testCase,report.requestedFE,6000);
verifyEqual(testCase,report.referenceSeed,1000);
verifyEqual(testCase,report.independentRuns,1);
verifyEqual(testCase,height(report.locations),3);
verifyEqual(testCase,report.referenceObjective,-30);
end
function testObjectiveTiesAndInvalidCohorts(testCase)
folder=fixture(testCase); file=fullfile(folder,"ga_convergence_study.mat");
s=load(file); result=s.result; result.records(3).objective=-20;
save(file,"result");
report=plotGaLocationConvergence(folder);
verifyEqual(testCase,report.referenceRunIndex,1);
verifyError(testCase,@()plotGaLocationConvergence(folder,"",Inf,RequestedFE=9000), ...
    'plotGaLocationConvergence:Budget');
verifyError(testCase,@()plotGaLocationConvergence(folder,"",3), ...
    'plotGaLocationConvergence:Runs');
result.records(4).seed=result.records(3).seed; save(file,"result");
verifyError(testCase,@()plotGaLocationConvergence(folder),'plotGaLocationConvergence:Runs');
result.records(4).seed=1001; result.records(1).seed=999; save(file,"result");
verifyError(testCase,@()plotGaLocationConvergence(folder),'plotGaLocationConvergence:Runs');
result.records(1).seed=1000; result.records(4).locations(1,1)=91; save(file,"result");
verifyError(testCase,@()plotGaLocationConvergence(folder),'plotGaLocationConvergence:Network');
end
function testObserverBoxplotsUseFixedReferenceAndKnownArcDistances(testCase)
folder=fixture(testCase);
reference=[-30 270;0 0;30 120]; offsets=[3 10 20 1 2 0];
r=struct("requestedBudget",6000,"runIndex",1,"seed",1000,"objective",-1, ...
    "candidateIds",[1;2;3],"locations",reference);
records=repmat(r,6,1);
for k=1:6
    records(k).requestedBudget=6000*(1+(k>3));
    records(k).runIndex=1+mod(k-1,3); records(k).seed=999+records(k).runIndex;
    sites=reference; sites(:,1)=sites(:,1)+offsets(k);
    order=circshift(1:3,k); ids=(3*k-2:3*k).';
    records(k).locations=sites(order,:); records(k).candidateIds=ids(order);
end
records(6).objective=-2;
result=struct("status","complete","records",records);
save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
report=plotGaObserverSpread(folder);
verifyEqual(testCase,report.requestedFE,[6000 12000]);
verifyEqual(testCase,report.referenceSeed,1002);
verifyEqual(testCase,report.referenceRequestedFE,12000);
verifyEqual(testCase,report.reference,reference);
verifyEqual(testCase,height(report.locations),18);
expected=repelem(deg2rad(offsets(:))*1737.4,3);
verifyEqual(testCase,report.locations.DistanceFromBestKm,expected,'AbsTol',1e-8);
for observer=1:3
    selected=report.locations.Observer==observer;
    early=report.locations.DistanceFromBestKm(selected & report.locations.RequestedFE==6000);
    late=report.locations.DistanceFromBestKm(selected & report.locations.RequestedFE==12000);
    verifyGreaterThan(testCase,median(early),median(late));
end
saved=readtable(report.locationsCsvFile);
verifyEqual(testCase,saved.DistanceFromBestKm,expected,'AbsTol',1e-8);
for file=[report.pngFile report.pdfFile report.locationsCsvFile]
    info=dir(file); verifyTrue(testCase,isscalar(info)); verifyGreaterThan(testCase,info.bytes,0);
end
end
function testManuscriptEfficiencyMeasuresAdjacentGainsPerRelativeCost(testCase)
folder=fixture(testCase); reference=[-30 270;0 0;30 120];
offsets=[0 0 10 10;0 0 4 4;0 0 8 8];
timings=[100 10 10 10;20 20 20 100;40 40 40 100];
r=struct("requestedBudget",6000,"runIndex",1,"seed",1000,"objective",-1, ...
    "runtimeSeconds",1,"candidateIds",[1;2;3],"locations",reference);
records=repmat(r,12,1);
for k=1:12
    b=ceil(k/4); run=1+mod(k-1,4); order=circshift(1:3,k);
    sites=reference; sites(:,1)=sites(:,1)+offsets(b,run)*[1;0.5;0.25]; ids=(3*k-2:3*k).';
    records(k).requestedBudget=3000*(b+1); records(k).runIndex=run; records(k).seed=999+run;
    records(k).runtimeSeconds=timings(b,run);
    records(k).locations=sites(order,:); records(k).candidateIds=ids(order);
end
records(9).objective=-2;
result=struct("status","complete","records",records);
file=fullfile(folder,"ga_convergence_study.mat"); save(file,"result");
before=findall(groot,'Type','figure');
efficiency=plotGaObserverEfficiency(folder);
verifyEqual(testCase,efficiency.Properties.VariableNames,{'FE','Efficiency'});
verifyEqual(testCase,efficiency.FE,[6000;9000;12000]);
% Mean runtimes are 32.5, 40, and 55 s. Mean objectives are -1, -1,
% and -1.25. The IQRs scale with the widths 10, 4, and 8.
expected=[0.6/(2*(7.5/32.5)); (0.25-1)/(2*(15/40))];
verifyTrue(testCase,isnan(efficiency.Efficiency(1)));
verifyEqual(testCase,efficiency.Efficiency(2:end),expected,'AbsTol',1e-8);
verifyEqual(testCase,findall(groot,'Type','figure'),before);
saved=readtable(fullfile(folder,"observer_location_plots","n_4","fe_6000_9000_12000","fe_efficiency.csv"));
verifyEqual(testCase,saved.Efficiency(2:end),expected,'AbsTol',1e-8);
% A ratio requires a positive increase in runtime.
for k=1:12, result.records(k).runtimeSeconds=10; end
save(file,"result"); efficiency=plotGaObserverEfficiency(folder);
verifyTrue(testCase,all(isnan(efficiency.Efficiency)));
result.records(1).runtimeSeconds=NaN; save(file,"result");
verifyError(testCase,@()plotGaObserverEfficiency(folder),'observerEfficiency:Runtime');
result.records=rmfield(result.records,'runtimeSeconds'); save(file,"result");
verifyError(testCase,@()plotGaObserverEfficiency(folder),'observerEfficiency:Runtime');
end
function testStudy2RunCountPlotsKeepOneReferenceAndNestedSamples(testCase)
folder=fixture(testCase); reference=[-30 359;0 0;30 120]; offsets=[8 6 4 2 1 0];
r=struct("requestedBudget",9000,"runIndex",1,"seed",1000,"objective",-1, ...
    "runtimeSeconds",10,"candidateIds",[1;2;3],"locations",reference);
records=repmat(r,6,1);
for k=1:6
    sites=reference; sites(:,1)=sites(:,1)+offsets(k); sites(1,2)=-1;
    order=circshift(1:3,k); ids=(3*k-2:3*k).';
    records(k).runIndex=k; records(k).seed=999+k;
    records(k).locations=sites(order,:); records(k).candidateIds=ids(order);
end
records(6).objective=-2;
result=struct("status","complete","records",records,"config",struct("runCounts",[2 4 6]));
save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
plots=plotGaRunCountConvergence(folder);
a=plots.polar; b=plots.spread;
verifyEqual(testCase,a.runCounts,[2 4 6]);
verifyEqual(testCase,a.requestedFE,9000);
verifyEqual(testCase,a.referenceSeed,1005);
verifyEqual(testCase,a.reference,reference);
verifyEqual(testCase,a.locations,b.locations);
verifyEqual(testCase,a.referenceCandidateIds,b.referenceCandidateIds);
verifyEqual(testCase,height(a.locations),3*(2+4+6));
for n=[2 4 6]
    t=a.locations(a.locations.IndependentRuns==n,:);
    verifyEqual(testCase,height(t),3*n);
    verifyEqual(testCase,unique(t.RunIndex),(1:n).');
    verifyEqual(testCase,t.DistanceFromBestKm,repelem(deg2rad(offsets(1:n).')*1737.4,3),'AbsTol',1e-8);
    verifyEqual(testCase,nnz(t.Observer==1 & t.Hemisphere=="south"),n);
    if n<6, verifyFalse(testCase,any(t.Seed==a.referenceSeed)); end
end
summary=summarizeGaSearchSettings(a,records);
verifyEqual(testCase,summary.MeanObjectiveError,[1;1;0]/6,'AbsTol',1e-12);
verifyEqual(testCase,summary.MaxDistanceStatisticErrorKm,deg2rad([4;2;0])*1737.4,'AbsTol',1e-8);
verifyEqual(testCase,summary.CumulativeSolverSeconds,[20;40;60]);
verifyEqual(testCase,summary.Efficiency(2),0.25,'AbsTol',1e-12);
verifyTrue(testCase,all(isnan(summary.Efficiency([1 end]))));
small=a.locations(a.locations.IndependentRuns==2,:);
large=a.locations(a.locations.IndependentRuns==6 & a.locations.RunIndex<=2,:);
verifyEqual(testCase,small(:,1:9),large(:,1:9)); % Same coordinates AND distances in each prefix.
verifyEqual(testCase,min(a.locations.DistanceFromBestKm(a.locations.RunIndex==6)),0,'AbsTol',1e-9);
saved=readtable(b.locationsCsvFile);
verifyEqual(testCase,saved.IndependentRuns,a.locations.IndependentRuns);
verifyEqual(testCase,saved.DistanceFromBestKm,a.locations.DistanceFromBestKm,'AbsTol',1e-8);
for file=[a.pngFile a.pdfFile b.pngFile b.pdfFile b.locationsCsvFile]
    info=dir(file); verifyTrue(testCase,isscalar(info)); verifyGreaterThan(testCase,info.bytes,0);
end
% The comparison path is separate from Study 1's FE plots.
verifyTrue(testCase,contains(plots.outputDirectory,"observer_run_count_plots"));
end
function testRunCountPlotValidation(testCase)
folder=fixture(testCase);
verifyError(testCase,@()loadGaObserverPlotData(folder,Inf,[6000 12000],"runs",[2]), ...
    'observerPlots:FixedFE');
verifyError(testCase,@()loadGaObserverPlotData(folder,Inf,12000,"runs",[2 3]), ...
    'plotGaLocationConvergence:Runs');
verifyError(testCase,@()loadGaObserverPlotData(folder,2,12000,"runs",[2]), ...
    'observerPlots:RunCounts');
verifyError(testCase,@()loadGaObserverPlotData(folder,Inf,12000,"runs",[]), ...
    'observerPlots:RunCounts');
a=loadGaObserverPlotData(folder,Inf,12000,"runs",[2]);
verifyEqual(testCase,height(a.locations),6);
verifyEqual(testCase,a.groupRunCounts,2);
verifyEqual(testCase,a.referenceSeed,1001);
end
function testManuscriptPostprocessPairsCheckpointsAndExportsFigures(testCase)
folder=fixture(testCase);
saved=load(fullfile(folder,"ga_convergence_study.mat"),"result");
result=saved.result;
for k=1:4, result.records(k).runtimeSeconds=10*k; end
save(fullfile(folder,"ga_convergence_study.mat"),"result");
benchmarkDirectory=fullfile(folder,"benchmark");
study2Directory=fullfile(folder,"study2");
mkdir(study2Directory);
result.records=result.records(1:2);
result.config.runCounts=2;
result.totalElapsedSeconds=35;
save(fullfile(study2Directory,"ga_convergence_study.mat"),"result");
mkdir(fullfile(benchmarkDirectory,"cpu"));
mkdir(fullfile(benchmarkDirectory,"gpu"));
result.records(1).history=struct("fe",[2 4 6000],"bestJ",[-1 -2 -4]);
result.records(2).history=struct("fe",[4 6000],"bestJ",[-4 -6]);
result.records(1).rawFE=6001;
result.records(2).rawFE=6002;
save(fullfile(benchmarkDirectory,"cpu","ga_convergence_study.mat"),"result");
result.records=flipud(result.records);
result.records(1).history.bestJ=[-6 -8];
save(fullfile(benchmarkDirectory,"gpu","ga_convergence_study.mat"),"result");
benchmark=struct("status","complete","agreement",table(true,'VariableNames',{'Passed'}), ...
    "timing",table(["cpu";"gpu"],'VariableNames',{'Backend'}));
save(fullfile(benchmarkDirectory,"gpu_ga_benchmark.mat"),"benchmark");
out=fullfile(folder,"manuscript");
report=postprocessGaManuscript(benchmarkDirectory,folder,study2Directory,out);
verifyEqual(testCase,report.benchmarkCheckpoints.RecordedFE,[4;6000]);
verifyEqual(testCase,report.benchmarkCheckpoints.MeanCPUObjective,[-3;-5]);
verifyEqual(testCase,report.benchmarkCheckpoints.MeanGPUObjective,[-4;-6]);
verifyEqual(testCase,report.runSummary.CumulativeSolverSeconds,30);
verifyEqual(testCase,report.runSummary.RecordedCampaignWallSeconds,35);
for file=[report.benchmarkFigure,report.feFigure,report.runFigure]
    verifyTrue(testCase,isfile(file));
end
end
function folder=fixture(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
r=struct("requestedBudget",6000,"runIndex",1,"seed",1000,"objective",-30, ...
    "candidateIds",[1;2;3],"locations",[-85 359;0 0;90 180]);
records=repmat(r,4,1);
for k=1:4
    records(k).requestedBudget=6000*(1+(k>2));
    records(k).runIndex=1+mod(k-1,2); records(k).seed=999+records(k).runIndex;
end
records(3).objective=-19; records(4).objective=-20;
records(3).candidateIds=[3;1;2]; records(3).locations=[90 180;-85 -1;0 360];
% Deliberately stale medoid alignment must never be used by the new plot.
result=struct("status","complete","records",records,"analysis",struct("reference",NaN));
save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
end
function testHemisphereProjectionAndDefaultAreCompatible(testCase)
fig=figure("Visible","off"); testCase.addTeardown(@()close(fig));
style=publicationPlotStyle(); style.axisFontSize=10; dem=@(lat,lon)zeros(size(lat));
ax=axes(fig);
plotPolarSelectionMap(ax,ones(9,12)*50,-90:10:0,0:30:360,dem,style);
verifyEqual(testCase,clim(ax),[0 100]);
cla(ax); plotPolarSelectionMap(ax,ones(9,12)*50,0:10:90,0:30:360,dem,style,"north");
verifyEqual(testCase,clim(ax),[0 100]);
labels=string(get(findall(ax,"Type","text"),'String'));
verifyTrue(testCase,any(contains(labels,"60°N")));
verifyFalse(testCase,any(contains(labels,"60°S")));
end

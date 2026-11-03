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
verifyEqual(testCase,report.requestedFE,12000);
verifyEqual(testCase,report.independentRuns,2);
verifyEqual(testCase,report.referenceSeed,1001);
verifyEqual(testCase,report.referenceObjective,-20);
verifyEqual(testCase,report.referenceCandidateIds,[1;2;3]);
verifyEqual(testCase,report.reference,[-85 359;0 0;90 180]);
verifyEqual(testCase,height(report.locations),6);
verifyEqual(testCase,report.locations.CandidateId,[1;2;3;1;2;3]);
verifyEqual(testCase,report.locations.DistanceFromBestKm,zeros(6,1),'AbsTol',1e-9);
verifyEqual(testCase,report.locations.Hemisphere,["south";"north";"north";"south";"north";"north"]);
verifyEqual(testCase,report.locations.LongitudeDeg,[359;0;180;359;0;180]);
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
result.records(4).seed=1001; result.records(4).locations(1,1)=91; save(file,"result");
verifyError(testCase,@()plotGaLocationConvergence(folder),'plotGaLocationConvergence:Network');
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

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
function testSavedSweepExportsBothHemispheresAndExactSites(testCase)
folder=string(tempname); mkdir(folder); testCase.addTeardown(@()rmdir(folder,'s'));
r=struct("requestedBudget",6000,"runIndex",1,"seed",1000, ...
    "candidateIds",[1;2;3],"locations",[-85 5;-84 10;0 0]);
records=repmat(r,4,1);
for k=1:4
    records(k).requestedBudget=6000*(1+(k>2));
    records(k).runIndex=1+mod(k-1,2); records(k).seed=999+records(k).runIndex;
    if records(k).runIndex==2
        records(k).candidateIds=[1;4;5]; records(k).locations=[-85 5;45 60;90 359];
    end
end
result=struct("status","complete","config",struct("runCounts",[2]), ...
    "records",records,"analysis",analyzeGaLocationConvergence(records,2));
save(fullfile(folder,"ga_convergence_study.mat"),"result","-v7.3");
report=plotGaLocationConvergence(folder);
verifySize(testCase,report.frequencyPercent,[18 12 2]);
verifyEqual(testCase,report.frequencyPercent(1,1,:),ones(1,1,2)*100);
verifyEqual(testCase,height(report.bins),18*12*2);
exact=report.exactCandidateFrequency;
verifyEqual(testCase,exact.SelectionPercent(exact.CandidateId==1),[100;100]);
verifyEqual(testCase,exact.SelectionPercent(exact.CandidateId==2),[50;50]);
verifyEqual(testCase,height(report.locationSummary),6);
for name=["selection_frequency_vs_fe.png","selection_frequency_vs_fe.pdf", ...
        "location_consistency_vs_fe.png","location_consistency_vs_fe.pdf", ...
        "selection_frequency_bins.csv","exact_candidate_frequency.csv","location_frequency_report.mat"]
    info=dir(fullfile(report.outputDirectory,name));
    verifyTrue(testCase,isscalar(info)); verifyGreaterThan(testCase,info.bytes,0);
end
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

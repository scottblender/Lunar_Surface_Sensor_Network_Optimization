function results=postprocessGaManuscript(benchmarkDirectory,study1Directory,study2Directory,outputDirectory)
% Generate the three search-setting figures and their tables from saved GA data.
arguments
    benchmarkDirectory (1,1) string
    study1Directory (1,1) string
    study2Directory (1,1) string
    outputDirectory (1,1) string = "results/manuscript_search"
end
benchmark=load(fullfile(benchmarkDirectory,"gpu_ga_benchmark.mat"),"benchmark");
benchmark=benchmark.benchmark;
assert(benchmark.status=="complete" && ~isempty(benchmark.agreement) && all(benchmark.agreement.Passed), ...
    "manuscriptSearch:Benchmark","Use a completed benchmark with passing objective agreement.");
cpu=loadSweep(fullfile(benchmarkDirectory,"cpu"));
gpu=loadSweep(fullfile(benchmarkDirectory,"gpu"));
study1=loadSweep(study1Directory);
study2=loadSweep(study2Directory);
assert(numel(unique([study2.records.requestedBudget]))==1, ...
    "manuscriptSearch:FixedFE","Study 2 must contain one fixed FE budget.");
fe=loadGaObserverPlotData(study1Directory);
runs=loadGaObserverPlotData(study2Directory,Inf,[],"runs");
[feSummary,feObservers]=summarizeGaSearchSettings(fe,study1.records);
[runSummary,runObservers]=summarizeGaSearchSettings(runs,study2.records);
runSummary.RequestedFE=repmat(runs.requestedFE,height(runSummary),1);
if isfield(study2,"totalElapsedSeconds")
    wallTime=NaN(height(runSummary),1);
    wallTime(runSummary.IndependentRuns==numel(study2.records))=study2.totalElapsedSeconds;
    runSummary.RecordedCampaignWallSeconds=wallTime;
end
[checkpoints,benchmarkRuns]=compareBenchmarks(cpu.records,gpu.records);

if ~isfolder(outputDirectory), mkdir(outputDirectory); end
feSummary.Properties.VariableNames{1}='RequestedFE';
feObservers.Properties.VariableNames{1}='RequestedFE';
runSummary=removevars(runSummary,"Setting");
runSummary=renamevars(runSummary,"PreviousSetting","PreviousIndependentRuns");
runObservers.Properties.VariableNames{1}='IndependentRuns';
writetable(feSummary,fullfile(outputDirectory,"fe_budget_summary.csv"));
writetable(feObservers,fullfile(outputDirectory,"fe_observer_distances.csv"));
writetable(runSummary,fullfile(outputDirectory,"independent_run_summary.csv"));
writetable(runObservers,fullfile(outputDirectory,"independent_run_observer_distances.csv"));
writetable(benchmark.timing,fullfile(outputDirectory,"cpu_gpu_timing.csv"));
writetable(benchmark.agreement,fullfile(outputDirectory,"cpu_gpu_agreement.csv"));
writetable(benchmarkRuns,fullfile(outputDirectory,"cpu_gpu_runs.csv"));
writetable(checkpoints,fullfile(outputDirectory,"cpu_gpu_checkpoints.csv"));
results=struct("outputDirectory",outputDirectory,"feSummary",feSummary,"runSummary",runSummary, ...
    "feReferenceSeed",fe.referenceSeed,"runReferenceSeed",runs.referenceSeed, ...
    "study2RequestedFE",runs.requestedFE,"benchmarkCheckpoints",checkpoints);
results.benchmarkFigure=plotBenchmark(benchmarkRuns,checkpoints,outputDirectory);
results.feFigure=plotBudgets(feSummary,outputDirectory);
results.runFigure=plotRunCounts(runSummary,runObservers,outputDirectory);
disp(feSummary(:,["RequestedFE","Efficiency"]));
disp(runSummary(:,["IndependentRuns","MeanObjectiveError","MaxDistanceStatisticErrorKm","Efficiency"]));
end

function result=loadSweep(directory)
saved=load(fullfile(directory,"ga_convergence_study.mat"),"result");
result=saved.result;
assert(result.status=="complete" && ~isempty(result.records), ...
    "manuscriptSearch:Incomplete","Use a completed sweep in %s.",directory);
end

function [checkpoints,paired]=compareBenchmarks(cpu,gpu)
[cpuSeeds,order]=sort([cpu.seed].');
cpu=cpu(order);
[gpuSeeds,order]=sort([gpu.seed].');
gpu=gpu(order);
assert(isequal(cpuSeeds,gpuSeeds) && numel(unique(cpuSeeds))==numel(cpuSeeds) && ...
    numel(unique([[cpu.requestedBudget],[gpu.requestedBudget]]))==1, ...
    "manuscriptSearch:BenchmarkPairs","Benchmark requires paired seeds at one requested FE budget.");
records=[cpu(:);gpu(:)];
common=records(1).history.fe(:);
for k=1:numel(records)
    common=intersect(common,records(k).history.fe(:));
end
assert(~isempty(common),"manuscriptSearch:Checkpoints","No FE checkpoints are shared by every CPU and GPU run.");
objective=zeros(numel(common),numel(records));
for k=1:numel(records)
    history=records(k).history;
    [~,index]=ismember(common,history.fe(:));
    objective(:,k)=reshape(history.bestJ(index),[],1);
end
n=numel(cpu);
checkpoints=table(common,mean(objective(:,1:n),2),mean(objective(:,n+1:end),2), ...
    'VariableNames',{'RecordedFE','MeanCPUObjective','MeanGPUObjective'});
paired=table(cpuSeeds,[cpu.requestedBudget].',[cpu.rawFE].',[gpu.rawFE].', ...
    [cpu.runtimeSeconds].',[gpu.runtimeSeconds].',[cpu.objective].',[gpu.objective].', ...
    'VariableNames',{'Seed','RequestedFE','CPURawFE','GPURawFE','CPUSolverSeconds', ...
    'GPUSolverSeconds','CPUFinalObjective','GPUFinalObjective'});
end

function file=plotBenchmark(paired,checkpoints,out)
[fig,layout,cleanup]=paperLayout(1,2,3.4); %#ok<ASGLU>
style=publicationPlotStyle();
ax=nexttile(layout);
group=[ones(height(paired),1);2*ones(height(paired),1)];
boxchart(ax,group,[paired.CPUSolverSeconds;paired.GPUSolverSeconds],"BoxFaceColor",style.blueColor);
xticks(ax,[1 2]); xticklabels(ax,["CPU","GPU"]);
ylabel(ax,"Solver runtime per run (s)"); panel(ax,"(a)");
ax=nexttile(layout);
hold(ax,"on");
plot(ax,checkpoints.RecordedFE,checkpoints.MeanCPUObjective,"-","Color",style.blueColor,"LineWidth",1.4);
plot(ax,checkpoints.RecordedFE,checkpoints.MeanGPUObjective,"--","Color",style.orangeColor,"LineWidth",1.4);
xlabel(ax,"Recorded FE"); ylabel(ax,"Mean best objective");
legend(ax,["CPU","GPU"],"Location","best","Box","off"); panel(ax,"(b)");
file=exportPaper(fig,out,"cpu_gpu_comparison",3.4);
end

function file=plotBudgets(t,out)
[fig,layout,cleanup]=paperLayout(2,2,5.6); %#ok<ASGLU>
labels=["Mean final objective","Mean runtime per run (s)","Mean distance IQR (km)","Marginal efficiency"];
values=[t.MeanFinalObjective,t.MeanSolverSecondsPerRun,t.MeanIQRKm,t.Efficiency];
for k=1:numel(labels)
    ax=nexttile(layout);
    plotSeries(ax,t.RequestedFE,values(:,k),"Requested FE per run",labels(k));
    panel(ax,"("+string(char('a'+k-1))+")");
    if k==4, yline(ax,0,":"); end
end
file=exportPaper(fig,out,"fe_budget_comparison",5.6);
end

function file=plotRunCounts(t,observers,out)
[fig,layout,cleanup]=paperLayout(3,2,7.8); %#ok<ASGLU>
x=t.IndependentRuns;
ax=nexttile(layout);
plotSeries(ax,x,t.MeanFinalObjective,"Independent runs","Mean final objective"); panel(ax,"(a)");
ax=nexttile(layout);
plotSeries(ax,x,t.CumulativeSolverSeconds/3600,"Independent runs","Cumulative solver time (h)"); panel(ax,"(b)");
labels=["Median distance (km)","Upper distance quartile (km)","Distance IQR (km)"];
variables=["MedianKm","Q75Km","IQRKm"];
style=publicationPlotStyle();
colors=[style.blueColor;style.orangeColor;style.greenColor];
markers=["-o","--s",":^"];
for k=1:numel(variables)
    ax=nexttile(layout);
    hold(ax,"on");
    values=observers.(variables(k));
    for observer=1:3
        plot(ax,x,values(observers.Observer==observer),markers(observer), ...
            "Color",colors(observer,:),"MarkerSize",4,"LineWidth",1.3);
    end
    xlabel(ax,"Independent runs"); ylabel(ax,labels(k));
    setRunTicks(ax,x);
    panel(ax,"("+string(char('c'+k-1))+")");
end
key=legend(ax,["Observer 1","Observer 2","Observer 3"],"Box","off");
key.Layout.Tile=6;
file=exportPaper(fig,out,"independent_run_comparison",7.8);
end

function [fig,layout,cleanup]=paperLayout(rows,columns,height)
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 7.5 height]);
cleanup=onCleanup(@()close(fig));
layout=tiledlayout(fig,rows,columns,"TileSpacing","compact","Padding","compact");
end

function plotSeries(ax,x,y,xLabel,yLabel)
style=publicationPlotStyle();
plot(ax,x,y,"-o","Color",style.blueColor,"LineWidth",1.4,"MarkerSize",4);
xlabel(ax,xLabel); ylabel(ax,yLabel);
if xLabel=="Independent runs", setRunTicks(ax,x); else, xticks(ax,x); end
end

function setRunTicks(ax,x)
ax.XScale="log";
xticks(ax,x);
xticklabels(ax,string(x));
end

function panel(ax,label)
ax.TickDir="out";
ax.Box="off";
grid(ax,"on");
text(ax,0.02,0.98,label,"Units","normalized","VerticalAlignment","top","FontWeight","bold");
end

function file=exportPaper(fig,out,stem,height)
file=fullfile(out,stem+".eps");
exportManuscriptFigure(fig,file,7.5,height);
end

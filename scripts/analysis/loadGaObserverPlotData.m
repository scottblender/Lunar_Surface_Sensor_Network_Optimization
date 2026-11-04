function report=loadGaObserverPlotData(studyDirectory,independentRuns,requestedFE,compareBy,runCounts)
% LOADGAOBSERVERPLOTDATA - Common FE or nested run-count plot preparation.
arguments
    studyDirectory (1,1) string
    independentRuns (1,1) double = Inf
    requestedFE (1,:) double = []
    compareBy (1,1) string {mustBeMember(compareBy,["fe","runs"])} = "fe"
    runCounts (1,:) double = []
end
if compareBy=="fe"
    assert(isempty(runCounts),"observerPlots:RunCounts","RunCounts requires CompareBy='runs'.");
    report=loadGaObserverLocations(studyDirectory,independentRuns,requestedFE);
    report.groupValues=report.requestedFE;
    report.groupVariable="RequestedFE";
    report.groupLabel="Requested FE per run";
    report.groupSuffix="fe";
    report.groupRunCounts=repmat(report.independentRuns,size(report.groupValues));
    report.panelLabels="FE "+string(report.groupValues);
    report.sharedTitle=sprintf("%d runs/FE | Reference: seed %d, FE %d, J = %.6f", ...
        report.independentRuns,report.referenceSeed,report.referenceRequestedFE,report.referenceObjective);
    return;
end
% First load and validate the full cohort once, selecting one fixed FE budget.
if isempty(requestedFE), requestedFE=Inf; end
assert(isscalar(requestedFE),"observerPlots:FixedFE","Run-count comparisons require one FE budget.");
assert(isinf(independentRuns) && independentRuns>0,"observerPlots:RunCounts", ...
    "Use RunCounts to select prefixes for a run-count comparison.");
saved=load(fullfile(studyDirectory,"ga_convergence_study.mat"),"result");
if isempty(runCounts)
    assert(isfield(saved.result,"config") && isfield(saved.result.config,"runCounts"), ...
        "observerPlots:RunCounts","Specify RunCounts, or use a sweep with saved config.runCounts.");
    runCounts=double(saved.result.config.runCounts(:).');
end
validateattributes(runCounts,{'double'},{'vector','integer','>=',2,'finite'});
runCounts=sort(unique(runCounts));
report=loadGaObserverLocations(studyDirectory,max(runCounts),requestedFE);
% Every prefix uses this same alignment/reference, including prefixes that do
% not contain the best run. Do not recompute a best network for each count.
base=report.locations; subsets=cell(numel(runCounts),1);
for k=1:numel(runCounts)
    t=base(base.RunIndex<=runCounts(k),:);
    t.IndependentRuns=repmat(runCounts(k),height(t),1);
    subsets{k}=t;
end
report.locations=vertcat(subsets{:});
report.runCounts=runCounts;
report.groupValues=runCounts;
report.groupVariable="IndependentRuns";
report.groupLabel="Independent runs";
report.groupSuffix="runs";
report.groupRunCounts=runCounts;
report.panelLabels="N "+string(runCounts);
report.sharedTitle=sprintf("FE %d | Reference: seed %d, N %d, J = %.6f", ...
    report.referenceRequestedFE,report.referenceSeed,max(runCounts),report.referenceObjective);
report.referenceRule="lowest objective at selected FE in largest displayed run prefix; fixed across all run counts; ties use lowest run index; observers sorted by latitude then longitude";
report.outputDirectory=fullfile(studyDirectory,"observer_run_count_plots", ...
    "fe_"+string(report.referenceRequestedFE),"n_"+join(string(runCounts),"_"));
end

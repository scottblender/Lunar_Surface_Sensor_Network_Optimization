function diagnostic=evaluateFamilyTransitions(reportFile,databaseFile,options)
% EVALUATEFAMILYTRANSITIONS - Separate, GPU-first sampled-path diagnostic.
% This does not optimize/refine networks or change convergence results. A bad
% segment along one sampled path is not proof that every connecting path is bad.
arguments
    reportFile (1,1) string
    databaseFile (1,1) string
    options.MaxFamilies (1,1) double {mustBeInteger,mustBePositive} = 4
    options.PathPoints (1,1) double {mustBeInteger,mustBePositive} = 21
    options.ExecutionDevice (1,1) string {mustBeMember(options.ExecutionDevice,["cpu","gpu"])} = "gpu"
    options.OutputDirectory (1,1) string = ""
end
assert(options.PathPoints>=3,"networkFamilies:PathPoints","Use at least three path points.");
s=load(reportFile,"report"); report=s.report;
assert(isfield(report.sourceSignature,"databaseSha256"),"networkFamilies:Provenance", ...
    "Generate the family report beside the original ga_sweep_manifest.mat to verify the frozen database.");
assert(analysisFileSha256(databaseFile)==report.sourceSignature.databaseSha256, ...
    "networkFamilies:DatabaseMismatch","Supplied database differs from the frozen sweep database.");
% Check physical chunk metadata against the original frozen manifest as well.
assert(isfield(report.sourceSignature,"chunkMetadata"),"networkFamilies:Provenance","Missing frozen chunk provenance.");
for k=1:numel(report.sourceSignature.chunkMetadata)
    expected=report.sourceSignature.chunkMetadata(k); actual=dir(expected.path);
    assert(isscalar(actual) && actual.bytes==expected.bytes && actual.datenum==expected.modified, ...
        "networkFamilies:ChunkMismatch","Frozen physical chunk changed or is missing: %s",expected.path);
end
s=load(databaseFile,"database"); database=s.database;
assert(database.config.domainComparison.domain=="global" && ~database.config.domainComparison.enforceSiteGroups, ...
    "networkFamilies:Domain","Transition diagnostic requires the same global view.");
assert(abs(database.config.moon.radiusKm-report.options.RadiusKm)<1e-10, ...
    "networkFamilies:Radius","Family-distance radius differs from the frozen database.");
paths=buildFamilyTransitionPaths(report,database,options.MaxFamilies,options.PathPoints);
out=options.OutputDirectory; if strlength(out)==0, out=fullfile(report.outputDirectory,"transitions"); end
if ~isfolder(out), mkdir(out); end
metadata=struct(); timer=tic; evaluationCount=0;
if ~isempty(paths)
    [objective,metadata]=createBatchedInformationObjective(database,options.ExecutionDevice);
    valid=find(paths.ValidDistinctSites);
    ids=sort([paths.Candidate1(valid),paths.Candidate2(valid),paths.Candidate3(valid)],2);
    [uniqueIds,~,back]=unique(ids,'rows','sorted');
    scores=objective(uniqueIds); paths.Objective(valid)=scores(back); evaluationCount=height(uniqueIds);
    endpoints=find(paths.Fraction==0 | paths.Fraction==1);
    for k=endpoints.'
        expected=paths.FromSavedObjective(k); if paths.Fraction(k)==1, expected=paths.ToSavedObjective(k); end
        assert(abs(paths.Objective(k)-expected)<=1e-8*max(1,abs(expected)), ...
            "networkFamilies:EndpointMismatch","Path endpoint disagrees with its saved objective.");
        checked=optimization.networkObjective([paths.Candidate1(k),paths.Candidate2(k),paths.Candidate3(k)],database,"information");
        assert(abs(paths.Objective(k)-checked)<=1e-8*max(1,abs(checked)), ...
            "networkFamilies:EndpointMismatch","Path endpoint fails independent CPU agreement.");
    end
    clear objective
end
rows={};
for pair=unique(paths.Pair).'
    t=paths(paths.Pair==pair,:); values=t.Objective(isfinite(t.Objective));
    rows{end+1,1}=struct("Pair",pair,"FromFamily",t.FromFamily(1),"ToFamily",t.ToFamily(1), ...
        "SampledPoints",height(t),"ValidPoints",nnz(t.ValidDistinctSites), ...
        "CompleteSampledPath",all(t.ValidDistinctSites), ...
        "FromObjective",t.FromSavedObjective(1),"ToObjective",t.ToSavedObjective(1), ...
        "MaximumSampledObjective",max(values), ...
        "RiseAboveWorseEndpoint",max(values)-max(t.FromSavedObjective(1),t.ToSavedObjective(1)), ...
        "MaximumSnapDistanceKm",max(t.MaxSnapDistanceKm)); %#ok<AGROW>
end
summary=table(); if ~isempty(rows), summary=struct2table(vertcat(rows{:})); end
writetable(paths,fullfile(out,"family_transition_paths.csv"));
if ~isempty(summary), writetable(summary,fullfile(out,"family_transition_summary.csv")); end
diagnostic=struct("options",options,"paths",paths,"summary",summary,"metadata",metadata, ...
    "sourceReportSha256",analysisFileSha256(reportFile),"databaseSha256",report.sourceSignature.databaseSha256, ...
    "uniqueDiagnosticEvaluations",evaluationCount,"elapsedSeconds",toc(timer), ...
    "outputDirectory",out,"interpretation", ...
    "sampled snapped great-circle paths only; incomplete paths and alternate routes prevent proof of distinct attraction basins");
save(fullfile(out,"family_transition_diagnostic.mat"),"diagnostic","-v7.3");
if ~isempty(paths)
    fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 9 5]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    ax=axes(fig); hold(ax,"on");
    for pair=unique(paths.Pair).'
        t=paths(paths.Pair==pair,:);
        plot(ax,t.Fraction,t.Objective-report.observedBestObjective,"-o","MarkerSize",3, ...
            "DisplayName",sprintf("Family %d to %d",t.FromFamily(1),t.ToFamily(1)));
    end
    yline(ax,report.options.ObjectiveGap,"k--","Near-best tolerance","HandleVisibility","off");
    xlabel(ax,"Fraction along matched great-circle path (snapped to candidate grid)");
    ylabel(ax,"Objective minus best observed objective (lower is better)");
    title(ax,"Sampled path profiles: barriers on these routes do not prove separate modes");
    legend(ax,"Location","eastoutside"); grid(ax,"on");
    exportgraphics(fig,fullfile(out,"family_transition_profiles.png"),"Resolution",200);
    exportgraphics(fig,fullfile(out,"family_transition_profiles.pdf"),"ContentType","vector");
end
fprintf("Family transition diagnostic: %d distinct network evaluations; %s\n",evaluationCount,out);
end

function tests = testManuscriptArtifactLayout
% Data-free checks for figure decoration bounds and the manuscript inventory.
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
end

function testTrackingHeatmapsFit(testCase)
style = publicationPlotStyle();
for nObjects = [4 20]
    rms = reshape(logspace(-3,1,nObjects*4*2),nObjects,4,2);
    observable = 50*ones(size(rms));
    if nObjects == 4
        names = ["LRO";"Chandrayaan-1";"Danuri";"Queqiao-2"];
    else
        names = compose("Spacecraft %02d",1:nObjects);
    end
    fig = plotManuscriptTrackingHeatmaps(rms,observable, ...
        names,[3 5 7 10],["information","coverage"],"Layout regression");
    cleanup = onCleanup(@()close(fig));
    drawnow;
    fig.Units = "inches";
    verifyGreaterThanOrEqual(testCase,fig.Position(3),style.heatmapWidthInches);
    verifyGreaterThanOrEqual(testCase,fig.Position(4),style.heatmapHeightInches);
    verifyNumElements(testCase,findall(fig,"Type","colorbar"),2);
    axesHandles = findall(fig,"Type","axes");
    verifyNumElements(testCase,axesHandles,4);
    fig.Units = "pixels"; canvas = fig.Position(3:4);
    for ax = axesHandles.'
        ax.Units = "pixels";
        position = getpixelposition(ax,true);
        inset = ax.TightInset;
        low = position(1:2)-inset(1:2);
        high = position(1:2)+position(3:4)+inset(3:4);
        verifyGreaterThanOrEqual(testCase,low,[-2 -2]);
        verifyLessThanOrEqual(testCase,high,canvas+2);
    end
    clear cleanup
end
end

function testManuscriptInventoryExcludesDiagnostics(testCase)
folder = string(tempname); mkdir(folder);
cleanup = onCleanup(@()rmdir(folder,"s")); %#ok<NASGU>
manifest = validateManuscriptArtifacts(folder);
verifyTrue(testCase,any(manifest.File=="constraint_screening_rso01.eps"));
verifyFalse(testCase,any(startsWith(manifest.File,"screening_breakdown_")));
verifyTrue(testCase,any(manifest.File=="design_rso_family_mcrf_3d.eps"));
verifyFalse(testCase,any(manifest.File=="optimization_rso_population.csv"));
verifyFalse(testCase,any(contains(manifest.File,"summary") & ...
    manifest.File~="network_summary.csv"));
% The RSO population table is replaced by the MCRF family figure; P0 remains
% a second CSV supplying the IOD table.
verifyEqual(testCase,sum(manifest.Kind=="table"),11);
verifyEqual(testCase,sum(startsWith(manifest.File,"monte_carlo_")),8);
end

function testArchivePreservesUnrelatedFiles(testCase)
parent = string(tempname); mkdir(parent);
cleanup = onCleanup(@()rmdir(parent,"s")); %#ok<NASGU>
folder = fullfile(parent,"paper"); mkdir(folder);
writelines("old figure",fullfile(folder,"screening_breakdown_information.eps"));
writelines("keep",fullfile(folder,"unrelated.csv"));
archiveNonManuscriptArtifacts(folder);
verifyFalse(testCase,isfile(fullfile(folder,"screening_breakdown_information.eps")));
verifyTrue(testCase,isfile(fullfile(parent,"paper_diagnostics_archive", ...
    "screening_breakdown_information.eps")));
verifyTrue(testCase,isfile(fullfile(folder,"unrelated.csv")));
end

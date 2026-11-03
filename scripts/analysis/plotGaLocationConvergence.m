function report=plotGaLocationConvergence(studyDirectory,demFile,independentRuns,options)
% PLOTGALOCATIONCONVERGENCE - One polar figure of sites matched to the best run.
% Saved data only. Columns are observers; rows are south/north hemispheres.
% Default: all independent runs at the largest saved requested FE budget.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,1) double = Inf
end
file=fullfile(studyDirectory,"ga_convergence_study.mat");
assert(isfile(file),"plotGaLocationConvergence:Missing","Missing completed sweep: %s",file);
saved=load(file,"result"); result=saved.result;
assert(result.status=="complete" && ~isempty(result.records), ...
    "plotGaLocationConvergence:Incomplete","Use a completed convergence sweep.");
requestedFE=options.RequestedFE;
if isinf(requestedFE) && requestedFE>0, requestedFE=max([result.records.requestedBudget]); end
validateattributes(requestedFE,{'double'},{'scalar','integer','positive','finite'});
records=result.records([result.records.requestedBudget]==requestedFE);
assert(~isempty(records),"plotGaLocationConvergence:Budget","No saved runs at FE %d.",requestedFE);
if isinf(independentRuns) && independentRuns>0, independentRuns=max([records.runIndex]); end
validateattributes(independentRuns,{'double'},{'scalar','integer','positive','finite'});
records=records([records.runIndex]<=independentRuns);
[~,order]=sort([records.runIndex]); records=records(order);
assert(numel(records)==independentRuns && isequal([records.runIndex],1:independentRuns) && ...
    numel(unique([records.seed]))==independentRuns, ...
    "plotGaLocationConvergence:Runs","Expected one distinct seed for every run in the selected prefix.");
for k=1:numel(records)
    ids=double(records(k).candidateIds(:)); sites=records(k).locations;
    assert(numel(ids)==3 && numel(unique(ids))==3 && all(isfinite(ids) & ids>0 & ids==round(ids)) && ...
        isequal(size(sites),[3 2]) && all(isfinite(sites),"all") && all(abs(sites(:,1))<=90), ...
        "plotGaLocationConvergence:Network","Each run must contain three valid physical sites.");
    records(k).locations(:,2)=mod(sites(:,2),360);
end
objectives=[records.objective];
assert(all(isfinite(objectives)),"plotGaLocationConvergence:Objective","Objectives must be finite.");
% Records are run-index sorted: ties choose the lowest run index.
[~,bestIndex]=min(objectives); best=records(bestIndex);
% Observer numbers are display labels anchored to this best network.
[reference,order]=sortrows(best.locations,[1 2]); referenceIds=best.candidateIds(order);
rows=cell(independentRuns,1);
for k=1:independentRuns
    [order,distance]=matchThreeObserverLocations(reference,records(k).locations);
    sites=records(k).locations(order,:); ids=records(k).candidateIds(order);
    hemisphere=repmat("south",3,1); hemisphere(sites(:,1)>=0)="north";
    rows{k}=table(repmat(requestedFE,3,1),repmat(records(k).runIndex,3,1), ...
        repmat(records(k).seed,3,1),(1:3).',ids(:),sites(:,1),sites(:,2),distance,hemisphere, ...
        'VariableNames',{'RequestedFE','RunIndex','Seed','Observer','CandidateId', ...
        'LatitudeDeg','LongitudeDeg','DistanceFromBestKm','Hemisphere'});
end
locations=vertcat(rows{:});
dem=@(lat,lon)zeros(size(lat));
if strlength(demFile)>0
    [dem,~]=digitalElevationModel.loadTriaxialLunarDem(demFile);
end
style=publicationPlotStyle(); style.axisFontSize=10;
fig=figure("Name","Observer locations relative to best run","Color","white", ...
    "Units","inches","Position",[0.5 0.5 12 8.5],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,3,"TileSpacing","compact","Padding","compact");
for hemisphere=["south","north"]
    for observer=1:3
        ax=nexttile(layout); latitudeEdges=-90:10:0;
        if hemisphere=="north", latitudeEdges=0:10:90; end
        % Reuse the paper's geographic projection and terrain, without bins.
        plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
        selected=locations.Observer==observer & locations.Hemisphere==hemisphere;
        [x,y]=projectSites(locations.LatitudeDeg(selected),locations.LongitudeDeg(selected),hemisphere);
        points=scatter3(ax,x,y,4*ones(size(x)),24,[0.05 0.35 0.65],"filled", ...
            "MarkerFaceAlpha",0.5,"MarkerEdgeColor","none");
        x=NaN; y=NaN;
        if (reference(observer,1)>=0)==(hemisphere=="north")
            [x,y]=projectSites(reference(observer,1),reference(observer,2),hemisphere);
        end
        star=scatter3(ax,x,y,5,180,[0.85 0.08 0.08],"p","filled", ...
            "MarkerEdgeColor","white","LineWidth",0.7);
        title(ax,sprintf("Observer %d | %s | %d/%d runs",observer,hemisphere,nnz(selected),independentRuns), ...
            "FontSize",11);
    end
end
key=legend(ax,[points star],["Independent-run location","Best-run location"], ...
    "Orientation","horizontal","FontSize",11);
key.Layout.Tile="south";
title(layout,sprintf("3 observers | FE %d | %d independent runs | best seed %d | J = %.6f", ...
    requestedFE,independentRuns,best.seed,best.objective),"FontSize",13);
subtitle(layout,"Sites matched one-to-one to the best network; observer labels may swap", ...
    "FontSize",11);
out=fullfile(studyDirectory,"observer_location_plots",sprintf("n_%d",independentRuns),sprintf("fe_%d",requestedFE));
if ~isfolder(out), mkdir(out); end
pngFile=fullfile(out,"observer_locations.png"); pdfFile=fullfile(out,"observer_locations.pdf");
exportgraphics(fig,pngFile,"Resolution",220);
exportgraphics(fig,pdfFile,"ContentType","image","Resolution",220);
report=struct("outputDirectory",out,"pngFile",pngFile,"pdfFile",pdfFile, ...
    "requestedFE",requestedFE,"independentRuns",independentRuns, ...
    "referenceSeed",best.seed,"referenceRunIndex",best.runIndex,"referenceObjective",best.objective, ...
    "reference",reference,"referenceCandidateIds",referenceIds(:),"locations",locations, ...
    "referenceRule","lowest objective in selected FE/run prefix; ties use lowest run index; observers sorted by latitude then longitude", ...
    "matchingRule","one-to-one assignment minimizing total great-circle distance to the best network");
fprintf("Observer-location figure saved to:\n  %s\n",pngFile);
end
function [x,y]=projectSites(latitude,longitude,hemisphere)
r=(latitude+90)/90;
if hemisphere=="north", r=(90-latitude)/90; end
x=r.*sind(longitude); y=r.*cosd(longitude);
end

function report=plotGaLocationConvergence(studyDirectory,demFile,independentRuns,options)
% PLOTGALOCATIONCONVERGENCE - One polar figure of sites matched to the best run.
% Saved data only. FE budgets are columns; each observer has south/north rows.
% One fixed reference: best run at the largest displayed FE budget.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,:) double = []
end
report=loadGaObserverLocations(studyDirectory,independentRuns,options.RequestedFE);
locations=report.locations; budgets=report.requestedFE; reference=report.reference;
independentRuns=report.independentRuns;
dem=@(lat,lon)zeros(size(lat));
if strlength(demFile)>0
    [dem,~]=digitalElevationModel.loadTriaxialLunarDem(demFile);
end
style=publicationPlotStyle(); style.axisFontSize=9;
figureSize=[max(7,3.4*numel(budgets)) 20];
if numel(budgets)==1, figureSize=[12 8.5]; end
fig=figure("Name","Observer locations relative to best run","Color","white", ...
    "Units","inches","Position",[0.5 0.5 figureSize],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
if numel(budgets)==1
    layout=tiledlayout(fig,2,3,"TileSpacing","compact","Padding","compact");
else
    layout=tiledlayout(fig,6,numel(budgets),"TileSpacing","compact","Padding","compact");
end
for observer=1:3
    for hemisphere=["south","north"]
        for budget=budgets
            tile=(2*(observer-1)+(hemisphere=="north"))*numel(budgets)+find(budgets==budget);
            if numel(budgets)==1, tile=3*(hemisphere=="north")+observer; end
            ax=nexttile(layout,tile); latitudeEdges=-90:10:0;
            if hemisphere=="north", latitudeEdges=0:10:90; end
            % Reuse the paper's geographic projection and terrain, without bins.
            plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
            selected=locations.RequestedFE==budget & locations.Observer==observer & locations.Hemisphere==hemisphere;
            [x,y]=projectSites(locations.LatitudeDeg(selected),locations.LongitudeDeg(selected),hemisphere);
            points=scatter3(ax,x,y,4*ones(size(x)),18,[0.05 0.35 0.65],"filled", ...
                "MarkerFaceAlpha",0.5,"MarkerEdgeColor","none");
            x=NaN; y=NaN;
            if (reference(observer,1)>=0)==(hemisphere=="north")
                [x,y]=projectSites(reference(observer,1),reference(observer,2),hemisphere);
            end
            star=scatter3(ax,x,y,5,120,[0.85 0.08 0.08],"p","filled", ...
                "MarkerEdgeColor","white","LineWidth",0.7);
            title(ax,sprintf("FE %d | Observer %d %s | %d/%d",budget,observer,hemisphere,nnz(selected),independentRuns), ...
                "FontSize",10);
        end
    end
end
key=legend(ax,[points star],["Independent-run location","Best-run location"], ...
    "Orientation","horizontal","FontSize",11);
key.Layout.Tile="south";
title(layout,sprintf("%d runs/FE | Reference: seed %d, FE %d, J = %.6f", ...
    independentRuns,report.referenceSeed,report.referenceRequestedFE,report.referenceObjective),"FontSize",12);
out=report.outputDirectory;
if ~isfolder(out), mkdir(out); end
pngFile=fullfile(out,"observer_locations.png"); pdfFile=fullfile(out,"observer_locations.pdf");
exportgraphics(fig,pngFile,"Resolution",220);
exportgraphics(fig,pdfFile,"ContentType","image","Resolution",220);
report.pngFile=pngFile; report.pdfFile=pdfFile;
fprintf("Observer-location figure saved to:\n  %s\n",pngFile);
end
function [x,y]=projectSites(latitude,longitude,hemisphere)
r=(latitude+90)/90;
if hemisphere=="north", r=(90-latitude)/90; end
x=r.*sind(longitude); y=r.*cosd(longitude);
end

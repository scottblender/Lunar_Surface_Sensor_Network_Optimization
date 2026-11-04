function report=plotGaLocationConvergence(studyDirectory,demFile,independentRuns,options)
% PLOTGALOCATIONCONVERGENCE - One polar figure of sites matched to the best run.
% Saved data only. FE budgets are columns; each observer has south/north rows.
% One fixed reference: best run at the largest displayed FE budget.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,:) double = []
    options.CompareBy (1,1) string {mustBeMember(options.CompareBy,["fe","runs"])} = "fe"
    options.RunCounts (1,:) double = []
end
report=loadGaObserverPlotData(studyDirectory,independentRuns,options.RequestedFE, ...
    options.CompareBy,options.RunCounts);
locations=report.locations; groups=report.groupValues; reference=report.reference;
dem=@(lat,lon)zeros(size(lat));
if strlength(demFile)>0
    [dem,~]=digitalElevationModel.loadTriaxialLunarDem(demFile);
end
style=publicationPlotStyle(); style.axisFontSize=9;
figureSize=[max(7,3.4*numel(groups)) 20];
if numel(groups)==1, figureSize=[12 8.5]; end
fig=figure("Name","Observer locations relative to best run","Color","white", ...
    "Units","inches","Position",[0.5 0.5 figureSize],"Visible","off");
cleanFigure=onCleanup(@()close(fig)); %#ok<NASGU>
if numel(groups)==1
    layout=tiledlayout(fig,2,3,"TileSpacing","compact","Padding","compact");
else
    layout=tiledlayout(fig,6,numel(groups),"TileSpacing","compact","Padding","compact");
end
for observer=1:3
    for hemisphere=["south","north"]
        for k=1:numel(groups)
            tile=(2*(observer-1)+(hemisphere=="north"))*numel(groups)+k;
            if numel(groups)==1, tile=3*(hemisphere=="north")+observer; end
            ax=nexttile(layout,tile); latitudeEdges=-90:10:0;
            if hemisphere=="north", latitudeEdges=0:10:90; end
            % Reuse the paper's geographic projection and terrain, without bins.
            plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
            selected=locations.(report.groupVariable)==groups(k) & locations.Observer==observer & locations.Hemisphere==hemisphere;
            [x,y]=projectSites(locations.LatitudeDeg(selected),locations.LongitudeDeg(selected),hemisphere);
            points=scatter3(ax,x,y,4*ones(size(x)),18,[0.05 0.35 0.65],"filled", ...
                "MarkerFaceAlpha",0.5,"MarkerEdgeColor","none");
            x=NaN; y=NaN;
            if (reference(observer,1)>=0)==(hemisphere=="north")
                [x,y]=projectSites(reference(observer,1),reference(observer,2),hemisphere);
            end
            star=scatter3(ax,x,y,5,120,[0.85 0.08 0.08],"p","filled", ...
                "MarkerEdgeColor","white","LineWidth",0.7);
            title(ax,sprintf("%s | Observer %d %s | %d/%d",report.panelLabels(k),observer,hemisphere,nnz(selected),report.groupRunCounts(k)), ...
                "FontSize",10);
        end
    end
end
key=legend(ax,[points star],["Independent-run location","Best-run location"], ...
    "Orientation","horizontal","FontSize",11);
key.Layout.Tile="south";
title(layout,report.sharedTitle,"FontSize",12);
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

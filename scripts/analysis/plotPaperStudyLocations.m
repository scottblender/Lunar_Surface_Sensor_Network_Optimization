function report = plotPaperStudyLocations(studyDirectory,demFile)
% PLOTPAPERSTUDYLOCATIONS - Compare final sensor placements across paper-study cases.
% Each case has south/north maps showing all final run locations and the
% selected network. Network sites are pooled without assigning observer labels.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
end

studyFile=fullfile(studyDirectory,"study.mat");
assert(isfile(studyFile),"paperLocations:Study","Study checkpoint not found: %s",studyFile);
saved=load(studyFile,"study");
study=saved.study;
assert(study.status=="complete" && ~isempty(study.cases), ...
    "paperLocations:Incomplete","Use a completed paper study.");
cases=vertcat(study.cases{:});
domains=vertcat(cases.domain);
sizes=[cases.networkSize].';
solvers=vertcat(cases.optimizer);
groups=unique(table(domains,sizes),"rows","stable");
optimizedSolvers=unique(solvers(solvers~="SEQUENTIAL"),"stable");
if isempty(optimizedSolvers), optimizedSolvers="SEQUENTIAL"; end
caseColumns=numel(optimizedSolvers);

if strlength(demFile)==0 && isfield(study.config.ekf,"demFile") && isfile(study.config.ekf.demFile)
    demFile=string(study.config.ekf.demFile);
end
dem=@(lat,lon)zeros(size(lat));
if strlength(demFile)>0
    [dem,~]=digitalElevationModel.loadTriaxialLunarDem(demFile);
end
style=publicationPlotStyle();
style.axisFontSize=8;
fig=figure("Color","white","Visible","off","Units","inches", ...
    "Position",[0.5 0.5 5.4*caseColumns 2.55*height(groups)+0.5]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,height(groups),2*caseColumns,"TileSpacing","compact","Padding","compact");

report=study.summary(:,["name","domain","optimizer","networkSize","objective"]);
report.Runs=zeros(numel(cases),1);
report.LocationCount=zeros(numel(cases),1);
for k=1:numel(cases)
    current=cases(k);
    folder=fullfile(studyDirectory,current.name);
    best=readtable(fullfile(folder,"selected_network.csv"));
    runLocations=zeros(0,2);
    domainLabel="Fixed CLPS";
    if solvers(k)~="SEQUENTIAL"
        [runLocations,report.Runs(k)]=readRunLocations(folder,current,study.config.baseSeed);
        domainLabel="CLPS neighborhoods";
        if domains(k)=="global", domainLabel="Global"; end
    end
    report.LocationCount(k)=size(runLocations,1);
    row=find(groups.domains==domains(k) & groups.sizes==sizes(k));
    column=find(optimizedSolvers==solvers(k));
    if solvers(k)=="SEQUENTIAL", column=1; end
    for hemisphere=["south","north"]
        north=hemisphere=="north";
        tile=(row-1)*2*caseColumns+2*column-1+north;
        ax=nexttile(layout,tile);
        latitudeEdges=-90:10:0;
        if north, latitudeEdges=0:10:90; end
        plotPolarSelectionMap(ax,zeros(9,12),latitudeEdges,0:30:360,dem,style,hemisphere);
        [x,y]=projectHemisphere(runLocations,north);
        points=scatter3(ax,x,y,4*ones(size(x)),10,[0.05 0.35 0.65],"filled", ...
            "MarkerFaceAlpha",0.30,"MarkerEdgeColor","none");
        [x,y]=projectHemisphere([best.LatitudeDeg best.LongitudeDeg],north);
        selected=scatter3(ax,x,y,5*ones(size(x)),38,[0.85 0.08 0.08],"p","filled", ...
            "MarkerEdgeColor","white","LineWidth",0.5);
        title(ax,sprintf("%s %d | %s | %s",domainLabel,sizes(k),solvers(k),hemisphere),"FontSize",9);
    end
end
key=legend(ax,[points selected],["Final location across runs","Selected network location"], ...
    "Orientation","horizontal");
key.Layout.Tile="south";
pngFile=fullfile(studyDirectory,"paper_case_polar_locations.png");
pdfFile=fullfile(studyDirectory,"paper_case_polar_locations.pdf");
exportgraphics(fig,pngFile,"Resolution",200);
exportgraphics(fig,pdfFile,"ContentType","image","Resolution",200);
fprintf("Case polar plots saved to %s and %s\n",pngFile,pdfFile);
end

function [locations,runCount] = readRunLocations(folder,current,baseSeed)
saved=load(fullfile(folder,"domain_manifest.mat"),"database");
candidates=saved.database.candidates;
runCount=numel(current.runObjectives);
networkSize=current.networkSize;
allIds=zeros(runCount*networkSize,1);
for index=1:runCount
    seed=baseSeed+index-1;
    file=fullfile(folder,sprintf("seed_%d",seed),"checkpoint.mat");
    assert(isfile(file),"paperLocations:Checkpoint","Run checkpoint not found: %s",file);
    saved=load(file,"record");
    ids=saved.record.ids(:);
    assert(saved.record.seed==seed && numel(ids)==networkSize && numel(unique(ids))==networkSize && ...
        all(ids>=1 & ids<=numel(candidates.latitudesRad) & ids==fix(ids)), ...
        "paperLocations:Run","Invalid final sensor IDs in %s.",file);
    allIds((index-1)*networkSize+(1:networkSize))=ids;
end
latitude=candidates.latitudesRad(allIds);
longitude=candidates.longitudesRad(allIds);
locations=[rad2deg(latitude(:)) mod(rad2deg(longitude(:)),360)];
end

function [x,y] = projectHemisphere(locations,north)
lat=locations(:,1);
inHemisphere=(lat>=0)==north;
radius=(90-abs(lat(inHemisphere)))/90;
lon=locations(inHemisphere,2);
x=radius.*sind(lon);
y=radius.*cosd(lon);
end

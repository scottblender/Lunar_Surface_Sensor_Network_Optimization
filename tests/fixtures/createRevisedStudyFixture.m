function [database,file] = createRevisedStudyFixture(folder,times)
% CREATEREVISEDSTUDYFIXTURE - Tiny physical two-body/chunked database with a flat test DEM.
plan=planPaperDatabase(struct("spacingKm",1800,"maximumCandidatesPerChunk",500));
lat=plan.latitudesRad; lon=plan.longitudesRad; n=numel(lat);
if nargin<2, times=[600;1200;1800]; end
times=times(:); nt=numel(times); no=2; radius=1737.4; mu=4902.800066;
DEM=griddedInterpolant({linspace(-pi/2,pi/2,25).',linspace(0,2*pi,49).'},zeros(25,49),'linear','nearest');
demFile=string(fullfile(folder,"flat_test_dem.mat")); save(demFile,"DEM");
database.config=productionDatabaseConfiguration(demFile,struct(),folder);
database.config.domainComparison=struct("domain","paper_shared","sites",plan.sites, ...
    "enforceSiteGroups",false,"maximumCandidatesPerChunk",500, ...
    "requestedDomains",["clps","global"]);
database.config.chunking.numberOfChunks=1;
file=string(fullfile(folder,"master.mat")); database.config.outputFile=file;
database.meta=struct("version","synthetic_physical_fixture","numberOfCandidates",n, ...
    "numberOfObjects",no,"numberOfOptimizationEpochs",nt,"demSource",demFile, ...
    "measurementJacobianStorage","on_demand");
database.meta.numberOfCandidatesBeforeFiltering=n;
database.candidates=struct("latitudesRad",lat,"longitudesRad",lon, ...
    "sensorElevationsKm",zeros(n,1),"originalIndices",(1:n).', ...
    "chunkIndex",ones(n,1),"chunkLocalIndex",(1:n).',"originalChunkLocalIndex",(1:n).');
database.study=struct("objectiveModes","information","networkSizes",[3 5]);
database.objective.infeasiblePenalty=1e12;
database.measurement.covariance=eye(2)*1e-8;
database.estimation=struct("stateScales",[1;1;1;1e-3;1e-3;1e-3], ...
    "objectWeights",ones(no,1),"accelerationNoiseIntensity",1e-15);
initialStates=[[2200;0;0;0;0;1.5],[0;3000;0;-1.2;0;0]];
database.prior=struct("referenceTime",0,"initialStates",initialStates, ...
    "initialCovariance",diag([1 1 1 1e-6 1e-6 1e-6]));
database.prior.initialCovariances=repmat(database.prior.initialCovariance,1,1,no);
database.tracking.times=times;
for object=1:no
    [states,phi,q]=optimization.precomputeTrackingData(0,times,initialStates(:,object), ...
        lat,lon,DEM,0,1e-15,mu,radius,0,2*pi/(27.321661*86400),true);
    database.tracking.referenceStateHistories(:,:,object)=states;
    database.tracking.stateTransitionHistories(:,:,:,object)=phi;
    database.tracking.processNoiseHistories(:,:,:,object)=q;
end
database.truth.optimizationStateHistories=database.tracking.referenceStateHistories;
database.truth.times=times;
earth=repmat([384400;0;0],1,nt); sun=repmat([0;149597870.7;0],1,nt);
[filteredAvailability,~]=optimization.buildFilteredVisibilityDatabase(times, ...
    database.truth.optimizationStateHistories,lat,lon,DEM,[0;pi;2*pi],zeros(n,3), ...
    earth,sun,0,0,6378.1366,695700,deg2rad(20),radius,0,2*pi/(27.321661*86400),deg2rad(10));
chunkFile=string(fullfile(folder,"physical_chunk.mat")); finalChunkComplete=true;
save(chunkFile,"filteredAvailability","finalChunkComplete","-v7.3");
chunks=struct("filePath",chunkFile,"numberOfOriginalCandidates",n,"numberOfRetainedCandidates",n);
database.terrain.maximumTerrainElevationRad=[];
database.visibility.candidateChunks=chunks;
database.visibility.filteredAvailability=[];
database.tracking.measurementJacobianChunks=chunks;
database.tracking.measurementJacobianHistories=[];
save(file,"database","-v7.3");
end

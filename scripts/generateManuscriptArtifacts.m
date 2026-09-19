function products = generateManuscriptArtifacts(userConfig)
% GENERATEMANUSCRIPTARTIFACTS One driver for all manuscript figures/tables.
%
% The generated products are synchronized with the current AAS manuscript.
% Numerical figures are kept in focused plot functions, while the process
% diagram is written as TikZ. Optional studies are never fabricated: Monte
% Carlo, restricted-domain, and operational products are generated only when
% the required underlying results are available.
%
% Examples:
%   products = generateManuscriptArtifacts();
%
%   cfg = struct();
%   cfg.clearOutputDirectory = true;
%   cfg.restrictedResultsDirectory = "...";
%   cfg.restrictedDatabaseFile = "...";
%   products = generateManuscriptArtifacts(cfg);

arguments
    userConfig (1,1) struct = struct()
end

close all;
scriptDirectory=fileparts(mfilename("fullpath"));
projectRoot=fileparts(scriptDirectory);
sourceDirectory=fullfile(projectRoot,"src");
addpath(scriptDirectory);
addpath(sourceDirectory);
rehash path;

defaults=struct();
defaults.outputDirectory=fullfile(projectRoot,"results","manuscript_artifacts");
defaults.clearOutputDirectory=false;
defaults.generateStudyDefinition=true;
defaults.generateDemFigures=true;
defaults.generateProductionResults=true;
defaults.generateScreeningBreakdown=true;
defaults.generateMonteCarlo=true;
defaults.generateOperationalValidation=true;
defaults.generateRobustnessValidation=true;
defaults.generateDemValidation=true;
defaults.validateArtifacts=true;
defaults.strictArtifactValidation=false;
defaults.restrictedResultsDirectory="";
defaults.restrictedDatabaseFile="";
defaults.restrictedStudyName="";
defaults.comparisonNetworkSize=10;
defaults.comparisonObjective="information";
defaults.operationalTableObjective="information";
defaults.operationalTableNetworkSize=10;
config=mergeStruct(defaults,userConfig);
config.outputDirectory=string(config.outputDirectory);
config.restrictedResultsDirectory=string(config.restrictedResultsDirectory);
config.restrictedDatabaseFile=string(config.restrictedDatabaseFile);
config.restrictedStudyName=string(config.restrictedStudyName);

if config.clearOutputDirectory && isfolder(config.outputDirectory)
    deleteGenerated(config.outputDirectory);
end
if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end

products=struct();
products.version="manuscript_artifact_driver_v2";
products.outputDirectory=config.outputDirectory;

%% Study-definition figures and tables

if config.generateStudyDefinition
    products.definitionFigures=runJob("study definition figures", ...
        @()generateStudyDefinitionFigures(config),true);
    products.clpsFigure=runJob("CLPS/design-domain figure", ...
        @()plotClpsDesignDomain(config),true);
end

if config.generateDemFigures
    products.demFigures=runJob("DEM figures", ...
        @()plotDemProducts(config),true);
end

products.optimizationWorkflow=runJob("optimization-workflow TikZ", ...
    @()writeOptimizationWorkflowTikz(config),true);

%% Load completed production campaign once

campaignConfig=config;
campaignConfig.outputDirectory=config.outputDirectory;
campaign=loadProductionCampaign(campaignConfig);
products.campaign=campaign;

%% Main production-result figures

if config.generateProductionResults
    products.convergence=runJob("convergence figures", ...
        @()plotProductionConvergence(campaign,config),true);

    products.networkLocations=runJob("sensor-selection frequency figures", ...
        @()plotProductionNetworkLocations(campaign,config),true);

    if config.generateScreeningBreakdown
        products.screeningBreakdown=runJob("measurement-screening figures", ...
            @()plotMeasurementScreeningBreakdown(campaign,config),true);
    end

    products.designTracking=runJob("design-RSO tracking figure", ...
        @()plotDesignRsoTrackingHeatmaps(campaign,config),true);
end

products.tables=runJob("manuscript tables", ...
    @()buildManuscriptTables(campaign,config),true);

%% Monte Carlo robustness figures

if config.generateMonteCarlo
    mcConfig=config;
    products.monteCarlo=runJob("Monte Carlo robustness figures", ...
        @()plotMonteCarloConferenceFigure(mcConfig),false);
end

%% Restricted-domain comparison

if strlength(config.restrictedResultsDirectory)>0 && ...
        strlength(config.restrictedDatabaseFile)>0
    products.domainComparison=runJob("restricted-domain comparison", ...
        @()generateDomainComparisonProducts(campaign,config),false);
else
    fprintf(["SKIP restricted-domain comparison: set " ...
        "restrictedResultsDirectory and restrictedDatabaseFile.\n"]);
end

%% Operational/legacy spacecraft evaluation

if config.generateOperationalValidation
    operational=runJob("operational-RSO validation", ...
        @()evaluateOperationalRsoNetworks(config),false);
    products.operational=operational;

    if isstruct(operational) && isfield(operational,"spacecraftNames")
        products.operationalFigure=runJob("operational-RSO tracking figure", ...
            @()plotOperationalRsoTrackingHeatmaps(operational,config),false);
        products.operationalTable=runJob("operational-RSO manuscript table", ...
            @()buildOperationalManuscriptTable(operational,config),false);
    end
end

%% Validation-only products supporting manuscript discussion

if config.generateRobustnessValidation
    products.discreteNeighbor=runJob("discrete-neighbor robustness", ...
        @()evaluateDiscreteNeighborRobustness(campaign,config),false);
end

if config.generateDemValidation
    syntheticFile=fullfile(projectRoot,"data","Synthetic_Lunar_DEM.mat");
    fullFile=fullfile(projectRoot,"data","Full_Resolution_DEM.mat");
    if isfile(syntheticFile) && isfile(fullFile)
        products.demValidation=runJob("DEM resolution validation", ...
            @()evaluateDemResolutionValidation(campaign,config),false);
    else
        fprintf("SKIP DEM validation: both DEM files are required.\n");
    end
end

%% Artifact-manifest check against the manuscript

if config.validateArtifacts
    products.artifactManifest=validateManuscriptArtifacts( ...
        config.outputDirectory,config);
end

fprintf("\n============================================================\n");
fprintf("Manuscript artifact generation complete\n");
fprintf("============================================================\n");
fprintf("Output directory:\n  %s\n",config.outputDirectory);
fprintf("Artifact manifest:\n  %s\n", ...
    fullfile(config.outputDirectory,"manuscript_artifact_manifest.csv"));
end

function result=runJob(name,job,required)
fprintf("\n[%s]\n",name);
try
    result=job();
catch ME
    if required
        rethrow(ME);
    end
    warning("generateManuscriptArtifacts:OptionalJobFailed", ...
        "%s failed: %s",name,ME.message);
    result=struct("available",false,"message",string(ME.message));
end
end

function deleteGenerated(directoryName)
extensions=["*.eps","*.png","*.pdf","*.csv","*.fig","*.tex"];
for k=1:numel(extensions)
    files=dir(fullfile(directoryName,"**",extensions(k)));
    for j=1:numel(files)
        delete(fullfile(files(j).folder,files(j).name));
    end
end
end

function out=mergeStruct(defaults,override)
out=defaults;
fields=fieldnames(override);
for k=1:numel(fields)
    out.(fields{k})=override.(fields{k});
end
end

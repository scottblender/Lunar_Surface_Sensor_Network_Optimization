function products = generateManuscriptArtifacts(userConfig)
% GENERATEMANUSCRIPTARTIFACTS One driver for all manuscript figures/tables.
%
% The driver separates study-definition schematics, production-result plots,
% validation plots, and table generation. Missing optional studies (Monte
% Carlo, full-DEM validation, restricted-domain comparison) are reported
% explicitly rather than silently fabricating outputs.
%
% Example:
%   cfg = struct();
%   cfg.clearOutputDirectory = true;
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
defaults.generateMonteCarlo=true;
defaults.generateOperationalValidation=true;
defaults.generateRobustnessValidation=true;
defaults.generateDemValidation=true;
config=mergeStruct(defaults,userConfig);
config.outputDirectory=string(config.outputDirectory);

if config.clearOutputDirectory && isfolder(config.outputDirectory)
    deleteGenerated(config.outputDirectory);
end
if ~isfolder(config.outputDirectory), mkdir(config.outputDirectory); end

products=struct();
products.version="manuscript_artifact_driver_v1";
products.outputDirectory=config.outputDirectory;
products.status=table(strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Product','Status','Message'});

if config.generateStudyDefinition
    products.definitionFigures=runJob("study definition figures", ...
        @()generateStudyDefinitionFigures(config),true);
    products.clpsFigure=runJob("CLPS/design-domain figure", ...
        @()plotClpsDesignDomain(config),true);
end

if config.generateDemFigures
    products.demFigures=runJob("DEM figures",@()plotDemProducts(config),true);
end

products.optimizationWorkflow=runJob("optimization-workflow TikZ", ...
    @()writeOptimizationWorkflowTikz(config),true);

campaignConfig=config;
campaignConfig.outputDirectory=config.outputDirectory;
campaign=loadProductionCampaign(campaignConfig);
products.campaign=campaign;

if config.generateProductionResults
    products.convergence=runJob("convergence figures", ...
        @()plotProductionConvergence(campaign,config),true);
    products.networkLocations=runJob("network-location figures", ...
        @()plotProductionNetworkLocations(campaign,config),true);
    products.designTracking=runJob("design-RSO tracking figure", ...
        @()plotDesignRsoTrackingHeatmaps(campaign,config),true);
end

products.tables=runJob("manuscript tables", ...
    @()buildManuscriptTables(campaign,config),true);

% Optional Monte Carlo products.
if config.generateMonteCarlo
    mcFile=fullfile(projectRoot,"results","monte_carlo","production_mc_results.mat");
    if isfile(mcFile)
        mcConfig=config; mcConfig.monteCarloResultsFile=mcFile;
        products.monteCarlo=runJob("Monte Carlo robustness figures", ...
            @()plotMonteCarloConferenceFigure(mcConfig),false);
    else
        fprintf("SKIP Monte Carlo figures: %s not found.\n",mcFile);
    end
end

% Operational validation and combined heatmap.
if config.generateOperationalValidation
    operational=runJob("operational-RSO validation", ...
        @()evaluateOperationalRsoNetworks(config),false);
    products.operational=operational;
    if isstruct(operational) && isfield(operational,"spacecraftNames")
        products.operationalFigure=runJob("operational-RSO tracking figure", ...
            @()plotOperationalRsoTrackingHeatmaps(operational,config),false);
    end
end

% Validation-only outputs used in the manuscript discussion/tables.
if config.generateRobustnessValidation
    products.discreteNeighbor=runJob("discrete-neighbor robustness", ...
        @()evaluateDiscreteNeighborRobustness(campaign,config),false);
end
if isfield(config,"restrictedResultsDirectory") && ...
        isfield(config,"restrictedDatabaseFile") && ...
        strlength(string(config.restrictedResultsDirectory))>0 && ...
        strlength(string(config.restrictedDatabaseFile))>0
    products.domainComparison=runJob("restricted-domain comparison", ...
        @()generateDomainComparisonProducts(campaign,config),false);
else
    fprintf("SKIP restricted-domain comparison: configure restrictedResultsDirectory and restrictedDatabaseFile.\n");
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

fprintf("\n============================================================\n");
fprintf("Manuscript artifact generation complete\n");
fprintf("============================================================\n");
fprintf("Output directory:\n  %s\n",config.outputDirectory);
fprintf("Use this driver instead of the retired publication/result plot runners.\n");
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
extensions=["*.eps","*.png","*.pdf","*.csv","*.fig"];
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
for k=1:numel(fields), out.(fields{k})=override.(fields{k}); end
end

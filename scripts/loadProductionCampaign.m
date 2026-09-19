function campaign = loadProductionCampaign(userConfig)
% LOADPRODUCTIONCAMPAIGN Load the frozen database and completed GA campaign.
%
% This function contains the result-discovery logic shared by all manuscript
% figure/table generators. It does not create figures or modify study data.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
resultsDirectory = fullfile(projectRoot,"results");

defaults = struct();
defaults.resultsDirectory = resultsDirectory;
defaults.databaseFile = fullfile(resultsDirectory,"optimization_database.mat");
defaults.outputDirectory = fullfile(resultsDirectory,"manuscript_artifacts");
defaults.networkSizes = [3 5 7 10];
defaults.objectiveModes = ["information","coverage"];
defaults.numberOfRuns = 20;
defaults.functionEvaluationBudget = 12000;
defaults.populationSize = 60;
defaults.baseSeed = 1000;
defaults.studyName = "lunar_surface_production_optimization";
defaults.maximumCampaignSpanHours = 168;
config = mergeStruct(defaults,userConfig);

config.resultsDirectory = string(config.resultsDirectory);
config.databaseFile = string(config.databaseFile);
config.outputDirectory = string(config.outputDirectory);
config.networkSizes = double(config.networkSizes(:).');
config.objectiveModes = lower(string(config.objectiveModes(:).'));
config.studyName = string(config.studyName);

assert(isfile(config.databaseFile), ...
    "Production optimization database was not found: %s",config.databaseFile);
databaseData = load(config.databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "optimization_database.mat does not contain database.");
database = databaseData.database;

runRoot = fullfile(config.resultsDirectory,"optimization_runs");
assert(isfolder(runRoot), ...
    "Optimization result directory was not found: %s",runRoot);

allSummaryFiles = dir(fullfile(runRoot,"**","study_summary.mat"));
assert(~isempty(allSummaryFiles), ...
    "No study_summary.mat files were found under %s.",runRoot);
[~,order] = sort([allSummaryFiles.datenum],"descend");
allSummaryFiles = allSummaryFiles(order);

numberOfNetworkSizes = numel(config.networkSizes);
numberOfObjectives = numel(config.objectiveModes);
summaryFiles = strings(numberOfNetworkSizes,numberOfObjectives);
campaignTimes = NaT(numberOfNetworkSizes,numberOfObjectives);
studies = cell(numberOfNetworkSizes,numberOfObjectives);

for networkIndex = 1:numberOfNetworkSizes
    networkSize = config.networkSizes(networkIndex);
    for objectiveIndex = 1:numberOfObjectives
        objectiveMode = config.objectiveModes(objectiveIndex);
        found = false;

        for fileIndex = 1:numel(allSummaryFiles)
            candidateFile = string(fullfile( ...
                allSummaryFiles(fileIndex).folder,allSummaryFiles(fileIndex).name));
            loaded = load(candidateFile,"studyState");
            if ~isfield(loaded,"studyState")
                continue
            end
            studyState = loaded.studyState;
            if ~matchesStudy(studyState,networkSize,objectiveMode,config)
                continue
            end

            studyDirectory = string(fileparts(candidateFile));
            complete = true;
            for runIndex = 1:config.numberOfRuns
                if ~isfile(fullfile(studyDirectory,sprintf("run_%03d.mat",runIndex)))
                    complete = false;
                    break
                end
            end
            if ~complete
                continue
            end

            summaryFiles(networkIndex,objectiveIndex) = candidateFile;
            studies{networkIndex,objectiveIndex} = studyState;
            [~,folderName] = fileparts(studyDirectory);
            campaignTimes(networkIndex,objectiveIndex) = extractTimestamp(folderName);
            found = true;
            break
        end

        assert(found, ...
            ["Could not find a complete production study for N_s=%d, %s. " ...
             "Expected %d runs and %d FE/run."], ...
            networkSize,objectiveMode,config.numberOfRuns, ...
            config.functionEvaluationBudget);
    end
end

assert(numel(unique(summaryFiles)) == numel(summaryFiles), ...
    "The same study summary was selected for more than one case.");

if all(~isnat(campaignTimes),"all")
    spanHours = hours(max(campaignTimes(:))-min(campaignTimes(:)));
    assert(spanHours <= config.maximumCampaignSpanHours, ...
        "Selected production studies span %.2f hr; expected one campaign.",spanHours);
else
    spanHours = NaN;
end

campaign = struct();
campaign.version = "manuscript_campaign_v1";
campaign.projectRoot = string(projectRoot);
campaign.configuration = config;
campaign.databaseFile = config.databaseFile;
campaign.outputDirectory = config.outputDirectory;
campaign.database = database;
campaign.studySummaryFiles = summaryFiles;
campaign.studies = studies;
campaign.campaignTimes = campaignTimes;
campaign.campaignSpanHours = spanHours;

end

function tf = matchesStudy(studyState,networkSize,objectiveMode,config)
tf = isstruct(studyState) && isscalar(studyState) && ...
    isfield(studyState,"config") && isfield(studyState,"numberOfRuns");
if ~tf, return, end
cfg = studyState.config;
required = {'networkSize','objectiveMode','functionEvaluationBudget', ...
    'populationSize','baseSeed','studyName'};
for k = 1:numel(required)
    if ~isfield(cfg,required{k})
        tf = false;
        return
    end
end
tf = studyState.numberOfRuns == config.numberOfRuns && ...
    cfg.networkSize == networkSize && ...
    lower(string(cfg.objectiveMode)) == objectiveMode && ...
    cfg.functionEvaluationBudget == config.functionEvaluationBudget && ...
    cfg.populationSize == config.populationSize && ...
    cfg.baseSeed == config.baseSeed && ...
    string(cfg.studyName) == config.studyName;
end

function timestamp = extractTimestamp(folderName)
tokens = regexp(string(folderName),"_(\d{8}_\d{6})$","tokens","once");
if isempty(tokens)
    timestamp = NaT;
else
    timestamp = datetime(string(tokens{1}),"InputFormat","yyyyMMdd_HHmmss");
end
end

function out = mergeStruct(defaults,override)
out = defaults;
fields = fieldnames(override);
for k = 1:numel(fields)
    out.(fields{k}) = override.(fields{k});
end
end

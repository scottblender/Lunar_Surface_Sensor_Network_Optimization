function restrictedCampaign = loadRestrictedCampaign(fullCampaign,userConfig)
% LOADRESTRICTEDCAMPAIGN Load the complete matched restricted-domain campaign.
%
% The restricted study is identified by date rather than by one individual
% network-size/objective folder. This guarantees that all eight restricted
% cases (N_s = 3,5,7,10 x information/coverage) are loaded together.
%
% Preferred configuration:
%   restrictedCampaignDate = "20260915"
%
% Optional fallback:
%   restrictedCampaignAnchor = "ga_coverage_n3_20260915_121933"
% The anchor is used only to infer the YYYYMMDD date and reference database.

arguments
    fullCampaign (1,1) struct
    userConfig (1,1) struct = struct()
end

resultsDirectory = string(fullCampaign.configuration.resultsDirectory);
if isfield(userConfig,"restrictedResultsDirectory") && ...
        strlength(string(userConfig.restrictedResultsDirectory)) > 0
    resultsDirectory = string(userConfig.restrictedResultsDirectory);
end

restrictedDate = "";
if isfield(userConfig,"restrictedCampaignDate")
    restrictedDate = string(userConfig.restrictedCampaignDate);
end

anchor = "";
if isfield(userConfig,"restrictedCampaignAnchor")
    anchor = string(userConfig.restrictedCampaignAnchor);
end

referenceSummary = "";
referenceStudy = [];

if strlength(anchor) > 0
    [referenceSummary,referenceStudy] = resolveAnchor( ...
        anchor,string(fullCampaign.projectRoot),resultsDirectory);
    anchorDate = extractDate(referenceSummary);
    if strlength(restrictedDate) == 0
        restrictedDate = anchorDate;
    else
        assert(restrictedDate == anchorDate, ...
            "restrictedCampaignDate does not match restrictedCampaignAnchor.");
    end
elseif strlength(restrictedDate) > 0
    [referenceSummary,referenceStudy] = resolveDateReference( ...
        restrictedDate,resultsDirectory);
end

assert(strlength(restrictedDate) > 0, ...
    "Set restrictedCampaignDate or restrictedCampaignAnchor.");
assert(~isempty(referenceStudy), ...
    "Could not resolve a restricted campaign reference study.");

restrictedConfig = fullCampaign.configuration;
restrictedConfig.resultsDirectory = resultsDirectory;
restrictedConfig.outputDirectory = string(fullCampaign.outputDirectory);
restrictedConfig.campaignDate = "";
restrictedConfig.campaignDates = restrictedDate;
restrictedConfig.requireDatabaseMatch = false;

if isfield(referenceStudy.config,"studyName")
    restrictedConfig.studyName = string(referenceStudy.config.studyName);
end

if isfield(userConfig,"restrictedStudyName") && ...
        strlength(string(userConfig.restrictedStudyName)) > 0
    restrictedConfig.studyName = string(userConfig.restrictedStudyName);
end

if isfield(userConfig,"restrictedDatabaseFile") && ...
        strlength(string(userConfig.restrictedDatabaseFile)) > 0
    restrictedConfig.databaseFile = string(userConfig.restrictedDatabaseFile);
else
    assert(isfield(referenceStudy.config,"databaseFile"), ...
        "Restricted reference study does not record config.databaseFile.");
    restrictedConfig.databaseFile = string(referenceStudy.config.databaseFile);
end

if ~isfile(restrictedConfig.databaseFile)
    [~,databaseName,databaseExtension] = fileparts(restrictedConfig.databaseFile);
    relocatedDatabase = fullfile( ...
        restrictedConfig.resultsDirectory,databaseName + databaseExtension);
    assert(isfile(relocatedDatabase), ...
        ["Restricted database was not found:\n%s\nAlso tried:\n%s"], ...
        restrictedConfig.databaseFile,relocatedDatabase);
    restrictedConfig.databaseFile = string(relocatedDatabase);
end

restrictedCampaign = loadProductionCampaign(restrictedConfig);

fprintf("\nRestricted-domain campaign loaded\n");
fprintf("  Date:      %s\n",restrictedDate);
fprintf("  Reference: %s\n",referenceSummary);
fprintf("  Database:  %s\n",restrictedConfig.databaseFile);
fprintf("  Cases:\n");
for objectiveIndex = 1:numel(restrictedCampaign.configuration.objectiveModes)
    for networkIndex = 1:numel(restrictedCampaign.configuration.networkSizes)
        fprintf("    %s, N_s=%d -> %s\n", ...
            restrictedCampaign.configuration.objectiveModes(objectiveIndex), ...
            restrictedCampaign.configuration.networkSizes(networkIndex), ...
            restrictedCampaign.studySummaryFiles(networkIndex,objectiveIndex));
    end
end
end

function [summaryFile,studyState] = resolveDateReference(campaignDate,resultsDirectory)
runRoot = fullfile(resultsDirectory,"optimization_runs");
files = dir(fullfile(runRoot,"**","study_summary.mat"));

summaryFile = "";
studyState = [];

for fileIndex = 1:numel(files)
    [~,folderName] = fileparts(files(fileIndex).folder);
    tokens = regexp(string(folderName),"_(\d{8})_\d{6}$","tokens","once");
    if isempty(tokens) || string(tokens{1}) ~= campaignDate
        continue
    end

    candidate = string(fullfile(files(fileIndex).folder,files(fileIndex).name));
    data = load(candidate,"studyState");
    if isfield(data,"studyState") && isfield(data.studyState,"config")
        summaryFile = candidate;
        studyState = data.studyState;
        return
    end
end

assert(strlength(summaryFile) > 0, ...
    "No optimization study was found for restricted campaign date %s.", ...
    campaignDate);
end

function [summaryFile,studyState] = resolveAnchor(anchor,projectRoot,resultsDirectory)
anchor = string(anchor);
candidates = strings(0,1);

if isfile(anchor)
    candidates(end+1,1) = anchor;
elseif isfolder(anchor)
    candidates(end+1,1) = fullfile(anchor,"study_summary.mat");
else
    candidates(end+1,1) = fullfile( ...
        resultsDirectory,"optimization_runs",anchor,"study_summary.mat");
    candidates(end+1,1) = fullfile(projectRoot,anchor,"study_summary.mat");
end

summaryFile = "";
for k = 1:numel(candidates)
    if isfile(candidates(k))
        summaryFile = candidates(k);
        break
    end
end

assert(strlength(summaryFile) > 0, ...
    "Restricted campaign anchor could not be resolved: %s",anchor);

data = load(summaryFile,"studyState");
assert(isfield(data,"studyState") && isfield(data.studyState,"config"), ...
    "Restricted campaign anchor does not contain a valid studyState.");
studyState = data.studyState;
end

function campaignDate = extractDate(summaryFile)
[~,folderName] = fileparts(fileparts(summaryFile));
tokens = regexp(string(folderName),"_(\d{8})_\d{6}$","tokens","once");
assert(~isempty(tokens), ...
    "Could not extract YYYYMMDD date from %s.",summaryFile);
campaignDate = string(tokens{1});
end

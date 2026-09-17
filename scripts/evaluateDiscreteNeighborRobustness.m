function result = evaluateDiscreteNeighborRobustness(productionInfo,userConfig)
% EVALUATEDISCRETENEIGHBORROBUSTNESS Test local optimality on the candidate grid.
%
% This study is intentionally separate from the continuous placement-error
% Monte Carlo study. It asks whether the best discrete network selected by
% the optimizer is locally superior to geographically neighboring candidate
% sites already contained in the frozen optimization database.
%
% For every best production network and objective:
%   1) Exhaustively replace one selected sensor at a time by each of its K
%      nearest eligible candidate sites and re-evaluate the same objective.
%   2) Draw joint discrete-neighbor perturbations in which every selected
%      sensor independently chooses either its nominal site or one of those
%      K neighbors. Duplicate-site networks are rejected and regenerated.
%
% Positive improvement means a lower minimization objective was found:
%
%   improvement = J_nominal - J_perturbed.
%
% Therefore, no positive one-site improvement means the nominal network is
% locally optimal with respect to all tested single-site substitutions.
%
% No paper figure is generated. A compact summary and detailed diagnostics
% are written under production_figures/tables/diagnostics, while the full
% sampled study is cached as a MAT file for later analysis.

arguments
    productionInfo (1,1) struct
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
addpath(sourceDirectory);
addpath(scriptDirectory);
rehash path;

assert(isfield(productionInfo,"configuration"), ...
    "productionInfo must come from plotProductionOptimizationResults.");
assert(isfield(productionInfo,"studySummaryFiles"), ...
    "productionInfo.studySummaryFiles is required.");
assert(isfield(productionInfo,"databaseFile"), ...
    "productionInfo.databaseFile is required.");
assert(isfield(productionInfo,"outputDirectory"), ...
    "productionInfo.outputDirectory is required.");

productionConfig = productionInfo.configuration;
defaultConfig = struct();
defaultConfig.nearestNeighborCount = 8;
defaultConfig.jointSamples = 1000;
defaultConfig.baseSeed = 9100;
defaultConfig.maximumRegenerationAttempts = 1000;
defaultConfig.improvementTolerance = 1e-10;
defaultConfig.reuseCache = true;
config = mergeStruct(defaultConfig,userConfig);

validateattributes(config.nearestNeighborCount,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.jointSamples,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.baseSeed,{'numeric'}, ...
    {'scalar','integer','nonnegative'});
validateattributes(config.maximumRegenerationAttempts,{'numeric'}, ...
    {'scalar','integer','positive'});
validateattributes(config.improvementTolerance,{'numeric'}, ...
    {'scalar','real','nonnegative'});
assert(islogical(config.reuseCache) && isscalar(config.reuseCache), ...
    "reuseCache must be a scalar logical.");

networkSizes = double(productionConfig.networkSizes(:).');
objectiveModes = lower(string(productionConfig.objectiveModes(:).'));
summaryFiles = string(productionInfo.studySummaryFiles);
databaseFile = string(productionInfo.databaseFile);
outputDirectory = string(productionInfo.outputDirectory);

assert(isfile(databaseFile),"Optimization database not found: %s",databaseFile);
assert(all(isfile(summaryFiles),"all"),"One or more production study summaries are missing.");

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization database file does not contain database.");
database = databaseData.database;

candidateLatitudesRad = double(database.candidates.latitudesRad(:));
candidateLongitudesRad = double(database.candidates.longitudesRad(:));
numberOfCandidates = database.meta.numberOfCandidates;
assert(numel(candidateLatitudesRad) == numberOfCandidates && ...
    numel(candidateLongitudesRad) == numberOfCandidates, ...
    "Candidate coordinate arrays do not match database.meta.numberOfCandidates.");
assert(config.nearestNeighborCount <= numberOfCandidates-max(networkSizes), ...
    "nearestNeighborCount is too large for the available candidate set.");

moonRadiusKm = double(database.config.moon.radiusKm);
diagnosticsDirectory = fullfile(outputDirectory,"tables","diagnostics");
cacheDirectory = fullfile(outputDirectory,"discrete_neighbor_cache");
if ~isfolder(diagnosticsDirectory), mkdir(diagnosticsDirectory); end
if ~isfolder(cacheDirectory), mkdir(cacheDirectory); end

summaryFile = fullfile(diagnosticsDirectory,"discrete_neighbor_summary.csv");
singleDetailFile = fullfile(diagnosticsDirectory,"discrete_neighbor_single_substitutions.csv");
jointDetailFile = fullfile(diagnosticsDirectory,"discrete_neighbor_joint_samples.csv");
cacheFile = fullfile(cacheDirectory,"discrete_neighbor_robustness.mat");

signature = buildSignature(databaseFile,summaryFiles,networkSizes,objectiveModes,config);
if config.reuseCache && isfile(cacheFile)
    cachedData = load(cacheFile,"studyCache");
    if isfield(cachedData,"studyCache") && ...
            isfield(cachedData.studyCache,"signature") && ...
            isequaln(cachedData.studyCache.signature,signature)
        result = cachedData.studyCache.result;
        writeOutputs(result,summaryFile,singleDetailFile,jointDetailFile);
        fprintf("\nUsing cached discrete-neighbor robustness study: %s\n",cacheFile);
        printCompactSummary(result.summaryTable);
        return
    end
end

numberOfNetworkSizes = numel(networkSizes);
numberOfObjectives = numel(objectiveModes);
numberOfCases = numberOfNetworkSizes*numberOfObjectives;

summaryRows = cell(numberOfCases,1);
singleTables = cell(numberOfCases,1);
jointTables = cell(numberOfCases,1);
caseResults = cell(numberOfNetworkSizes,numberOfObjectives);
caseIndex = 0;

fprintf("\n============================================================\n");
fprintf("Discrete candidate-neighbor robustness / local optimality\n");
fprintf("============================================================\n");
fprintf("Nearest eligible neighbors per sensor: %d\n",config.nearestNeighborCount);
fprintf("Joint discrete-neighbor samples/case: %d\n",config.jointSamples);

for objectiveIndex = 1:numberOfObjectives
    objectiveMode = objectiveModes(objectiveIndex);
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        networkSize = networkSizes(networkIndex);

        loadedData = load(summaryFiles(networkIndex,objectiveIndex),"studyState");
        assert(isfield(loadedData,"studyState"), ...
            "Study summary does not contain studyState: %s", ...
            summaryFiles(networkIndex,objectiveIndex));
        studyState = loadedData.studyState;
        nominalIndices = sort(double(studyState.overallBestSensorIndices(:).'));
        assert(numel(nominalIndices) == networkSize, ...
            "Saved best network size does not match the production configuration.");

        [nominalObjective,~] = optimization.networkObjective( ...
            nominalIndices,database,objectiveMode);

        neighborIndices = cell(networkSize,1);
        neighborDistancesKm = cell(networkSize,1);
        for sensorPosition = 1:networkSize
            [neighborIndices{sensorPosition},neighborDistancesKm{sensorPosition}] = ...
                nearestEligibleCandidates( ...
                    nominalIndices(sensorPosition),nominalIndices, ...
                    candidateLatitudesRad,candidateLongitudesRad, ...
                    moonRadiusKm,config.nearestNeighborCount);
        end

        objectiveCache = containers.Map('KeyType','char','ValueType','double');
        objectiveCache(networkKey(nominalIndices)) = nominalObjective;

        [singleTable,singleResult,objectiveCache] = evaluateSingleSubstitutions( ...
            nominalIndices,neighborIndices,neighborDistancesKm, ...
            nominalObjective,database,objectiveMode,config.improvementTolerance, ...
            objectiveCache);

        caseSeed = config.baseSeed + 100*objectiveIndex + networkIndex;
        [jointTable,jointResult,objectiveCache] = evaluateJointSamples( ...
            nominalIndices,neighborIndices,nominalObjective,database, ...
            objectiveMode,config.jointSamples,caseSeed, ...
            config.maximumRegenerationAttempts,config.improvementTolerance, ...
            objectiveCache);

        summaryRows{caseIndex} = table( ...
            objectiveMode,networkSize,nominalObjective, ...
            singleResult.numberTested,singleResult.numberBetter, ...
            singleResult.fractionBetter,singleResult.bestObjective, ...
            singleResult.maximumImprovement, ...
            singleResult.bestSensorPosition, ...
            singleResult.bestOriginalIndex, ...
            singleResult.bestReplacementIndex, ...
            singleResult.bestReplacementDistanceKm, ...
            jointResult.numberSamples,jointResult.numberUniqueNetworks, ...
            jointResult.numberBetter,jointResult.fractionBetter, ...
            jointResult.bestObjective,jointResult.maximumImprovement, ...
            string(mat2str(jointResult.bestSensorIndices)), ...
            'VariableNames',{ ...
            'Objective','NetworkSize','NominalObjective', ...
            'SingleNeighborTests','SingleBetterCount','SingleBetterFraction', ...
            'BestSingleObjective','MaximumSingleImprovement', ...
            'BestSingleSensorPosition','BestSingleOriginalIndex', ...
            'BestSingleReplacementIndex','BestSingleReplacementDistanceKm', ...
            'JointSamples','UniqueJointNetworks','JointBetterCount', ...
            'JointBetterFraction','BestJointObjective','MaximumJointImprovement', ...
            'BestJointSensorIndices'});

        singleTable = addvars(singleTable, ...
            repmat(objectiveMode,height(singleTable),1), ...
            repmat(networkSize,height(singleTable),1), ...
            'Before',1,'NewVariableNames',{'Objective','NetworkSize'});
        jointTable = addvars(jointTable, ...
            repmat(objectiveMode,height(jointTable),1), ...
            repmat(networkSize,height(jointTable),1), ...
            'Before',1,'NewVariableNames',{'Objective','NetworkSize'});
        singleTables{caseIndex} = singleTable;
        jointTables{caseIndex} = jointTable;

        caseResult = struct();
        caseResult.objectiveMode = objectiveMode;
        caseResult.networkSize = networkSize;
        caseResult.nominalSensorIndices = nominalIndices;
        caseResult.nominalObjective = nominalObjective;
        caseResult.neighborIndices = neighborIndices;
        caseResult.neighborDistancesKm = neighborDistancesKm;
        caseResult.single = singleResult;
        caseResult.joint = jointResult;
        caseResult.caseSeed = caseSeed;
        caseResult.uniqueObjectiveEvaluations = objectiveCache.Count;
        caseResults{networkIndex,objectiveIndex} = caseResult;

        fprintf("  %-11s N_s=%2d: single better %3d/%3d, joint better %4d/%4d, max dJ = %.6g\n", ...
            objectiveMode,networkSize,singleResult.numberBetter, ...
            singleResult.numberTested,jointResult.numberBetter, ...
            jointResult.numberSamples, ...
            max(singleResult.maximumImprovement,jointResult.maximumImprovement));
    end
end

summaryTable = vertcat(summaryRows{:});
singleDetailTable = vertcat(singleTables{:});
jointDetailTable = vertcat(jointTables{:});

result = struct();
result.version = "discrete_neighbor_robustness_v1";
result.created = string(datetime("now"));
result.configuration = config;
result.databaseFile = databaseFile;
result.studySummaryFiles = summaryFiles;
result.summaryTable = summaryTable;
result.singleDetailTable = singleDetailTable;
result.jointDetailTable = jointDetailTable;
result.caseResults = caseResults;
result.summaryFile = string(summaryFile);
result.singleDetailFile = string(singleDetailFile);
result.jointDetailFile = string(jointDetailFile);
result.cacheFile = string(cacheFile);

writeOutputs(result,summaryFile,singleDetailFile,jointDetailFile);
studyCache = struct("signature",signature,"result",result); %#ok<NASGU>
save(cacheFile,"studyCache","-v7.3");
printCompactSummary(summaryTable);
end

%% ========================================================================
function [tableOut,result,objectiveCache] = evaluateSingleSubstitutions( ...
    nominalIndices,neighborIndices,neighborDistancesKm,nominalObjective, ...
    database,objectiveMode,tolerance,objectiveCache)

networkSize = numel(nominalIndices);
numberRows = sum(cellfun(@numel,neighborIndices));
sensorPositionColumn = zeros(numberRows,1);
originalIndexColumn = zeros(numberRows,1);
replacementIndexColumn = zeros(numberRows,1);
replacementDistanceKm = zeros(numberRows,1);
objectiveColumn = zeros(numberRows,1);
improvementColumn = zeros(numberRows,1);

rowIndex = 0;
for sensorPosition = 1:networkSize
    for neighborIndex = 1:numel(neighborIndices{sensorPosition})
        rowIndex = rowIndex + 1;
        replacementIndex = neighborIndices{sensorPosition}(neighborIndex);
        perturbedIndices = nominalIndices;
        perturbedIndices(sensorPosition) = replacementIndex;
        perturbedIndices = sort(perturbedIndices);
        [objectiveValue,objectiveCache] = cachedObjective( ...
            perturbedIndices,database,objectiveMode,objectiveCache);

        sensorPositionColumn(rowIndex) = sensorPosition;
        originalIndexColumn(rowIndex) = nominalIndices(sensorPosition);
        replacementIndexColumn(rowIndex) = replacementIndex;
        replacementDistanceKm(rowIndex) = ...
            neighborDistancesKm{sensorPosition}(neighborIndex);
        objectiveColumn(rowIndex) = objectiveValue;
        improvementColumn(rowIndex) = nominalObjective-objectiveValue;
    end
end

isBetter = objectiveColumn < nominalObjective-tolerance;
[bestObjective,bestRow] = min(objectiveColumn);
result = struct();
result.numberTested = numberRows;
result.numberBetter = nnz(isBetter);
result.fractionBetter = result.numberBetter/numberRows;
result.bestObjective = bestObjective;
result.maximumImprovement = nominalObjective-bestObjective;
result.bestSensorPosition = sensorPositionColumn(bestRow);
result.bestOriginalIndex = originalIndexColumn(bestRow);
result.bestReplacementIndex = replacementIndexColumn(bestRow);
result.bestReplacementDistanceKm = replacementDistanceKm(bestRow);
result.locallyOptimal = result.numberBetter == 0;

networkStrings = strings(numberRows,1);
for row = 1:numberRows
    perturbedIndices = nominalIndices;
    perturbedIndices(sensorPositionColumn(row)) = replacementIndexColumn(row);
    networkStrings(row) = string(mat2str(sort(perturbedIndices)));
end

tableOut = table( ...
    sensorPositionColumn,originalIndexColumn,replacementIndexColumn, ...
    replacementDistanceKm,objectiveColumn,improvementColumn,isBetter, ...
    networkStrings, ...
    'VariableNames',{'SensorPosition','OriginalCandidateIndex', ...
    'ReplacementCandidateIndex','ReplacementDistanceKm','Objective', ...
    'Improvement','BetterThanNominal','SensorIndices'});
end

%% ========================================================================
function [tableOut,result,objectiveCache] = evaluateJointSamples( ...
    nominalIndices,neighborIndices,nominalObjective,database,objectiveMode, ...
    numberSamples,seed,maximumAttempts,tolerance,objectiveCache)

networkSize = numel(nominalIndices);
rng(seed,"twister");
objectiveValues = zeros(numberSamples,1);
improvements = zeros(numberSamples,1);
changedSensorCounts = zeros(numberSamples,1);
networkStrings = strings(numberSamples,1);

for sampleIndex = 1:numberSamples
    accepted = false;
    for attempt = 1:maximumAttempts
        proposal = nominalIndices;
        for sensorPosition = 1:networkSize
            choices = [nominalIndices(sensorPosition),neighborIndices{sensorPosition}(:).'];
            proposal(sensorPosition) = choices(randi(numel(choices)));
        end
        if numel(unique(proposal)) == networkSize
            accepted = true;
            break
        end
    end
    assert(accepted, ...
        "Unable to generate a duplicate-free discrete-neighbor sample.");

    canonicalProposal = sort(proposal);
    [objectiveValues(sampleIndex),objectiveCache] = cachedObjective( ...
        canonicalProposal,database,objectiveMode,objectiveCache);
    improvements(sampleIndex) = nominalObjective-objectiveValues(sampleIndex);
    changedSensorCounts(sampleIndex) = nnz(proposal ~= nominalIndices);
    networkStrings(sampleIndex) = string(mat2str(canonicalProposal));
end

isBetter = objectiveValues < nominalObjective-tolerance;
[bestObjective,bestSample] = min(objectiveValues);
uniqueNetworks = unique(networkStrings);
result = struct();
result.numberSamples = numberSamples;
result.numberUniqueNetworks = numel(uniqueNetworks);
result.numberBetter = nnz(isBetter);
result.fractionBetter = result.numberBetter/numberSamples;
result.bestObjective = bestObjective;
result.maximumImprovement = nominalObjective-bestObjective;
result.bestSample = bestSample;
result.bestSensorIndices = sscanf(erase(networkStrings(bestSample),["[","]"]),'%f').';
if isempty(result.bestSensorIndices)
    result.bestSensorIndices = nominalIndices;
else
    result.bestSensorIndices = sort(result.bestSensorIndices);
end

sampleColumn = (1:numberSamples).';
tableOut = table(sampleColumn,objectiveValues,improvements,isBetter, ...
    changedSensorCounts,networkStrings, ...
    'VariableNames',{'Sample','Objective','Improvement','BetterThanNominal', ...
    'ChangedSensorCount','SensorIndices'});
end

%% ========================================================================
function [indices,distancesKm] = nearestEligibleCandidates( ...
    centerIndex,nominalIndices,latitudesRad,longitudesRad,moonRadiusKm,k)

centerLatitude = latitudesRad(centerIndex);
centerLongitude = longitudesRad(centerIndex);
cosCentralAngle = sin(centerLatitude).*sin(latitudesRad) + ...
    cos(centerLatitude).*cos(latitudesRad).*cos(longitudesRad-centerLongitude);
cosCentralAngle = min(1,max(-1,cosCentralAngle));
distances = moonRadiusKm*acos(cosCentralAngle);
distances(nominalIndices) = Inf;
[sortedDistances,sortedIndices] = sort(distances,"ascend");
finiteMask = isfinite(sortedDistances);
sortedDistances = sortedDistances(finiteMask);
sortedIndices = sortedIndices(finiteMask);
assert(numel(sortedIndices) >= k, ...
    "Not enough eligible neighboring candidates for candidate %d.",centerIndex);
indices = sortedIndices(1:k).';
distancesKm = sortedDistances(1:k).';
end

%% ========================================================================
function [objectiveValue,objectiveCache] = cachedObjective( ...
    sensorIndices,database,objectiveMode,objectiveCache)
key = networkKey(sensorIndices);
if isKey(objectiveCache,key)
    objectiveValue = objectiveCache(key);
    return
end
objectiveValue = optimization.networkObjective(sensorIndices,database,objectiveMode);
objectiveCache(key) = objectiveValue;
end

function key = networkKey(sensorIndices)
key = sprintf('%d_',sort(sensorIndices));
end

%% ========================================================================
function signature = buildSignature( ...
    databaseFile,summaryFiles,networkSizes,objectiveModes,config)
signature = struct();
signature.version = "discrete_neighbor_robustness_v1";
signature.databaseFile = databaseFile;
signature.databaseStamp = fileStamp(databaseFile);
signature.summaryFiles = summaryFiles;
signature.summaryStamps = zeros(numel(summaryFiles),2);
for fileIndex = 1:numel(summaryFiles)
    signature.summaryStamps(fileIndex,:) = fileStamp(summaryFiles(fileIndex));
end
signature.networkSizes = networkSizes;
signature.objectiveModes = objectiveModes;
signature.nearestNeighborCount = config.nearestNeighborCount;
signature.jointSamples = config.jointSamples;
signature.baseSeed = config.baseSeed;
signature.improvementTolerance = config.improvementTolerance;
end

function stamp = fileStamp(fileName)
info = dir(fileName);
assert(~isempty(info),"File not found while building cache signature: %s",fileName);
stamp = [double(info.bytes),double(info.datenum)];
end

%% ========================================================================
function writeOutputs(result,summaryFile,singleDetailFile,jointDetailFile)
writetable(result.summaryTable,summaryFile);
writetable(result.singleDetailTable,singleDetailFile);
writetable(result.jointDetailTable,jointDetailFile);
end

function printCompactSummary(summaryTable)
fprintf("\nDiscrete-neighbor local-optimality summary\n");
disp(summaryTable(:,{ ...
    'Objective','NetworkSize','SingleBetterCount','SingleNeighborTests', ...
    'MaximumSingleImprovement','JointBetterFraction','MaximumJointImprovement'}));
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for fieldIndex = 1:numel(fields)
    if isfield(output,fields{fieldIndex})
        output.(fields{fieldIndex}) = override.(fields{fieldIndex});
    end
end
end

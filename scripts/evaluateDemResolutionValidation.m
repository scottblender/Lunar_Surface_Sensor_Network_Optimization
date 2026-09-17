function result = evaluateDemResolutionValidation(productionInfo,userConfig)
% EVALUATEDEMRESOLUTIONVALIDATION Compare synthetic and full DEM terrain gates.
%
% This validation does not rerun the optimization. It evaluates the exact
% optimized sensor sites from the completed production study using both the
% synthetic production DEM and the full-resolution DEM source used by
% data/SyntheticLunarDEM.m. The comparison is limited to terrain-horizon
% geometry and terrain-informed observability so Earth/Sun screening cannot
% mask terrain-model differences.
%
% Main paper output:
%   conference_dem_resolution_validation.csv
%
% The table reports, for every N_s/objective best network:
%   - horizon-profile RMSE and maximum absolute difference;
%   - terrain LOS agreement, false-clear, and false-block percentages;
%   - network observable-epoch percentage under each DEM and the change in
%     percentage points.
%
% The full-resolution source DEM is treated as the reference. A false clear
% occurs when the synthetic DEM accepts terrain LOS while the full DEM rejects
% it.

arguments
    productionInfo (1,1) struct
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
sourceDirectory = fullfile(projectRoot,"src");
dataDirectory = fullfile(projectRoot,"data");
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
defaultConfig.syntheticDemFile = "";
defaultConfig.fullDemFile = "";
defaultConfig.reuseDemValidationCache = true;
config = mergeRecognized(defaultConfig,userConfig);

networkSizes = double(productionConfig.networkSizes(:).');
objectiveModes = lower(string(productionConfig.objectiveModes(:).'));
summaryFiles = string(productionInfo.studySummaryFiles);
databaseFile = string(productionInfo.databaseFile);
outputDirectory = string(productionInfo.outputDirectory);

assert(isfile(databaseFile),"Optimization database not found: %s",databaseFile);
assert(all(isfile(summaryFiles),"all"), ...
    "One or more production study summaries are missing.");

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization database file does not contain database.");
database = databaseData.database;

syntheticDemFile = resolveSyntheticDemFile(config.syntheticDemFile,database,dataDirectory);
fullDemFile = resolveFullDemFile( ...
    config.fullDemFile,dataDirectory,projectRoot,syntheticDemFile);
assert(isfile(syntheticDemFile),"Synthetic DEM not found: %s",syntheticDemFile);

moonRadiusKm = double(database.config.moon.radiusKm);
maximumRangeKm = double(database.config.terrain.maximumRangeKm);
rangeStepKm = double(database.config.terrain.rangeStepKm);
azimuthStepRad = double(database.config.terrain.horizonAzimuthStepRad);
horizonMarginRad = double(database.config.terrain.horizonMarginRad);
minimumElevationRad = double(database.config.visibility.minimumElevationRad);
theta0Rad = double(database.config.moon.theta0Rad);
angularRateRadS = 2*pi/double(database.config.moon.siderealPeriodSeconds);
times = double(database.tracking.times(:));
truthStateHistories = double(database.truth.optimizationStateHistories);

numberOfNetworkSizes = numel(networkSizes);
numberOfObjectives = numel(objectiveModes);
studies = cell(numberOfNetworkSizes,numberOfObjectives);
allSelectedIndices = zeros(0,1);
for objectiveIndex = 1:numberOfObjectives
    for networkIndex = 1:numberOfNetworkSizes
        loadedData = load(summaryFiles(networkIndex,objectiveIndex),"studyState");
        assert(isfield(loadedData,"studyState"), ...
            "Study summary does not contain studyState: %s", ...
            summaryFiles(networkIndex,objectiveIndex));
        studies{networkIndex,objectiveIndex} = loadedData.studyState;
        allSelectedIndices = [allSelectedIndices; ... %#ok<AGROW>
            double(loadedData.studyState.overallBestSensorIndices(:))];
    end
end
uniqueSelectedIndices = unique(allSelectedIndices,"stable");
selectedLatitudesRad = double(database.candidates.latitudesRad(uniqueSelectedIndices));
selectedLongitudesRad = double(database.candidates.longitudesRad(uniqueSelectedIndices));

cacheDirectory = fullfile(outputDirectory,"dem_validation_cache");
tableDirectory = fullfile(outputDirectory,"tables");
if ~isfolder(cacheDirectory), mkdir(cacheDirectory); end
if ~isfolder(tableDirectory), mkdir(tableDirectory); end
cacheFile = fullfile(cacheDirectory,"dem_resolution_validation.mat");
outputFile = fullfile(tableDirectory,"conference_dem_resolution_validation.csv");

signature = buildSignature(databaseFile,summaryFiles,syntheticDemFile, ...
    fullDemFile,uniqueSelectedIndices,maximumRangeKm,rangeStepKm,azimuthStepRad);
if config.reuseDemValidationCache && isfile(cacheFile)
    cachedData = load(cacheFile,"validationCache");
    if isfield(cachedData,"validationCache") && ...
            isfield(cachedData.validationCache,"signature") && ...
            isequaln(cachedData.validationCache.signature,signature)
        result = cachedData.validationCache.result;
        result.outputFile = string(outputFile);
        writetable(result.summaryTable,outputFile);
        fprintf("\nUsing cached DEM resolution validation: %s\n",cacheFile);
        disp(result.summaryTable);
        return
    end
end

fprintf("\n============================================================\n");
fprintf("DEM resolution validation at optimized sites\n");
fprintf("============================================================\n");
fprintf("Synthetic DEM: %s\n",syntheticDemFile);
fprintf("Full DEM source: %s\n",fullDemFile);
fprintf("Unique optimized sites: %d\n",numel(uniqueSelectedIndices));

syntheticDem = loadDemSource(syntheticDemFile,moonRadiusKm);
fullDem = loadDemSource(fullDemFile,moonRadiusKm);

[syntheticAzimuths,syntheticHorizon] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        selectedLatitudesRad,selectedLongitudesRad,syntheticDem, ...
        maximumRangeKm,rangeStepKm,azimuthStepRad,moonRadiusKm);
[fullAzimuths,fullHorizon] = ...
    digitalElevationModel.buildMaximumTerrainHorizonDatabase( ...
        selectedLatitudesRad,selectedLongitudesRad,fullDem, ...
        maximumRangeKm,rangeStepKm,azimuthStepRad,moonRadiusKm);

assert(isequal(size(syntheticHorizon),size(fullHorizon)), ...
    "Synthetic and full DEM horizon databases have different dimensions.");
assert(max(abs(syntheticAzimuths-fullAzimuths)) < 1e-12, ...
    "Synthetic and full DEM horizon azimuth grids differ.");

[syntheticTerrainAvailability,~,~,~,~] = ...
    optimization.buildTerrainAwareLosDatabase( ...
        times,truthStateHistories,selectedLatitudesRad,selectedLongitudesRad, ...
        syntheticDem,syntheticAzimuths,syntheticHorizon,minimumElevationRad, ...
        horizonMarginRad,moonRadiusKm,theta0Rad,angularRateRadS);
[fullTerrainAvailability,~,~,~,~] = ...
    optimization.buildTerrainAwareLosDatabase( ...
        times,truthStateHistories,selectedLatitudesRad,selectedLongitudesRad, ...
        fullDem,fullAzimuths,fullHorizon,minimumElevationRad, ...
        horizonMarginRad,moonRadiusKm,theta0Rad,angularRateRadS);

numberOfCases = numberOfNetworkSizes*numberOfObjectives;
objectiveColumn = strings(numberOfCases,1);
networkSizeColumn = zeros(numberOfCases,1);
uniqueSiteCount = zeros(numberOfCases,1);
horizonRmseDeg = zeros(numberOfCases,1);
maximumAbsHorizonDifferenceDeg = zeros(numberOfCases,1);
terrainLosAgreementPercent = zeros(numberOfCases,1);
falseClearPercent = zeros(numberOfCases,1);
falseBlockPercent = zeros(numberOfCases,1);
syntheticObservableEpochPercent = zeros(numberOfCases,1);
fullObservableEpochPercent = zeros(numberOfCases,1);
deltaObservableEpochPercentagePoints = zeros(numberOfCases,1);
terrainDecisionCount = zeros(numberOfCases,1);

caseIndex = 0;
for objectiveIndex = 1:numberOfObjectives
    objectiveMode = objectiveModes(objectiveIndex);
    for networkIndex = 1:numberOfNetworkSizes
        caseIndex = caseIndex + 1;
        networkSize = networkSizes(networkIndex);
        nominalIndices = sort(double( ...
            studies{networkIndex,objectiveIndex}.overallBestSensorIndices(:)));
        [present,localSiteIndices] = ismember(nominalIndices,uniqueSelectedIndices);
        assert(all(present),"Optimized site was not found in validation-site union.");

        syntheticCaseHorizon = syntheticHorizon(localSiteIndices,:);
        fullCaseHorizon = fullHorizon(localSiteIndices,:);
        horizonDifference = syntheticCaseHorizon-fullCaseHorizon;

        syntheticCaseAvailability = ...
            syntheticTerrainAvailability(localSiteIndices,:,:);
        fullCaseAvailability = fullTerrainAvailability(localSiteIndices,:,:);
        agreement = syntheticCaseAvailability == fullCaseAvailability;
        falseClear = syntheticCaseAvailability & ~fullCaseAvailability;
        falseBlock = ~syntheticCaseAvailability & fullCaseAvailability;

        syntheticNetworkAvailability = squeeze(any(syntheticCaseAvailability,1));
        fullNetworkAvailability = squeeze(any(fullCaseAvailability,1));

        objectiveColumn(caseIndex) = objectiveMode;
        networkSizeColumn(caseIndex) = networkSize;
        uniqueSiteCount(caseIndex) = numel(nominalIndices);
        horizonRmseDeg(caseIndex) = rad2deg(sqrt(mean(horizonDifference.^2,"all")));
        maximumAbsHorizonDifferenceDeg(caseIndex) = ...
            rad2deg(max(abs(horizonDifference),[],"all"));
        terrainLosAgreementPercent(caseIndex) = 100*mean(agreement,"all");
        falseClearPercent(caseIndex) = 100*mean(falseClear,"all");
        falseBlockPercent(caseIndex) = 100*mean(falseBlock,"all");
        syntheticObservableEpochPercent(caseIndex) = ...
            100*mean(syntheticNetworkAvailability,"all");
        fullObservableEpochPercent(caseIndex) = ...
            100*mean(fullNetworkAvailability,"all");
        deltaObservableEpochPercentagePoints(caseIndex) = ...
            syntheticObservableEpochPercent(caseIndex)- ...
            fullObservableEpochPercent(caseIndex);
        terrainDecisionCount(caseIndex) = numel(agreement);
    end
end

summaryTable = table( ...
    objectiveColumn,networkSizeColumn,uniqueSiteCount,horizonRmseDeg, ...
    maximumAbsHorizonDifferenceDeg,terrainLosAgreementPercent, ...
    falseClearPercent,falseBlockPercent,syntheticObservableEpochPercent, ...
    fullObservableEpochPercent,deltaObservableEpochPercentagePoints, ...
    terrainDecisionCount, ...
    'VariableNames',{ ...
    'Objective','NetworkSize','SiteCount','HorizonRmseDeg', ...
    'MaximumAbsHorizonDifferenceDeg','TerrainLosAgreementPercent', ...
    'FalseClearPercent','FalseBlockPercent', ...
    'SyntheticObservableEpochPercent','FullObservableEpochPercent', ...
    'DeltaObservableEpochPercentagePoints','TerrainDecisionCount'});

result = struct();
result.version = "dem_resolution_validation_v2";
result.created = string(datetime("now"));
result.syntheticDemFile = syntheticDemFile;
result.fullDemFile = fullDemFile;
result.uniqueSelectedCandidateIndices = uniqueSelectedIndices;
result.horizonAzimuthsRad = syntheticAzimuths;
result.syntheticHorizonRad = syntheticHorizon;
result.fullHorizonRad = fullHorizon;
result.summaryTable = summaryTable;
result.outputFile = string(outputFile);
result.cacheFile = string(cacheFile);

writetable(summaryTable,outputFile);
validationCache = struct("signature",signature,"result",result); %#ok<NASGU>
save(cacheFile,"validationCache","-v7.3");

fprintf("\nDEM resolution validation summary\n");
disp(summaryTable);
end

function syntheticDemFile = resolveSyntheticDemFile(requestedFile,database,dataDirectory)
requestedFile = string(requestedFile);
if strlength(requestedFile) > 0
    syntheticDemFile = requestedFile;
    return
end
if isfield(database,"config") && isfield(database.config,"demSource")
    candidate = string(database.config.demSource);
    if strlength(candidate) > 0 && isfile(candidate)
        syntheticDemFile = candidate;
        return
    end
end
candidateNames = ["Synthetic:LunarDEM.mat","Synthetic_LunarDEM.mat", ...
    "SyntheticLunarDEM.mat"];
for index = 1:numel(candidateNames)
    candidate = string(fullfile(dataDirectory,candidateNames(index)));
    if isfile(candidate)
        syntheticDemFile = candidate;
        return
    end
end
error("evaluateDemResolutionValidation:SyntheticDemNotFound", ...
    "Synthetic lunar DEM could not be resolved from the database or data directory.");
end

function fullDemFile = resolveFullDemFile( ...
    requestedFile,dataDirectory,projectRoot,syntheticDemFile)
requestedFile = string(requestedFile);
if strlength(requestedFile) > 0
    if isfile(requestedFile)
        fullDemFile = requestedFile;
        return
    end
    error("evaluateDemResolutionValidation:FullDemNotFound", ...
        "Requested full-resolution DEM was not found: %s",requestedFile);
end

% The local data directory is gitignored. The project-specific generator is
% data/SyntheticLunarDEM.m. Read that script and resolve the highest-resolution
% DEM MAT-file it references, excluding the synthetic production DEM itself.
generatorScript = string(fullfile(dataDirectory,"SyntheticLunarDEM.mat"));
if ~isfile(generatorScript)
    matches = dir(fullfile(projectRoot,"**","SyntheticLunarDEM.mat"));
    if ~isempty(matches)
        generatorScript = string(fullfile(matches(1).folder,matches(1).name));
    end
end

if isfile(generatorScript)
    fullDemFile = resolveDemInputFromGenerator( ...
        generatorScript,syntheticDemFile,dataDirectory,projectRoot);
    if strlength(fullDemFile) > 0
        return
    end
    error("evaluateDemResolutionValidation:FullDemNotResolvedFromGenerator", ...
        "Found %s, but no full-resolution DEM MAT-file referenced by the script could be resolved. Provide userConfig.fullDemFile if the source DEM path is constructed dynamically.", ...
        generatorScript);
end

error("evaluateDemResolutionValidation:FullDemNotFound", ...
    "Full-resolution DEM source not found. Expected data/SyntheticLunarDEM.m or provide the exact DEM MAT-file with userConfig.fullDemFile.");
end

function fullDemFile = resolveDemInputFromGenerator( ...
    generatorScript,syntheticDemFile,dataDirectory,projectRoot)
fullDemFile = "";
scriptText = fileread(generatorScript);

% Extract quoted MAT-file paths from load/save statements and other literal
% references. The full-resolution input is selected by DEM validity and grid
% sample count, not simply by filename.
quotedMatFiles = regexp(scriptText, ...
    '["'']([^"'']+\.mat)["'']','tokens');
if isempty(quotedMatFiles)
    return
end

literalPaths = strings(numel(quotedMatFiles),1);
for index = 1:numel(quotedMatFiles)
    literalPaths(index) = string(quotedMatFiles{index}{1});
end
literalPaths = unique(literalPaths,"stable");

scriptFolder = string(fileparts(generatorScript));
resolvedCandidates = strings(0,1);
for index = 1:numel(literalPaths)
    literalPath = literalPaths(index);
    pathCandidates = [ ...
        literalPath; ...
        string(fullfile(scriptFolder,literalPath)); ...
        string(fullfile(dataDirectory,literalPath)); ...
        string(fullfile(projectRoot,literalPath))];

    for candidateIndex = 1:numel(pathCandidates)
        candidate = pathCandidates(candidateIndex);
        if isfile(candidate)
            resolvedCandidates(end+1,1) = candidate; %#ok<AGROW>
            break
        end
    end
end

if isempty(resolvedCandidates)
    return
end
resolvedCandidates = unique(resolvedCandidates,"stable");

bestScore = -Inf;
for index = 1:numel(resolvedCandidates)
    candidate = resolvedCandidates(index);
    if sameFile(candidate,syntheticDemFile)
        continue
    end
    score = demSampleCount(candidate);
    if score > bestScore
        bestScore = score;
        fullDemFile = candidate;
    end
end

if strlength(fullDemFile) > 0
    fprintf("Resolved full-resolution DEM from %s:\n  %s\n", ...
        generatorScript,fullDemFile);
end
end

function score = demSampleCount(fileName)
score = -Inf;
try
    fileVariables = whos("-file",fileName);
catch
    return
end

for variableIndex = 1:numel(fileVariables)
    variableInfo = fileVariables(variableIndex);
    variableClass = string(variableInfo.class);
    variableName = string(variableInfo.name);

    if variableClass == "griddedInterpolant"
        try
            loaded = load(fileName,variableName);
            value = loaded.(variableName);
            if numel(value.GridVectors) == 2
                score = max(score,numel(value.Values));
            end
        catch
        end
        continue
    end

    if ~ismember(variableClass,["double","single","int8","uint8", ...
            "int16","uint16","int32","uint32","int64","uint64"])
        continue
    end

    variableSize = double(variableInfo.size);
    if numel(variableSize) == 2 && variableSize(1) > 1 && ...
            variableSize(2) == 2*variableSize(1)
        score = max(score,prod(variableSize));
    end
end
end

function tf = sameFile(firstFile,secondFile)
firstFile = string(firstFile);
secondFile = string(secondFile);
if strlength(secondFile) == 0
    tf = false;
    return
end
try
    firstInfo = dir(firstFile);
    secondInfo = dir(secondFile);
    tf = ~isempty(firstInfo) && ~isempty(secondInfo) && ...
        strcmpi(string(fullfile(firstInfo(1).folder,firstInfo(1).name)), ...
        string(fullfile(secondInfo(1).folder,secondInfo(1).name)));
catch
    tf = strcmpi(firstFile,secondFile);
end
end

function dem = loadDemSource(sourceFile,moonRadiusKm)
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(sourceFile),moonRadiusKm,24,48);
end

function signature = buildSignature(databaseFile,summaryFiles,syntheticDemFile, ...
    fullDemFile,selectedIndices,maximumRangeKm,rangeStepKm,azimuthStepRad)
signature = struct();
signature.version = "dem_resolution_validation_v2";
signature.databaseStamp = fileStamp(databaseFile);
signature.summaryStamps = zeros(numel(summaryFiles),2);
for index = 1:numel(summaryFiles)
    signature.summaryStamps(index,:) = fileStamp(summaryFiles(index));
end
signature.syntheticDemStamp = fileStamp(syntheticDemFile);
signature.fullDemStamp = fileStamp(fullDemFile);
signature.selectedIndices = selectedIndices;
signature.maximumRangeKm = maximumRangeKm;
signature.rangeStepKm = rangeStepKm;
signature.azimuthStepRad = azimuthStepRad;
end

function stamp = fileStamp(fileName)
info = dir(fileName);
assert(~isempty(info),"File not found while building validation signature: %s",fileName);
stamp = [double(info.bytes),double(info.datenum)];
end

function output = mergeRecognized(defaults,override)
output = defaults;
fields = fieldnames(override);
for index = 1:numel(fields)
    if isfield(output,fields{index})
        output.(fields{index}) = override.(fields{index});
    end
end
end

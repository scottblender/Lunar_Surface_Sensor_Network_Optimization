function result = evaluateDemResolutionValidation(productionInfo,userConfig)
% EVALUATEDEMRESOLUTIONVALIDATION Compare synthetic and full DEM terrain gates.
%
% This validation does not rerun the optimization. It evaluates the exact
% overall-best sensor sites from the completed production study using:
%   synthetic DEM: data/Synthetic_Lunar_DEM.mat
%   full DEM:      data/Full_Resolution_DEM.mat
%
% The comparison is limited to terrain-horizon geometry and terrain-informed
% observability so Earth/Sun screening cannot mask terrain-model differences.
%
% Main paper output:
%   conference_dem_resolution_validation.csv
%
% The full-resolution DEM is treated as the reference. A false clear occurs
% when the synthetic DEM accepts terrain LOS while the full DEM rejects it.

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

if ~isfile(databaseFile)
    error('evaluateDemResolutionValidation:DatabaseNotFound', ...
        'Optimization database not found: %s',char(databaseFile));
end
if ~all(isfile(summaryFiles),"all")
    error('evaluateDemResolutionValidation:StudySummaryNotFound', ...
        'One or more production study summaries are missing.');
end

databaseData = load(databaseFile,"database");
assert(isfield(databaseData,"database"), ...
    "Optimization database file does not contain database.");
database = databaseData.database;

syntheticDemFile = resolveDemFile( ...
    config.syntheticDemFile,dataDirectory,projectRoot,"Synthetic_Lunar_DEM.mat", ...
    'evaluateDemResolutionValidation:SyntheticDemNotFound',"synthetic");
fullDemFile = resolveDemFile( ...
    config.fullDemFile,dataDirectory,projectRoot,"Full_Resolution_DEM.mat", ...
    'evaluateDemResolutionValidation:FullDemNotFound',"full-resolution");

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
        summaryFile = summaryFiles(networkIndex,objectiveIndex);
        loadedData = load(summaryFile,"studyState");
        if ~isfield(loadedData,"studyState")
            error('evaluateDemResolutionValidation:MissingStudyState', ...
                'Study summary does not contain studyState: %s',char(summaryFile));
        end
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
fprintf("Full DEM:      %s\n",fullDemFile);
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
result.version = "dem_resolution_validation_v4_renamed_dem_files";
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

function fileName = resolveDemFile( ...
    requestedFile,dataDirectory,projectRoot,defaultName,errorId,description)
requestedFile = string(requestedFile);
if strlength(requestedFile) > 0
    if isfile(requestedFile)
        fileName = requestedFile;
        return
    end
    error(char(errorId), ...
        'Requested %s DEM was not found: %s',char(description),char(requestedFile));
end

fileName = string(fullfile(dataDirectory,defaultName));
if isfile(fileName)
    return
end

matches = dir(fullfile(projectRoot,"**",defaultName));
if ~isempty(matches)
    fileName = string(fullfile(matches(1).folder,matches(1).name));
    return
end

error(char(errorId), ...
    'Could not find %s DEM. Expected %s.',char(description),char(fullfile(dataDirectory,defaultName)));
end

function dem = loadDemSource(sourceFile,moonRadiusKm)
[dem,~] = digitalElevationModel.loadTriaxialLunarDem( ...
    string(sourceFile),moonRadiusKm,24,48);
end

function signature = buildSignature(databaseFile,summaryFiles,syntheticDemFile, ...
    fullDemFile,selectedIndices,maximumRangeKm,rangeStepKm,azimuthStepRad)
signature = struct();
signature.version = "dem_resolution_validation_v4_renamed_dem_files";
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
if isempty(info)
    error('evaluateDemResolutionValidation:SignatureFileNotFound', ...
        'File not found while building validation signature: %s',char(string(fileName)));
end
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

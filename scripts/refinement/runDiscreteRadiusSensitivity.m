function study = runDiscreteRadiusSensitivity(userConfig)
% RUNDISCRETERADIUSSENSITIVITY - Sweep geographic refinement radii around a fixed sensor network.
%
% Inputs:
%   - userConfig - Starting study/network, database, radii, and sweep settings.
%
% Outputs:
%   - study - Radius results, shared evaluation counts, and elbow summary.
%
% See also runDiscreteRadiusStudy, analyzeSavedDiscreteRadiusStudy.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(fileparts(scriptDirectory));
addpath(fullfile(projectRoot,"src"));

config = struct();
config.studySummaryFile = "";
config.databaseFile = "";
config.maximumRemapDistanceKm = [];
config.initialSensorIndices = [];
config.objectiveMode = "";
config.radiiKm = [10 20 30 40 50 60];
config.maximumCombinations = 50000;
config.skipOversized = true;
config.improvementTolerance = 1e-10;
config.captureFraction = 0.95;
config.marginalThresholdPct = 1;
config.outputDirectory = "";
config.saveResults = true;
config.makePlots = true;
config.studyState = struct();
config.database = struct();
config.objectiveFcn = [];

names = fieldnames(userConfig);
for i = 1:numel(names)
    name = names{i};
    assert(isfield(config,name), ...
        "runDiscreteRadiusSensitivity:UnknownOption", ...
        "Unknown option: %s",name);
    config.(name) = userConfig.(name);
end

radiiKm = double(config.radiiKm(:));
validateattributes(radiiKm,{'double'}, ...
    {'vector','nonempty','real','finite','nonnegative'});
assert(all(diff(radiiKm) > 0), ...
    "runDiscreteRadiusSensitivity:RadiiNotIncreasing", ...
    "radiiKm must be strictly increasing with no repeated values.");
assert(isnumeric(config.maximumCombinations) && ...
    isscalar(config.maximumCombinations) && ...
    isreal(config.maximumCombinations) && ...
    config.maximumCombinations > 0 && ...
    (isinf(config.maximumCombinations) || ...
    (isfinite(config.maximumCombinations) && ...
     config.maximumCombinations == floor(config.maximumCombinations))), ...
    "runDiscreteRadiusSensitivity:InvalidCombinationLimit", ...
    'maximumCombinations must be a positive integer or Inf.');
validateattributes(config.improvementTolerance,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(config.captureFraction,{'numeric'}, ...
    {'scalar','real','finite','>',0,'<=',1});
validateattributes(config.marginalThresholdPct,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
assert(islogical(config.skipOversized) && isscalar(config.skipOversized));
assert(islogical(config.saveResults) && isscalar(config.saveResults));
assert(islogical(config.makePlots) && isscalar(config.makePlots));
if ~isempty(config.maximumRemapDistanceKm)
    validateattributes(config.maximumRemapDistanceKm,{'numeric'}, ...
        {'scalar','real','finite','nonnegative'});
end

%% Determine the fixed starting network (no global optimizer rerun).
% Use direct IDs to reproduce a standalone refinement on the current database.
summaryFile = "";
if ~isempty(config.initialSensorIndices)
    assert(strlength(string(config.studySummaryFile)) == 0 && ...
        isempty(fieldnames(config.studyState)), ...
        "runDiscreteRadiusSensitivity:AmbiguousNetworkSource", ...
        ['Specify either initialSensorIndices/objectiveMode or a saved ' ...
         'study, not both.']);
    validateattributes(config.initialSensorIndices,{'numeric'}, ...
        {'vector','nonempty','real','finite','integer','positive'});
    requestedMode = lower(string(config.objectiveMode));
    assert(isscalar(requestedMode) && ...
        ismember(requestedMode,["coverage","information"]), ...
        "runDiscreteRadiusSensitivity:DirectModeRequired", ...
        "With initialSensorIndices, set config.objectiveMode to coverage or information.");
    studyState = struct();
    studyState.overallBestSensorIndices = ...
        double(config.initialSensorIndices(:));
    studyState.config = struct("objectiveMode",requestedMode);
    startingNetworkSource = "explicit_indices";
else
    assert(strlength(string(config.objectiveMode)) == 0, ...
        "runDiscreteRadiusSensitivity:AmbiguousNetworkSource", ...
        "objectiveMode may be specified directly only with initialSensorIndices.");
    startingNetworkSource = "saved_study";
    if ~isempty(fieldnames(config.studyState))
        studyState = config.studyState;
    else
        summaryFile = string(config.studySummaryFile);
        if strlength(summaryFile) == 0
            summaryFile = findLatestStudySummary(projectRoot);
        else
            summaryFile = resolveRelativeFile(summaryFile,projectRoot);
        end
        assert(isfile(summaryFile), ...
            "runDiscreteRadiusSensitivity:StudyNotFound", ...
            "Study summary not found: %s",summaryFile);
        D = load(summaryFile,"studyState");
        assert(isfield(D,"studyState"), ...
            "runDiscreteRadiusSensitivity:InvalidStudy", ...
            "The summary MAT file does not contain studyState.");
        studyState = D.studyState;
    end
end

assert(isfield(studyState,"overallBestSensorIndices") && ...
    isfield(studyState,"config") && ...
    isfield(studyState.config,"objectiveMode"), ...
    "runDiscreteRadiusSensitivity:InvalidStudy", ...
    "studyState needs overallBestSensorIndices and config.objectiveMode.");
originalIndices = sort(double(studyState.overallBestSensorIndices(:)));
objectiveMode = lower(string(studyState.config.objectiveMode));
assert(isscalar(objectiveMode) && ...
    ismember(objectiveMode,["coverage","information"]), ...
    "runDiscreteRadiusSensitivity:InvalidObjectiveMode", ...
    "Expected a coverage or information optimization study.");

% Use the current database; a historical study path may refer to rebuilt data.
if ~isempty(fieldnames(config.database))
    database = config.database;
    databaseFile = "";
else
    databaseFile = string(config.databaseFile);
    if strlength(databaseFile) == 0
        databaseFile = fullfile( ...
            projectRoot,"results","optimization_database.mat");
    else
        databaseFile = resolveRelativeFile(databaseFile,projectRoot);
    end
    assert(isfile(databaseFile), ...
        "runDiscreteRadiusSensitivity:DatabaseNotFound", ...
        "Current optimization database not found: %s",databaseFile);
    S = load(databaseFile,"database");
    assert(isfield(S,"database"), ...
        "runDiscreteRadiusSensitivity:InvalidDatabase", ...
        "Database MAT file does not contain database.");
    database = S.database;
end
assert(isfield(database,"candidates") && ...
    isfield(database.candidates,"latitudesRad") && ...
    isfield(database.candidates,"longitudesRad") && ...
    isfield(database,"config") && isfield(database.config,"moon") && ...
    isfield(database.config.moon,"radiusKm"), ...
    "runDiscreteRadiusSensitivity:InvalidDatabase", ...
    "Current database lacks lunar candidate coordinates or Moon radius.");
currentLatitude = double(database.candidates.latitudesRad(:));
currentLongitude = double(database.candidates.longitudesRad(:));
assert(numel(currentLatitude) == numel(currentLongitude) && ...
    all(isfinite(currentLatitude)) && all(isfinite(currentLongitude)) && ...
    numel(currentLatitude) >= numel(originalIndices), ...
    "runDiscreteRadiusSensitivity:InvalidDatabase", ...
    "Current candidate-grid coordinate arrays are invalid.");
moonRadiusKm = double(database.config.moon.radiusKm);
validateattributes(moonRadiusKm,{'numeric'}, ...
    {'scalar','finite','real','positive'});

% Preserve study provenance as metadata ONLY. The baseline and all
% refinements are evaluated anew on the selected CURRENT database.
savedOriginalIndices = originalIndices;
savedDatabaseVersion = "";
currentDatabaseVersion = "";
if isfield(database,"meta") && isfield(database.meta,"version")
    currentDatabaseVersion = string(database.meta.version);
end
mappingDistancesKm = zeros(numel(originalIndices),1);
mappingApplied = false;
savedObjective = NaN;

if startingNetworkSource == "saved_study"
    savedLat = [];
    savedLon = [];
    if isfield(studyState,"overallBestObjective")
        savedObjective = double(studyState.overallBestObjective);
    end
    if isfield(studyState,"runStates") && ...
            isfield(studyState,"overallBestRunIndex") && ...
            ~isempty(studyState.runStates)
        bestRun = studyState.runStates{studyState.overallBestRunIndex};
        if isfield(bestRun,"databaseVersion")
            savedDatabaseVersion = string(bestRun.databaseVersion);
        end
        if isfield(bestRun,"bestSensorLatitudesRad") && ...
                isfield(bestRun,"bestSensorLongitudesRad")
            savedLat = double(bestRun.bestSensorLatitudesRad(:));
            savedLon = double(bestRun.bestSensorLongitudesRad(:));
        end
    end
    if isempty(savedLat) && ...
            isfield(studyState,"overallBestSensorTable")
        T = studyState.overallBestSensorTable;
        if istable(T) && all(ismember( ...
                {'LatitudeDeg','LongitudeDeg'},T.Properties.VariableNames))
            savedLat = deg2rad(double(T.LatitudeDeg(:)));
            savedLon = deg2rad(double(T.LongitudeDeg(:)));
        end
    end

    if ~isempty(savedLat) && numel(savedLat) == numel(originalIndices) && ...
            numel(savedLon) == numel(originalIndices)
        % Sorted ID order is canonical for the initial network and the
        % saved run state. Map each physical location onto the new grid.
        if isfield(studyState,"overallBestSensorIndices")
            [~,order] = sort(double(studyState.overallBestSensorIndices(:)));
            savedLat = savedLat(order);
            savedLon = savedLon(order);
        end
        maxDistanceKm = double(config.maximumRemapDistanceKm);
        if isempty(maxDistanceKm)
            maxDistanceKm = 30;
            if isfield(database.config,"candidates") && ...
                    isfield(database.config.candidates,"spacingKm")
                spacing = double(database.config.candidates.spacingKm);
                if isscalar(spacing) && isfinite(spacing) && spacing > 0
                    maxDistanceKm = 2*spacing;
                end
            end
        end
        mappedIndices = zeros(numel(savedLat),1);
        mappingDistancesKm = zeros(numel(savedLat),1);
        for sensor = 1:numel(savedLat)
            dLat = currentLatitude-savedLat(sensor);
            dLon = currentLongitude-savedLon(sensor);
            haversine = sin(dLat/2).^2 + ...
                cos(savedLat(sensor)).*cos(currentLatitude).* ...
                sin(dLon/2).^2;
            distances = 2*moonRadiusKm*asin( ...
                sqrt(min(1,max(0,haversine))));
            [mappingDistancesKm(sensor),mappedIndices(sensor)] = ...
                min(distances);
        end
        assert(all(mappingDistancesKm <= maxDistanceKm+1e-9), ...
            "runDiscreteRadiusSensitivity:RemapTooFar", ...
            ['A saved observer is farther than %.3f km from its nearest ' ...
             'CURRENT candidate (max displacement %.3f km). ' ...
             'Inspect the saved coordinates/current grid or adjust ' ...
             'maximumRemapDistanceKm explicitly.'], ...
            maxDistanceKm,max(mappingDistancesKm));
        assert(numel(unique(mappedIndices)) == numel(mappedIndices), ...
            "runDiscreteRadiusSensitivity:RemapCollision", ...
            ['Two saved observers mapped to the same current candidate. ' ...
             'Select a new distinct current-grid network explicitly.']);
        mappingApplied = any(mappedIndices ~= originalIndices) || ...
            any(mappingDistancesKm > 1e-6);
        originalIndices = sort(mappedIndices);
        if mappingApplied
            fprintf(['Mapped saved observer positions to current ' ...
                'candidate IDs: %s (max offset %.3f km).\n'], ...
                mat2str(originalIndices(:).'),max(mappingDistancesKm));
        end
    else
        % Same database/version and unambiguous saved indices can still
        % be used for older studies lacking explicit saved coordinates.
        assert(strlength(savedDatabaseVersion) > 0 && ...
            savedDatabaseVersion == currentDatabaseVersion && ...
            all(originalIndices >= 1) && ...
            all(originalIndices <= numel(currentLatitude)), ...
            "runDiscreteRadiusSensitivity:MissingSavedCoordinates", ...
            ['The saved study lacks per-observer coordinates needed ' ...
             'to transfer its sites to the CURRENT database. ' ...
             'Supply config.initialSensorIndices from the current grid ' ...
             'and config.objectiveMode explicitly instead.']);
    end
end

% Do not claim the old objective is comparable: all reported J and
% improvements use the newly recomputed CURRENT-database baseline.
if isempty(config.objectiveFcn)
    productionObjective = @(indices) optimization.networkObjective( ...
        indices,database,objectiveMode);
else
    assert(isa(config.objectiveFcn,"function_handle"), ...
        "runDiscreteRadiusSensitivity:InvalidObjectiveFcn", ...
        "objectiveFcn must be a function handle.");
    productionObjective = config.objectiveFcn;
end

%% Estimate search sizes before running expensive objectives.
% Mirrors the Haversine-radius convention in refineDiscreteNetwork.

numberOfRadii = numel(radiiKm);
neighborhoodSizes = zeros(numberOfRadii,numel(originalIndices));
combinationCounts = zeros(numberOfRadii,1);
lat = double(database.candidates.latitudesRad(:));
lon = double(database.candidates.longitudesRad(:));
R = double(database.config.moon.radiusKm);
for i = 1:numel(originalIndices)
    center = originalIndices(i);
    dLat = lat-lat(center);
    dLon = lon-lon(center);
    h = sin(dLat/2).^2 + cos(lat(center)).*cos(lat).* ...
        sin(dLon/2).^2;
    distanceKm = 2*R*asin(sqrt(min(1,max(0,h))));
    for k = 1:numberOfRadii
        tolKm = max(1e-9,32*eps(max(1,radiiKm(k))));
        neighborhoodSizes(k,i) = max(1, ...
            nnz(distanceKm <= radiiKm(k)+tolKm));
    end
end
combinationCounts = prod(neighborhoodSizes,2);

%% Each radius starts at the SAME global network, but shares a cached
% objective evaluator. The cache avoids rerunning any previous network.
sharedCache = containers.Map('KeyType','char','ValueType','double');
refinementResults = cell(numberOfRadii,1);
status = repmat("pending",numberOfRadii,1);
bestObjectiveByRadius = NaN(numberOfRadii,1);
newObjectiveEvaluations = zeros(numberOfRadii,1);
cumulativeObjectiveEvaluations = zeros(numberOfRadii,1);
independentNetworkCounts = NaN(numberOfRadii,1);
runTimesSeconds = NaN(numberOfRadii,1);
originalObjective = NaN;
previousBest = NaN;

fprintf("\n============================================================\n");
fprintf("Lunar discrete refinement: radius sensitivity\n");
fprintf("============================================================\n");
fprintf("Mode:          %s\n",objectiveMode);
fprintf("Sensor count:  %d\n",numel(originalIndices));
fprintf("Original IDs:  %s\n",mat2str(originalIndices(:).'));
fprintf("Starting source: %s\n",startingNetworkSource);
fprintf("Combination limit: %.0f\n",config.maximumCombinations);

for k = 1:numberOfRadii
    radius = radiiKm(k);
    if combinationCounts(k) > config.maximumCombinations || ...
            ~isfinite(combinationCounts(k))
        if ~config.skipOversized
            error("runDiscreteRadiusSensitivity:TooManyCombinations", ...
                'Radius %.4g km has %.0f combinations (limit %.0f).', ...
                radius,combinationCounts(k),config.maximumCombinations);
        end
        status(k) = "skipped_limit";
        cumulativeObjectiveEvaluations(k) = double(sharedCache.Count);
        fprintf("  %7.2f km: SKIPPED (%.0f combinations)\n", ...
            radius,combinationCounts(k));
        continue
    end

    beforeFe = double(sharedCache.Count);
    options = struct();
    options.maximumCombinations = config.maximumCombinations;
    options.improvementTolerance = config.improvementTolerance;
    options.objectiveFcn = @cachedObjective;

    localResult = optimization.refineDiscreteNetwork( ...
        originalIndices,database,objectiveMode,radius,options);
    refinementResults{k} = localResult;
    bestObjectiveByRadius(k) = localResult.bestObjective;
    independentNetworkCounts(k) = localResult.numberOfUniqueNetworks;
    runTimesSeconds(k) = localResult.elapsedSeconds;
    cumulativeObjectiveEvaluations(k) = double(sharedCache.Count);
    newObjectiveEvaluations(k) = ...
        cumulativeObjectiveEvaluations(k)-beforeFe;
    status(k) = "completed";

    if isnan(originalObjective)
        originalObjective = localResult.initialObjective;
    else
        assert(abs(localResult.initialObjective-originalObjective) <= ...
            1e-10*max(1,abs(originalObjective)), ...
            "runDiscreteRadiusSensitivity:InconsistentInitialObjective", ...
            "The nominal objective changed during the radius sweep.");
    end
    if ~isnan(previousBest)
        assert(localResult.bestObjective <= previousBest+ ...
            config.improvementTolerance+1e-10*max(1,abs(previousBest)), ...
            "runDiscreteRadiusSensitivity:NonMonotonic", ...
            "The best objective increased with the search radius.");
    end
    previousBest = localResult.bestObjective;

    fprintf("  %7.2f km: J = %.12g, new FE = %.0f, total FE = %.0f\n", ...
        radius,localResult.bestObjective, ...
        newObjectiveEvaluations(k),cumulativeObjectiveEvaluations(k));
end

completed = status == "completed";
assert(any(completed), ...
    "runDiscreteRadiusSensitivity:NoCompletedRadii", ...
    ['No radius completed. Reduce the radii or raise ' ...
     'maximumCombinations explicitly.']);
completedIndices = find(completed);
lastIndex = completedIndices(end);

%% Improvement, marginal gain, and r95 (empirical, largest completed r).

gain = NaN(numberOfRadii,1);
marginalGain = NaN(numberOfRadii,1);
relativeImprovementPct = NaN(numberOfRadii,1);
marginalRelativeImprovementPct = NaN(numberOfRadii,1);
bestScore = NaN(numberOfRadii,1);
capturedPct = NaN(numberOfRadii,1);
previousBest = originalObjective;
for k = completedIndices(:).'
    currentBest = bestObjectiveByRadius(k);
    gain(k) = originalObjective-currentBest;
    marginalGain(k) = previousBest-currentBest;
    bestScore(k) = -currentBest; % maximized information/coverage score
    if abs(originalObjective) > eps
        relativeImprovementPct(k) = 100*gain(k)/abs(originalObjective);
    elseif abs(gain(k)) <= eps
        relativeImprovementPct(k) = 0;
    end
    if abs(previousBest) > eps
        marginalRelativeImprovementPct(k) = ...
            100*marginalGain(k)/abs(previousBest);
    elseif abs(marginalGain(k)) <= eps
        marginalRelativeImprovementPct(k) = 0;
    end
    previousBest = currentBest;
end

% Choose the last material gain only when a larger tested radius shows a plateau.
tradeoffRadiusKm = NaN;
material = find(completed & isfinite(marginalRelativeImprovementPct) & ...
    marginalRelativeImprovementPct >= config.marginalThresholdPct);
if ~isempty(material) && material(end) < lastIndex
    tradeoffRadiusKm = radiiKm(material(end));
end
tradeoffProvisional = any(~completed);

maximumObservedGain = max(0,originalObjective- ...
    bestObjectiveByRadius(lastIndex));
radiusAtCaptureKm = NaN;
if maximumObservedGain > 0
    capturedPct(completed) = ...
        100*max(0,gain(completed))/maximumObservedGain;
    firstCapture = find(completed & ...
        capturedPct >= 100*config.captureFraction-1e-10,1,"first");
    radiusAtCaptureKm = radiiKm(firstCapture);
else
    capturedPct(completed) = 0;
end

summaryTable = table( ...
    radiiKm,status,combinationCounts,bestObjectiveByRadius,bestScore, ...
    gain,relativeImprovementPct,marginalGain, ...
    marginalRelativeImprovementPct,capturedPct, ...
    independentNetworkCounts,newObjectiveEvaluations, ...
    cumulativeObjectiveEvaluations,runTimesSeconds, ...
    'VariableNames',{'RadiusKm','Status','CartesianCombinations', ...
    'BestJ','BestScore','Improvement','RelativeImprovementPct', ...
    'MarginalImprovement','MarginalRelativeImprovementPct', ...
    'CapturedImprovementPct','UniqueNetworksWithinRadius', ...
    'NewObjectiveEvaluations','CumulativeObjectiveEvaluations', ...
    'RuntimeSeconds'});

bestResult = refinementResults{lastIndex};
study = struct();
study.version = "discrete_radius_sensitivity_v1";
study.created = string(datetime("now"));
study.studySummaryFile = string(summaryFile);
study.startingNetworkSource = startingNetworkSource;
study.databaseFile = string(databaseFile);
study.objectiveMode = objectiveMode;
study.originalSensorIndices = originalIndices;
study.savedOriginalSensorIndices = savedOriginalIndices;
study.mappingDistancesKm = mappingDistancesKm;
study.mappingApplied = mappingApplied;
study.savedDatabaseVersion = savedDatabaseVersion;
study.currentDatabaseVersion = currentDatabaseVersion;
study.savedObjectiveNotCompared = savedObjective;
study.originalObjective = originalObjective;
study.radiiKm = radiiKm;
study.refinementResults = refinementResults;
study.summaryTable = summaryTable;
study.captureFraction = config.captureFraction;
study.radiusAtCaptureKm = radiusAtCaptureKm;
study.marginalThresholdPct = config.marginalThresholdPct;
study.tradeoffRadiusKm = tradeoffRadiusKm;
study.tradeoffProvisional = tradeoffProvisional;
study.largestCompletedRadiusKm = radiiKm(lastIndex);
study.maximumObservedImprovement = maximumObservedGain;
study.bestSensorIndices = bestResult.bestSensorIndices;
study.bestObjective = bestResult.bestObjective;
study.totalUniqueObjectiveEvaluations = double(sharedCache.Count);
study.configuration = rmfield(config, ...
    {'studyState','database','objectiveFcn'});
study.outputDirectory = "";
study.summaryCsvFile = "";
study.studyMatFile = "";
study.objectiveRadiusFigureFile = "";
study.objectiveFeFigureFile = "";
study.relativeRadiusFigureFile = "";
study.relativeSearchSpaceFigureFile = "";

%% Save independent post-processing products.
if config.saveResults || config.makePlots
    outputDirectory = string(config.outputDirectory);
    if strlength(outputDirectory) == 0
        timestamp = string(datetime("now","Format","yyyyMMdd_HHmmss_SSS"));
        outputDirectory = fullfile(projectRoot,"results", ...
            "local_refinement","radius_sensitivity_"+timestamp);
    elseif ~isfolder(outputDirectory)
        % Relative outputs are rooted at the repository for consistency.
        if ~isAbsolutePath(outputDirectory)
            outputDirectory = fullfile(projectRoot,outputDirectory);
        end
    end
    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    study.outputDirectory = outputDirectory;

    if config.makePlots
        objectiveRadiusFigureFile = fullfile( ...
            outputDirectory,"best_objective_vs_radius.png");
        objectiveFeFigureFile = fullfile( ...
            outputDirectory,"best_objective_vs_unique_fe.png");
        saveComparisonPlots(radiiKm,completed,originalObjective, ...
            bestObjectiveByRadius,cumulativeObjectiveEvaluations, ...
            objectiveMode,objectiveRadiusFigureFile,objectiveFeFigureFile);
        study.objectiveRadiusFigureFile = objectiveRadiusFigureFile;
        study.objectiveFeFigureFile = objectiveFeFigureFile;
        relativeRadiusFigureFile = fullfile( ...
            outputDirectory,"relative_improvement_vs_radius.png");
        relativeSpaceFigureFile = fullfile( ...
            outputDirectory,"relative_improvement_vs_search_space.png");
        saveRelativePlots(radiiKm,completed,combinationCounts, ...
            relativeImprovementPct,marginalRelativeImprovementPct, ...
            tradeoffRadiusKm,config.marginalThresholdPct, ...
            relativeRadiusFigureFile,relativeSpaceFigureFile);
        study.relativeRadiusFigureFile = relativeRadiusFigureFile;
        study.relativeSearchSpaceFigureFile = relativeSpaceFigureFile;
    end

    if config.saveResults
        summaryCsvFile = fullfile( ...
            outputDirectory,"radius_sensitivity_summary.csv");
        studyMatFile = fullfile( ...
            outputDirectory,"radius_sensitivity_study.mat");
        writetable(summaryTable,summaryCsvFile);
        study.summaryCsvFile = summaryCsvFile;
        study.studyMatFile = studyMatFile;
        save(studyMatFile,"study","-v7.3");
    end
end

fprintf("\nRadius sensitivity summary:\n");
disp(summaryTable);
fprintf("Best discrete objective: %.12g\n",study.bestObjective);
fprintf("Best positive score: %.12g\n",-study.bestObjective);
if isfinite(tradeoffRadiusKm)
    fprintf("Relative-gain elbow: %.2f km (threshold %.3g%%/step)\n", ...
        tradeoffRadiusKm,config.marginalThresholdPct);
    if tradeoffProvisional
        fprintf("NOTE: Elbow is provisional because some radii were skipped.\n");
    end
else
    fprintf("No relative-gain plateau identified at completed radii.\n");
end
fprintf("Total distinct objective evaluations: %.0f\n", ...
    study.totalUniqueObjectiveEvaluations);
if isfinite(radiusAtCaptureKm)
    fprintf("%.0f%% of observed improvement reached at %.2f km\n", ...
        100*config.captureFraction,radiusAtCaptureKm);
else
    fprintf("No objective improvement found at completed radii.\n");
end
if any(~completed)
    fprintf("WARNING: %d radius/radii skipped for combination limits.\n", ...
        nnz(~completed));
end
if strlength(study.outputDirectory) > 0
    fprintf("Results saved under: %s\n",study.outputDirectory);
end

    function value = cachedObjective(indices)
        key = sprintf('%d_',sort(double(indices(:))));
        if isKey(sharedCache,key)
            value = sharedCache(key);
            return
        end
        value = productionObjective(indices);
        assert(isnumeric(value) && isscalar(value) && ...
            isreal(value) && isfinite(value), ...
            "runDiscreteRadiusSensitivity:NonfiniteObjective", ...
            "The objective must return a finite real scalar.");
        value = double(value);
        sharedCache(key) = value;
    end
end

function summaryFile = findLatestStudySummary(projectRoot)
studyFiles = dir(fullfile( ...
    projectRoot,"results","optimization_runs","*","study_summary.mat"));
assert(~isempty(studyFiles), ...
    "runDiscreteRadiusSensitivity:NoStudies", ...
    "No study_summary.mat found beneath results/optimization_runs.");
[~,order] = sort([studyFiles.datenum],"descend");
studyFiles = studyFiles(order);
summaryFile = fullfile(studyFiles(1).folder,studyFiles(1).name);
end

function fileName = resolveRelativeFile(fileName,projectRoot)
if ~isAbsolutePath(fileName)
    % Keep paths already resolvable from MATLAB's current directory.
    if ~isfile(fileName)
        fileName = fullfile(projectRoot,fileName);
    end
end
end

function yes = isAbsolutePath(fileName)
fileName = char(fileName);
yes = startsWith(fileName,filesep) || ...
    ~isempty(regexp(fileName,'^[A-Za-z]:[\\/]','once')) || ...
    startsWith(fileName,'\\');
end

function saveRelativePlots(radii,completed,combinations, ...
    relativePct,marginalPct,tradeoffRadiusKm,thresholdPct, ...
    radiusFile,spaceFile)
% Benefits are relative to |J|, including for negative minimization J.
% The x-axis on the search-space plot uses raw Cartesian combinations.
f = figure("Visible","off","Color","w");
hold on;
plot(radii(completed),relativePct(completed),"-o", ...
    "LineWidth",1.5,"DisplayName","Cumulative relative improvement");
plot(radii(completed),marginalPct(completed),"-s", ...
    "LineWidth",1.5,"DisplayName","Marginal relative improvement");
yline(thresholdPct,"--","Threshold", ...
    "HandleVisibility","off");
if isfinite(tradeoffRadiusKm)
    xline(tradeoffRadiusKm,":","Elbow radius", ...
        "HandleVisibility","off");
end
xlabel("Search radius (km)");
ylabel("Relative improvement (%)");
title("Refinement relative improvement versus radius");
legend("Location","best");
grid on;
exportgraphics(f,radiusFile,"Resolution",200);
close(f);

f = figure("Visible","off","Color","w");
hold on;
good = completed & isfinite(combinations) & combinations > 0;
plot(combinations(good),relativePct(good),"-o", ...
    "LineWidth",1.5,"DisplayName","Cumulative relative improvement");
plot(combinations(good),marginalPct(good),"-s", ...
    "LineWidth",1.5,"DisplayName","Marginal relative improvement");
set(gca,"XScale","log");
yline(thresholdPct,"--","Threshold", ...
    "HandleVisibility","off");
xlabel("Raw Cartesian search-space combinations (log scale)");
ylabel("Relative improvement (%)");
title("Refinement returns versus discrete search-space size");
legend("Location","best");
grid on;
exportgraphics(f,spaceFile,"Resolution",200);
close(f);
end

function saveComparisonPlots(radii,completed,J0,bestJ,fe,mode, ...
    radiusFile,feFile)
xRadius = [0;radii(completed)];
y = [J0;bestJ(completed)];
xFe = [0;fe(completed)];

f = figure("Visible","off","Color","w");
plot(xRadius,y,"-o","LineWidth",1.5,"MarkerSize",5);
hold on;
yline(J0,"--","Original objective","LabelHorizontalAlignment","left");
xlabel("Discrete search radius (km)");
ylabel("Best objective J (minimized)");
title("Discrete radius sensitivity: "+mode);
exportgraphics(f,radiusFile,"Resolution",200);
close(f);

f = figure("Visible","off","Color","w");
plot(xFe,y,"-o","LineWidth",1.5,"MarkerSize",5);
hold on;
yline(J0,"--","Original objective","LabelHorizontalAlignment","left");
xlabel("Cumulative unique objective evaluations");
ylabel("Best objective J (minimized)");
title("Refinement quality versus computation: "+mode);
exportgraphics(f,feFile,"Resolution",200);
close(f);
end

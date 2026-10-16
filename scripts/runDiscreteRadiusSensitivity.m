function study = runDiscreteRadiusSensitivity(userConfig)
% RUNDISCRETERADIUSSENSITIVITY Radius sweep around ONE FIXED lunar network.
%
% This is POST-PROCESSING ONLY; no solver is rerun and the production
% database or original optimization study is never modified.
%
% Example (from repository root):
%   addpath("scripts");
%   cfg = struct();
%   cfg.studySummaryFile = ...
%       "results/optimization_runs/YOUR_STUDY_FOLDER/study_summary.mat";
%   cfg.radiiKm = [10 20 30 40 50 60];
%   cfg.maximumCombinations = 50000;
%   study = runDiscreteRadiusSensitivity(cfg);
%
% Omit studySummaryFile to use the latest study_summary.mat found beneath
% results/optimization_runs. Specify it for reproducible publications.
%
% Optional userConfig fields:
%   initialSensorIndices  - direct starting candidate IDs on CURRENT database
%                           (bypasses saved-study lookup when nonempty)
%   objectiveMode         - "information"/"coverage"; required for direct IDs
%   studySummaryFile      - saved study_summary.mat (default latest)
%                           do not combine with initialSensorIndices
%   databaseFile          - database MAT (default study config or results)
%   radiiKm               - increasing radii in km (default [10 20 30 40 50 60])
%   maximumCombinations   - raw Cartesian limit per radius (default 50000)
%   skipOversized         - skip limit-exceeding radii (default true)
%   improvementTolerance  - absolute J tolerance (default 1e-10)
%   captureFraction       - fraction of largest OBSERVED gain (default .95)
%   outputDirectory       - directory for CSV/MAT/figures (default timestamped)
%   saveResults           - write MAT and CSV (default true)
%   makePlots             - write objective/radius and objective/FE PNGs
%                           (default true; requires graphics)
%
% Testing/development ONLY:
%   studyState, database  - preloaded structs (avoid MAT-file dependency)
%   objectiveFcn          - @(sortedCandidateIndices) scalar J override
%
% IMPORTANT: The measured 'r95' is relative to the largest COMPLETED
% radius, not a certificate of global or continuous optimality. Oversized
% radii are marked as skipped and are not used for that reference.
%
% The same original sensor indices anchor ALL radii. A shared Map caches
% objectives of canonical sorted networks across different radius runs:
% cumulative FE counts REAL calls to the objective, not repeat cache hits.
%
% Data files under results/ are ignored by Git.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory = fileparts(mfilename("fullpath"));
projectRoot = fileparts(scriptDirectory);
addpath(fullfile(projectRoot,"src"));

config = struct();
config.studySummaryFile = "";
config.databaseFile = "";
config.initialSensorIndices = [];
config.objectiveMode = "";
config.radiiKm = [10 20 30 40 50 60];
config.maximumCombinations = 50000;
config.skipOversized = true;
config.improvementTolerance = 1e-10;
config.captureFraction = 0.95;
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
validateattributes(config.maximumCombinations,{'numeric'}, ...
    {'scalar','integer','positive','finite'});
validateattributes(config.improvementTolerance,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(config.captureFraction,{'numeric'}, ...
    {'scalar','real','finite','>',0,'<=',1});
assert(islogical(config.skipOversized) && isscalar(config.skipOversized));
assert(islogical(config.saveResults) && isscalar(config.saveResults));
assert(islogical(config.makePlots) && isscalar(config.makePlots));

%% Determine the fixed starting network (no global optimizer rerun).
% A direct index vector lets this radius sweep use EXACTLY the same
% current-database starting point as refineDiscreteNetwork. This avoids
% accidentally selecting a historical study for a different database.
summaryFile = "";
if ~isempty(config.initialSensorIndices)
    assert(strlength(string(config.studySummaryFile)) == 0 && ...
        isempty(fieldnames(config.studyState)), ...
        "runDiscreteRadiusSensitivity:AmbiguousNetworkSource", ...
        ["Specify either initialSensorIndices/objectiveMode or a saved " ...
         "study, not both."]);
    validateattributes(config.initialSensorIndices,{'numeric'}, ...
        {'vector','nonempty','real','finite','integer','positive'});
    requestedMode = lower(string(config.objectiveMode));
    assert(isscalar(requestedMode) && ...
        ismember(requestedMode,["coverage","information"]), ...
        "runDiscreteRadiusSensitivity:DirectModeRequired", ...
        ["With initialSensorIndices, set config.objectiveMode to " ...
         """coverage"" or ""information""."]);
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

if ~isempty(fieldnames(config.database))
    database = config.database;
    databaseFile = "";
else
    % An explicitly selected database must NEVER silently fall back to
    % another file. A saved old path may be stale after moving projects;
    % in that case try the conventional local path but verify provenance.
    requestedFile = string(config.databaseFile);
    if strlength(requestedFile) > 0
        databaseFile = resolveRelativeFile(requestedFile,projectRoot);
    else
        savedFile = "";
        if isfield(studyState.config,"databaseFile")
            savedFile = string(studyState.config.databaseFile);
        end
        if strlength(savedFile) > 0 && ...
                isfile(resolveRelativeFile(savedFile,projectRoot))
            databaseFile = resolveRelativeFile(savedFile,projectRoot);
        else
            databaseFile = fullfile( ...
                projectRoot,"results","optimization_database.mat");
        end
    end
    assert(isfile(databaseFile), ...
        "runDiscreteRadiusSensitivity:DatabaseNotFound", ...
        ["Optimization database not found: %s\n" ...
         "Supply config.databaseFile with the matching MAT-file path."], ...
        databaseFile);
    S = load(databaseFile,"database");
    assert(isfield(S,"database"), ...
        "runDiscreteRadiusSensitivity:InvalidDatabase", ...
        "Database MAT file does not contain database.");
    database = S.database;
end

% The study's candidate indices refer to a PARTICULAR database. A
% different DB must not be mistaken for a local improvement of that study.
if isfield(studyState,"runStates") && ...
        isfield(studyState,"overallBestRunIndex") && ...
        ~isempty(studyState.runStates)
    bestRun = studyState.runStates{studyState.overallBestRunIndex};
    if isfield(bestRun,"databaseVersion") && ...
            isfield(database,"meta") && isfield(database.meta,"version")
        savedVersion = string(bestRun.databaseVersion);
        loadedVersion = string(database.meta.version);
        if ~isequal(savedVersion,loadedVersion)
            originalDatabaseFile = "<not recorded>";
            if isfield(bestRun,"databaseFile")
                originalDatabaseFile = string(bestRun.databaseFile);
            end
            error("runDiscreteRadiusSensitivity:DatabaseVersionMismatch", ...
                ['The saved optimization study and loaded database ' ...
                 'are not compatible.\n' ...
                 'Study database version: %s\n' ...
                 'Loaded database version: %s\n' ...
                 'Study database path:    %s\n' ...
                 'Loaded database path:   %s\n' ...
                 'Select the original matching database with ' ...
                 'config.databaseFile, or rerun the global optimizer ' ...
                 'using the currently loaded database. ' ...
                 'Do not bypass this check to compare objective values.'], ...
                savedVersion,loadedVersion,originalDatabaseFile, ...
                string(databaseFile));
        end
    end

    % The same version string can appear on databases with different
    % candidate-site grids. Check the actual stored winning coordinates.
    if isfield(bestRun,"bestSensorLatitudesRad") && ...
            isfield(bestRun,"bestSensorLongitudesRad")
        assert(all(originalIndices >= 1) && ...
            all(originalIndices <= numel(database.candidates.latitudesRad)), ...
            "runDiscreteRadiusSensitivity:CandidateGridMismatch", ...
            "Winning sensor indices are outside the loaded candidate set.");
        currentLatitude = double( ...
            database.candidates.latitudesRad(originalIndices));
        currentLongitude = double( ...
            database.candidates.longitudesRad(originalIndices));
        savedLatitude = double(bestRun.bestSensorLatitudesRad(:));
        savedLongitude = double(bestRun.bestSensorLongitudesRad(:));
        deltaLongitude = atan2( ...
            sin(currentLongitude(:)-savedLongitude), ...
            cos(currentLongitude(:)-savedLongitude));
        assert(numel(savedLatitude) == numel(originalIndices) && ...
            numel(savedLongitude) == numel(originalIndices) && ...
            all(abs(currentLatitude(:)-savedLatitude) < 1e-10) && ...
            all(abs(deltaLongitude) < 1e-10), ...
            "runDiscreteRadiusSensitivity:CandidateGridMismatch", ...
            ["The loaded database has different candidate coordinates " ...
             "at the saved best sensor indices. Select the original " ...
             "optimization database."]);
    end
end

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
    ["No radius completed. Reduce the radii or raise " ...
     "maximumCombinations explicitly."]);
completedIndices = find(completed);
lastIndex = completedIndices(end);

%% Improvement, marginal gain, and r95 (empirical, largest completed r).

gain = NaN(numberOfRadii,1);
marginalGain = NaN(numberOfRadii,1);
capturedPct = NaN(numberOfRadii,1);
previousBest = originalObjective;
for k = completedIndices(:).'
    gain(k) = originalObjective-bestObjectiveByRadius(k);
    marginalGain(k) = previousBest-bestObjectiveByRadius(k);
    previousBest = bestObjectiveByRadius(k);
end

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
    radiiKm,status,combinationCounts,bestObjectiveByRadius, ...
    gain,marginalGain,capturedPct,independentNetworkCounts, ...
    newObjectiveEvaluations,cumulativeObjectiveEvaluations, ...
    runTimesSeconds, ...
    'VariableNames',{'RadiusKm','Status','CartesianCombinations', ...
    'BestJ','Improvement','MarginalImprovement', ...
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
study.originalObjective = originalObjective;
study.radiiKm = radiiKm;
study.refinementResults = refinementResults;
study.summaryTable = summaryTable;
study.captureFraction = config.captureFraction;
study.radiusAtCaptureKm = radiusAtCaptureKm;
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

function analysis = analyzeSavedDiscreteRadiusStudy(userConfig)
% ANALYZESAVEDDISCRETERADIUSSTUDY - Post-process existing radius-sweep results.
%
% Inputs:
%   - userConfig - Saved radius study, matching database, and output settings.
%
% Outputs:
%   - analysis - Gain-per-FE and sensor-displacement tables.
%
% Notes:
%   - Post-processing reads saved results without evaluating the objective.

arguments
    userConfig (1,1) struct = struct()
end

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = struct();
config.studyMatFile = "";
config.databaseFile = "";
config.outputDirectory = "";
config.saveResults = true;
config.makePlots = true;
config.boundaryFraction = 0.90;
config.study = struct();
config.database = struct();
inputNames = fieldnames(userConfig);
for i = 1:numel(inputNames)
    field = inputNames{i};
    assert(isfield(config,field), ...
        "analyzeSavedDiscreteRadiusStudy:UnknownOption", ...
        "Unknown option: %s",field);
    config.(field) = userConfig.(field);
end
validateattributes(config.boundaryFraction,{'numeric'}, ...
    {'scalar','real','finite','>=',0,'<=',1});
assert(islogical(config.saveResults) && isscalar(config.saveResults));
assert(islogical(config.makePlots) && isscalar(config.makePlots));

studyFile = string(config.studyMatFile);
if ~isempty(fieldnames(config.study))
    study = config.study;
    if strlength(studyFile) > 0
        studyFile = resolveStudyFile(studyFile,root);
    end
else
    if strlength(studyFile) == 0
        hits = dir(fullfile(root,"results","local_refinement", ...
            "radius_sensitivity_*","radius_sensitivity_study.mat"));
        assert(~isempty(hits), ...
            "analyzeSavedDiscreteRadiusStudy:StudyNotFound", ...
            "No saved radius sensitivity MAT files were found.");
        [~,newest] = max([hits.datenum]);
        studyFile = fullfile(hits(newest).folder,hits(newest).name);
    else
        studyFile = resolveStudyFile(studyFile,root);
    end
    assert(isfile(studyFile), ...
        "analyzeSavedDiscreteRadiusStudy:StudyNotFound", ...
        "Saved radius study not found: %s",studyFile);
    loaded = load(studyFile,"study");
    assert(isfield(loaded,"study"), ...
        "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
        "The MAT file does not contain a study struct.");
    study = loaded.study;
end
assert(isfield(study,"summaryTable") && istable(study.summaryTable) && ...
    isfield(study,"refinementResults") && ...
    isfield(study,"originalSensorIndices") && ...
    isfield(study,"originalObjective"), ...
    "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
    "Saved study lacks the radius table, results, or starting network.");

databaseFile = string(config.databaseFile);
if ~isempty(fieldnames(config.database))
    database = config.database;
elseif strlength(databaseFile) == 0
    % Explicit default is the current canonical database. Verify saved
    % winning coordinates before using its candidate index mappings.
    databaseFile = fullfile(root,"results","optimization_database.mat");
    assert(isfile(databaseFile), ...
        "analyzeSavedDiscreteRadiusStudy:DatabaseNotFound", ...
        "Optimization database not found: %s",databaseFile);
    D = load(databaseFile,"database");
    assert(isfield(D,"database"), ...
        "analyzeSavedDiscreteRadiusStudy:InvalidDatabase", ...
        "Database MAT file must contain database.");
    database = D.database;
else
    databaseFile = resolveStudyFile(databaseFile,root);
    assert(isfile(databaseFile), ...
        "analyzeSavedDiscreteRadiusStudy:DatabaseNotFound", ...
        "Optimization database not found: %s",databaseFile);
    D = load(databaseFile,"database");
    assert(isfield(D,"database"), ...
        "analyzeSavedDiscreteRadiusStudy:InvalidDatabase", ...
        "Database MAT file must contain database.");
    database = D.database;
end

assert(isfield(database,"candidates") && ...
    isfield(database.candidates,"latitudesRad") && ...
    isfield(database.candidates,"longitudesRad") && ...
    isfield(database,"config") && isfield(database.config,"moon") && ...
    isfield(database.config.moon,"radiusKm"), ...
    "analyzeSavedDiscreteRadiusStudy:InvalidDatabase", ...
    "Database candidate coordinates or Moon radius unavailable.");
lat = double(database.candidates.latitudesRad(:));
lon = double(database.candidates.longitudesRad(:));
R = double(database.config.moon.radiusKm);
assert(numel(lat) == numel(lon) && isfinite(R) && R > 0 && ...
    all(isfinite(lat)) && all(isfinite(lon)), ...
    "analyzeSavedDiscreteRadiusStudy:InvalidDatabase", ...
    "Candidate arrays or lunar radius invalid.");

T = study.summaryTable;
neededColumns = ["RadiusKm","Status","BestJ", ...
    "NewObjectiveEvaluations","CumulativeObjectiveEvaluations", ...
    "CartesianCombinations"];
assert(all(ismember(neededColumns,string(T.Properties.VariableNames))), ...
    "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
    "Summary table lacks required columns.");
radii = double(T.RadiusKm(:));
completed = string(T.Status(:)) == "completed";
assert(numel(study.refinementResults) == height(T), ...
    "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
    "Radius rows and saved refinementResults have different lengths.");
originalIds = double(study.originalSensorIndices(:));
nSensor = numel(originalIds);
assert(all(originalIds >= 1 & originalIds <= numel(lat)) && ...
    numel(unique(originalIds)) == nSensor, ...
    "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
    "Original candidate IDs are invalid for this database.");

nRadii = numel(radii);
maxMove = NaN(nRadii,1);
meanMove = NaN(nRadii,1);
maxFraction = NaN(nRadii,1);
nearBoundary = NaN(nRadii,1);
allRows = cell(nRadii,1);

for k = 1:nRadii
    if ~completed(k)
        continue
    end
    result = study.refinementResults{k};
    assert(isstruct(result) && isfield(result,"bestSensorIndices"), ...
        "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
        "Completed radius %.4g km lacks best indices.",radii(k));
    ids = double(result.bestSensorIndices(:));
    assert(numel(ids)==nSensor && all(ids >= 1 & ids <= numel(lat)) && ...
        numel(unique(ids)) == nSensor, ...
        "analyzeSavedDiscreteRadiusStudy:InvalidStudy", ...
        "Radius %.4g km has invalid winner indices.",radii(k));
    if isfield(result,"initialSensorIndices")
        assert(isequal(sort(double(result.initialSensorIndices(:))), ...
            sort(originalIds)), ...
            "analyzeSavedDiscreteRadiusStudy:InconsistentStart", ...
            "Radius %.4g km used a different starting network.",radii(k));
    end

    % Guard against silently interpreting saved indices on a new grid.
    if isfield(result,"bestLatitudesRad") && ...
            isfield(result,"bestLongitudesRad")
        storedLat = double(result.bestLatitudesRad(:));
        storedLon = double(result.bestLongitudesRad(:));
        longitudeError = atan2(sin(lon(ids)-storedLon), ...
            cos(lon(ids)-storedLon));
        assert(numel(storedLat)==nSensor && ...
            numel(storedLon)==nSensor && ...
            all(abs(lat(ids)-storedLat)<1e-8) && ...
            all(abs(longitudeError)<1e-8), ...
            "analyzeSavedDiscreteRadiusStudy:CandidateGridChanged", ...
            ['The candidate coordinates differ from the saved winners. ' ...
             'Analyze with the database used for the original sweep; ' ...
             'do not re-evaluate or rerun optimization.']);
    end

    % Rows: original sensors; columns: best candidate sites.
    deltaLat = lat(ids).'-lat(originalIds);
    deltaLon = lon(ids).'-lon(originalIds);
    h = sin(deltaLat/2).^2 + ...
        cos(lat(originalIds)).*cos(lat(ids).').*sin(deltaLon/2).^2;
    distances = 2*R*asin(sqrt(min(1,max(0,h))));
    allowed = distances <= radii(k)+1e-7;
    if isfield(result,"neighborhoodIndices") && ...
            numel(result.neighborhoodIndices)==nSensor
        for sensor = 1:nSensor
            allowed(sensor,:) = allowed(sensor,:) & ...
                ismember(ids(:).', ...
                double(result.neighborhoodIndices{sensor}(:).'));
        end
    end

    assignment = matchLocations(distances,allowed);
    d = distances(sub2ind(size(distances),(1:nSensor).',assignment));
    movedIds = ids(assignment);
    maxMove(k) = max(d);
    meanMove(k) = mean(d);
    if radii(k) > 0
        fractions = d/radii(k);
    else
        fractions = zeros(nSensor,1);
    end
    maxFraction(k) = max(fractions);
    nearBoundary(k) = nnz(fractions >= config.boundaryFraction & d > 0);

    allRows{k} = table( ...
        repmat(radii(k),nSensor,1),(1:nSensor).', ...
        originalIds,movedIds,d,fractions, ...
        rad2deg(lat(originalIds)),mod(rad2deg(lon(originalIds)),360), ...
        rad2deg(lat(movedIds)),mod(rad2deg(lon(movedIds)),360), ...
        'VariableNames',{'RadiusKm','OriginalSensorNumber', ...
        'InitialCandidateIndex','RefinedCandidateIndex', ...
        'DisplacementKm','FractionOfSearchRadius', ...
        'InitialLatitudeDeg','InitialLongitudeDeg', ...
        'RefinedLatitudeDeg','RefinedLongitudeDeg'});
end

nonempty = ~cellfun(@isempty,allRows);
if any(nonempty)
    sensorDisplacementTable = vertcat(allRows{nonempty});
else
    sensorDisplacementTable = table();
end

% Marginal benefit: percentage-points of J reduction compared with the
% preceding COMPLETED radius. Denominator is |previous best J|.
marginalPct = NaN(nRadii,1);
cumulativePct = NaN(nRadii,1);
previousJ = double(study.originalObjective);
for k = find(completed(:)).'
    currentJ = double(T.BestJ(k));
    if abs(previousJ)>eps
        marginalPct(k) = 100*(previousJ-currentJ)/abs(previousJ);
    elseif abs(previousJ-currentJ)<=eps
        marginalPct(k) = 0;
    end
    if abs(study.originalObjective)>eps
        cumulativePct(k) = ...
            100*(study.originalObjective-currentJ)/abs(study.originalObjective);
    elseif abs(study.originalObjective-currentJ)<=eps
        cumulativePct(k) = 0;
    end
    previousJ = currentJ;
end

newFe = double(T.NewObjectiveEvaluations(:));
cumFe = double(T.CumulativeObjectiveEvaluations(:));
combinations = double(T.CartesianCombinations(:));
etaPer1000Fe = NaN(nRadii,1);
etaCumulative = NaN(nRadii,1);
etaPer1000Combinations = NaN(nRadii,1);
prevSpace = 0;
for k = find(completed(:)).'
    if newFe(k)>0
        etaPer1000Fe(k) = 1000*marginalPct(k)/newFe(k);
    end
    if cumFe(k)>1
        etaCumulative(k) = ...
            1000*cumulativePct(k)/(cumFe(k)-1);
    end
    expandedSpace = combinations(k)-prevSpace;
    if expandedSpace>0
        etaPer1000Combinations(k) = ...
            1000*marginalPct(k)/expandedSpace;
    end
    prevSpace = combinations(k);
end

T.MarginalRelativeImprovementPct = marginalPct;
T.RelativeImprovementPct = cumulativePct;
T.EtaPctPointsPer1000NewFE = etaPer1000Fe;
T.CumulativeEfficiencyPctPointsPer1000FE = etaCumulative;
T.EtaPctPointsPer1000NewCombinations = etaPer1000Combinations;
T.MaxSensorDisplacementKm = maxMove;
T.MeanSensorDisplacementKm = meanMove;
T.MaxDisplacementFractionOfRadius = maxFraction;
T.SensorsAt90PctRadius = nearBoundary;
analysis = struct();
analysis.sourceStudyFile = studyFile;
analysis.databaseFile = databaseFile;
analysis.created = string(datetime("now"));
analysis.summaryTable = T;
analysis.sensorDisplacementTable = sensorDisplacementTable;
analysis.boundaryFraction = config.boundaryFraction;
analysis.originalSensorIndices = originalIds;
analysis.etaUnit = "percentage points per 1000 NEW uncached FEs";
analysis.outputDirectory = "";
analysis.summaryCsvFile = "";
analysis.displacementCsvFile = "";
analysis.analysisMatFile = "";
analysis.efficiencyFigureFile = "";
analysis.efficiencyVsFeFigureFile = "";
analysis.displacementFigureFile = "";

if config.saveResults || config.makePlots
    outputDir = string(config.outputDirectory);
    if strlength(outputDir)==0
        if strlength(studyFile)>0
            outputDir = string(fileparts(studyFile));
        else
            outputDir = fullfile(root,"results","local_refinement", ...
                "radius_postprocessing_"+string(datetime( ...
                "now","Format","yyyyMMdd_HHmmss_SSS")));
        end
    elseif ~isAbsolutePath(outputDir)
        outputDir = fullfile(root,outputDir);
    end
    if ~isfolder(outputDir), mkdir(outputDir); end
    analysis.outputDirectory = outputDir;
    if config.makePlots
        analysis.efficiencyFigureFile = fullfile( ...
            outputDir,"marginal_efficiency_vs_radius.png");
        analysis.efficiencyVsFeFigureFile = fullfile( ...
            outputDir,"relative_improvement_vs_cumulative_fe.png");
        analysis.displacementFigureFile = fullfile( ...
            outputDir,"sensor_displacements_vs_radius.png");
        saveFigures(T,sensorDisplacementTable,originalIds, ...
            analysis.efficiencyFigureFile, ...
            analysis.efficiencyVsFeFigureFile, ...
            analysis.displacementFigureFile);
    end
    if config.saveResults
        analysis.summaryCsvFile = fullfile( ...
            outputDir,"radius_sensitivity_efficiency_summary.csv");
        analysis.displacementCsvFile = fullfile( ...
            outputDir,"radius_sensitivity_sensor_displacements.csv");
        analysis.analysisMatFile = fullfile( ...
            outputDir,"radius_sensitivity_postprocessing.mat");
        writetable(T,analysis.summaryCsvFile);
        writetable(sensorDisplacementTable,analysis.displacementCsvFile);
        save(analysis.analysisMatFile,"analysis");
    end
end

fprintf("\nSaved radius sensitivity post-processing (no objective FEs):\n");
disp(T(:,{'RadiusKm','BestJ','RelativeImprovementPct', ...
    'EtaPctPointsPer1000NewFE','MaxSensorDisplacementKm', ...
    'SensorsAt90PctRadius'}));
if strlength(analysis.outputDirectory)>0
    fprintf("Post-processing outputs: %s\n",analysis.outputDirectory);
end
end

function assignment = matchLocations(distances,allowed)
% Find the minimum-total-displacement feasible matching. This avoids
% mistaking sorted network IDs for persistent observer identities.
n = size(distances,1);
assert(size(distances,2)==n && all(any(allowed,2)) && ...
    all(any(allowed,1)), ...
    "analyzeSavedDiscreteRadiusStudy:NoFeasibleAssignment", ...
    "No feasible one-to-one sensor correspondence exists.");
assignment = zeros(n,1);
current = zeros(n,1);
used = false(n,1);
bestCost = Inf;
search(1,0);
assert(isfinite(bestCost), ...
    "analyzeSavedDiscreteRadiusStudy:NoFeasibleAssignment", ...
    "Saved winner cannot be matched to original sensor neighborhoods.");
    function search(s,cost)
        if s>n
            if cost<bestCost
                bestCost=cost;
                assignment=current;
            end
            return
        end
        options = find(allowed(s,:) & ~used.');
        for j=options
            newCost=cost+distances(s,j);
            if newCost>=bestCost, continue; end
            used(j)=true;
            current(s)=j;
            search(s+1,newCost);
            used(j)=false;
        end
    end
end

function saveFigures(T,movement,originalIds,etaFile,improvementFile,moveFile)
completed = string(T.Status)=="completed";
f = figure("Visible","off","Color","w");
plot(T.RadiusKm(completed),T.EtaPctPointsPer1000NewFE(completed), ...
    "-o","LineWidth",1.5);
xlabel("Search radius (km)");
ylabel("Marginal improvement (percentage points / 1000 new FE)");
title("Marginal computational efficiency by radius");
grid on;
exportgraphics(f,etaFile,"Resolution",200);
close(f);

f = figure("Visible","off","Color","w");
plot(T.CumulativeObjectiveEvaluations(completed), ...
    T.RelativeImprovementPct(completed),"-o","LineWidth",1.5);
xlabel("Cumulative unique objective evaluations");
ylabel("Total relative objective improvement (%)");
title("Refinement gain versus evaluation cost");
grid on;
exportgraphics(f,improvementFile,"Resolution",200);
close(f);

f = figure("Visible","off","Color","w");
hold on;
for s=1:numel(originalIds)
    mask = movement.OriginalSensorNumber==s;
    plot(movement.RadiusKm(mask),movement.DisplacementKm(mask), ...
        "-o","LineWidth",1.5, ...
        "DisplayName",sprintf("Sensor %d",s));
end
plot(T.RadiusKm(completed),T.RadiusKm(completed), ...
    "k--","LineWidth",1, ...
    "DisplayName","Search-radius boundary");
xlabel("Search radius (km)");
ylabel("Distance from original sensor (km)");
title("Winning sensor displacements");
legend("Location","best");
grid on;
exportgraphics(f,moveFile,"Resolution",200);
close(f);
end

function path = resolveStudyFile(path,root)
if ~isAbsolutePath(path) && ~isfile(path)
    path=fullfile(root,path);
end
end

function yes = isAbsolutePath(path)
path=char(path);
yes=startsWith(path,filesep) || ...
    ~isempty(regexp(path,'^[A-Za-z]:[\\/]','once')) || ...
    startsWith(path,'\\');
end

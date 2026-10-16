function result = refineDiscreteNetwork( ...
    initialSensorIndices,database,objectiveMode,radiusKm,userConfig)
% REFINEDISCRETENETWORK Exhaustively refine a lunar candidate-site network.
%
% result = optimization.refineDiscreteNetwork( ...
%     initialSensorIndices,database,objectiveMode,radiusKm)
% result = optimization.refineDiscreteNetwork(...,userConfig)
%
% This is POST-PROCESSING: it does not modify the global optimizer, its
% database, its FE history, or its saved study. Each observer may occupy any
% retained candidate site within radiusKm of THAT observer's original site.
% All Cartesian combinations are tested, rejecting duplicate sensor IDs.
% Overlapping neighborhoods may generate the same sorted network more than
% once; each unique network is evaluated only once.
%
% The search is exhaustive WITHIN THESE FIXED GEOGRAPHIC NEIGHBORHOODS,
% not over the global candidate set or arbitrary off-grid coordinates.
% The input (unrefined) network is always feasible and is never worsened.
%
% Inputs
%   initialSensorIndices : vector of distinct, 1-based candidate IDs
%   database             : production optimization database
%   objectiveMode        : "coverage" or "information"
%   radiusKm             : max great-circle distance from each original
%                          observer location, in kilometers
%   userConfig (optional):
%       maximumCombinations  (default 10000): bound on *raw* Cartesian
%                            combinations before expensive FE begins
%       improvementTolerance (default 1e-10): absolute J improvement
%       objectiveFcn (default []): optional @(indices) objective for tests;
%                                 normally uses optimization.networkObjective
%
% Outputs include bestSensorIndices, bestObjective, initialObjective,
% improvement, neighborhoodIndices, numberOfObjectiveEvaluations, and
% counts of valid/duplicate/repeated combinations. Reported FE includes
% the initial-network evaluation and is separate from global-optimizer FE.
%
% Example (after loading a saved studyState and its matching database):
%   indices = studyState.overallBestSensorIndices;
%   result = optimization.refineDiscreteNetwork( ...
%       indices,database,string(studyState.config.objectiveMode),10);

arguments
    initialSensorIndices double
    database (1,1) struct
    objectiveMode (1,1) string
    radiusKm (1,1) double {mustBeFinite,mustBeNonnegative}
    userConfig (1,1) struct = struct()
end

timer = tic;
objectiveMode = lower(objectiveMode);
assert(ismember(objectiveMode,["coverage","information"]), ...
    "refineDiscreteNetwork:InvalidMode", ...
    "objectiveMode must be coverage or information.");

validateattributes(initialSensorIndices,{'double'}, ...
    {'vector','nonempty','real','finite','integer','positive'});
initialIndices = sort(initialSensorIndices(:));
numberOfSensors = numel(initialIndices);
assert(numel(unique(initialIndices)) == numberOfSensors, ...
    "refineDiscreteNetwork:DuplicateInitialSites", ...
    "The initial network must contain distinct candidate indices.");

assert(isfield(database,"candidates") && ...
    isfield(database.candidates,"latitudesRad") && ...
    isfield(database.candidates,"longitudesRad") && ...
    isfield(database,"config") && isfield(database.config,"moon") && ...
    isfield(database.config.moon,"radiusKm"), ...
    "refineDiscreteNetwork:InvalidDatabase", ...
    "Database is missing candidate coordinates or Moon radius.");
latitudes = double(database.candidates.latitudesRad(:));
longitudes = double(database.candidates.longitudesRad(:));
numberOfCandidates = numel(latitudes);
assert(numberOfCandidates > 0 && ...
    numel(longitudes) == numberOfCandidates && ...
    all(isfinite(latitudes)) && all(isfinite(longitudes)) && ...
    all(abs(latitudes) <= pi/2+1e-12), ...
    "refineDiscreteNetwork:InvalidDatabase", ...
    "Candidate latitude/longitude arrays are invalid.");
assert(all(initialIndices <= numberOfCandidates), ...
    "refineDiscreteNetwork:InvalidInitialSite", ...
    "An initial candidate index is outside the retained candidate set.");
if isfield(database,"meta") && ...
        isfield(database.meta,"numberOfCandidates")
    assert(database.meta.numberOfCandidates == numberOfCandidates, ...
        "refineDiscreteNetwork:InvalidDatabase", ...
        "Candidate array size differs from database.meta.numberOfCandidates.");
end
moonRadiusKm = double(database.config.moon.radiusKm);
validateattributes(moonRadiusKm,{'double'}, ...
    {'scalar','real','finite','positive'});

maximumCombinations = 10000;
improvementTolerance = 1e-10;
objectiveFcn = [];
if isfield(userConfig,"maximumCombinations")
    maximumCombinations = userConfig.maximumCombinations;
end
if isfield(userConfig,"improvementTolerance")
    improvementTolerance = userConfig.improvementTolerance;
end
if isfield(userConfig,"objectiveFcn")
    objectiveFcn = userConfig.objectiveFcn;
end
validateattributes(maximumCombinations,{'numeric'}, ...
    {'scalar','integer','positive','finite'});
validateattributes(improvementTolerance,{'numeric'}, ...
    {'scalar','real','nonnegative','finite'});
if isempty(objectiveFcn)
    objectiveFcn = @(indices) optimization.networkObjective( ...
        indices,database,objectiveMode);
else
    assert(isa(objectiveFcn,"function_handle"), ...
        "refineDiscreteNetwork:InvalidObjectiveFcn", ...
        "userConfig.objectiveFcn must be a function handle.");
end

% Haversine distances remain numerically stable for nearby locations and
% automatically wrap across 0/360-degree longitude and handle the poles.
neighborIndices = cell(numberOfSensors,1);
neighborhoodSizes = zeros(numberOfSensors,1);
for sensor = 1:numberOfSensors
    center = initialIndices(sensor);
    dLat = latitudes-latitudes(center);
    dLon = longitudes-longitudes(center);
    haversine = sin(dLat/2).^2 + ...
        cos(latitudes(center)).*cos(latitudes).*sin(dLon/2).^2;
    greatCircleDistancesKm = 2*moonRadiusKm*asin( ...
        sqrt(min(1,max(0,haversine))));

    % Include the original candidate even with floating-point roundoff.
    distanceToleranceKm = max(1e-9, ...
        32*eps(max(1,radiusKm)));
    near = find(greatCircleDistancesKm <= radiusKm+distanceToleranceKm);
    neighborIndices{sensor} = union(near,center,'sorted');
    neighborhoodSizes(sensor) = numel(neighborIndices{sensor});
end

numberOfCombinations = prod(double(neighborhoodSizes));
assert(isfinite(numberOfCombinations) && ...
    numberOfCombinations <= maximumCombinations, ...
    "refineDiscreteNetwork:TooManyCombinations", ...
    ['The %.0f neighborhood combinations exceed the limit of %.0f. ' ...
     'Reduce radiusKm or explicitly increase maximumCombinations.'], ...
    numberOfCombinations,maximumCombinations);

% Cache canonical (sorted) networks. Each distinct network is counted as
% one function evaluation regardless of neighborhood overlap/permutations.
objectiveCache = containers.Map('KeyType','char','ValueType','double');
initialObjective = evaluateObjective(initialIndices);
objectiveCache(networkKey(initialIndices)) = initialObjective;
numberOfObjectiveEvaluations = 1;
numberOfValidCombinations = 0;
numberOfDuplicateCombinations = 0;
numberOfRepeatedNetworks = 0;
bestObjective = initialObjective;
bestSensorIndices = initialIndices;
workingIndices = zeros(numberOfSensors,1);

enumerate(1);

result = struct();
result.version = "discrete_local_refinement_v1";
result.objectiveMode = objectiveMode;
result.radiusKm = radiusKm;
result.initialSensorIndices = initialIndices;
result.initialObjective = initialObjective;
result.bestSensorIndices = bestSensorIndices;
result.bestLatitudesRad = latitudes(bestSensorIndices);
result.bestLongitudesRad = mod(longitudes(bestSensorIndices),2*pi);
result.bestObjective = bestObjective;
result.improvement = initialObjective-bestObjective;
result.improved = bestObjective < initialObjective-improvementTolerance;
result.neighborhoodIndices = neighborIndices;
result.neighborhoodSizes = neighborhoodSizes;
result.numberOfCombinations = numberOfCombinations;
result.numberOfValidCombinations = numberOfValidCombinations;
result.numberOfDuplicateCombinations = numberOfDuplicateCombinations;
result.numberOfRepeatedNetworks = numberOfRepeatedNetworks;
result.numberOfUniqueNetworks = double(objectiveCache.Count);
result.numberOfObjectiveEvaluations = numberOfObjectiveEvaluations;
result.improvementTolerance = improvementTolerance;
result.elapsedSeconds = toc(timer);
result.exhaustiveWithinOriginalNeighborhoods = true;

    function enumerate(sensor)
        if sensor > numberOfSensors
            candidateIndices = sort(workingIndices);
            if any(diff(candidateIndices) == 0)
                numberOfDuplicateCombinations = ...
                    numberOfDuplicateCombinations+1;
                return
            end
            numberOfValidCombinations = numberOfValidCombinations+1;
            key = networkKey(candidateIndices);
            if isKey(objectiveCache,key)
                numberOfRepeatedNetworks = numberOfRepeatedNetworks+1;
                candidateObjective = objectiveCache(key);
            else
                candidateObjective = evaluateObjective(candidateIndices);
                objectiveCache(key) = candidateObjective;
                numberOfObjectiveEvaluations = ...
                    numberOfObjectiveEvaluations+1;
            end
            if candidateObjective < bestObjective-improvementTolerance
                bestObjective = candidateObjective;
                bestSensorIndices = candidateIndices;
            end
            return
        end

        possibleSites = neighborIndices{sensor};
        for index = 1:numel(possibleSites)
            workingIndices(sensor) = possibleSites(index);
            enumerate(sensor+1);
        end
    end

    function value = evaluateObjective(indices)
        value = objectiveFcn(indices);
        assert(isnumeric(value) && isscalar(value) && ...
            isreal(value) && isfinite(value), ...
            "refineDiscreteNetwork:InvalidObjectiveValue", ...
            "Objective must return one finite real scalar.");
        value = double(value);
    end
end

function key = networkKey(sensorIndices)
key = sprintf('%d_',sensorIndices);
end

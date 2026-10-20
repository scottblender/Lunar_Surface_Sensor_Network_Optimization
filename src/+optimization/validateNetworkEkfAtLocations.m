function validation = validateNetworkEkfAtLocations( ...
    database,sensorLatitudesRad,sensorLongitudesRad, ...
    filteredAvailability,userConfig)
% VALIDATENETWORKEKFATLOCATIONS - Run the network EKF at supplied surface coordinates.
% Equal-size networks share the measurement-noise realization for a common seed.

arguments
    database (1,1) struct
    sensorLatitudesRad (:,1) double
    sensorLongitudesRad (:,1) double
    filteredAvailability logical
    userConfig (1,1) struct = struct()
end

sensorLatitudesRad = double(sensorLatitudesRad(:));
sensorLongitudesRad = mod(double(sensorLongitudesRad(:)),2*pi);
numberOfSensors = numel(sensorLatitudesRad);
numberOfTimes = numel(database.tracking.times);
numberOfObjects = database.meta.numberOfObjects;

assert(numberOfSensors > 0, ...
    "validateNetworkEkfAtLocations:EmptyNetwork", ...
    "At least one sensor location is required.");
assert(numel(sensorLongitudesRad) == numberOfSensors, ...
    "validateNetworkEkfAtLocations:CoordinateSizeMismatch", ...
    "Sensor latitude and longitude arrays must have equal length.");
assert(size(filteredAvailability,1) == numberOfSensors && ...
    size(filteredAvailability,2) == numberOfTimes && ...
    size(filteredAvailability,3) == numberOfObjects, ...
    "validateNetworkEkfAtLocations:AvailabilitySizeMismatch", ...
    "Filtered availability must be sensor-by-time-by-object.");

validationDatabase = database;
validationDatabase.meta.numberOfCandidates = numberOfSensors;
validationDatabase.candidates.latitudesRad = sensorLatitudesRad;
validationDatabase.candidates.longitudesRad = sensorLongitudesRad;
validationDatabase.visibility.filteredAvailability = filteredAvailability;
validationDatabase.visibility.candidateChunks = struct([]);

localSensorIndices = (1:numberOfSensors).';
validation = optimization.validateNetworkEkf( ...
    validationDatabase,localSensorIndices,userConfig);

validation.version = "lunar_network_ekf_location_validation_v1";
validation.sensorIndices = zeros(0,1);
validation.sensorLatitudesRad = sensorLatitudesRad;
validation.sensorLongitudesRad = sensorLongitudesRad;
validation.usedArbitrarySensorLocations = true;
end

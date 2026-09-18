function selectedJacobians = ...
    loadChunkedMeasurementJacobians(database,sensorIndices)
% LOADCHUNKEDMEASUREMENTJACOBIANS Compatibility wrapper for chunk loader.

arguments
    database (1,1) struct
    sensorIndices (:,1) double
end

selectedJacobians = ...
    optimization.loadChunkedCandidateData( ...
        database,sensorIndices,"measurementJacobianHistories");

end

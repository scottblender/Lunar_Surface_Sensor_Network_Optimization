function [indices,exactMatch] = matchCandidateLocations( ...
    database,latitudesRad,longitudesRad)
% MATCHCANDIDATELOCATIONS - Match wrapped coordinates (rad) to frozen candidate IDs.

candidateLatitudesRad = double(database.candidates.latitudesRad(:));
candidateLongitudesRad = mod( ...
    double(database.candidates.longitudesRad(:)),2*pi);

indices = zeros(numel(latitudesRad),1);
exactMatch = true;
for sensorIndex = 1:numel(latitudesRad)
    latitudeDifference = candidateLatitudesRad-latitudesRad(sensorIndex);
    longitudeDifference = atan2( ...
        sin(candidateLongitudesRad-longitudesRad(sensorIndex)), ...
        cos(candidateLongitudesRad-longitudesRad(sensorIndex)));
    [distance,index] = min(hypot(latitudeDifference,longitudeDifference));
    indices(sensorIndex) = index;
    exactMatch = exactMatch && distance < 1e-10;
end
end

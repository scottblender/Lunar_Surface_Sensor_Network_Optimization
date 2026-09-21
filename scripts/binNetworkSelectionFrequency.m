function percent = binNetworkSelectionFrequency(runStates,database,latitudeEdges,longitudeEdges)
% Percentage of runs with one or more selected sensors in each geographic bin.
assert(~isempty(runStates),"No optimization runs supplied.");
counts = zeros(numel(latitudeEdges)-1,numel(longitudeEdges)-1);
for run = 1:numel(runStates)
    state = runStates{run};
    if isfield(state,"bestSensorLatitudesRad") && isfield(state,"bestSensorLongitudesRad")
        latitude = rad2deg(double(state.bestSensorLatitudesRad(:)));
        longitude = rad2deg(double(state.bestSensorLongitudesRad(:)));
    else
        indices = double(state.bestSensorIndices(:));
        latitude = rad2deg(double(database.candidates.latitudesRad(indices)));
        longitude = rad2deg(double(database.candidates.longitudesRad(indices)));
    end
    assert(all(isfinite(latitude)) && all(isfinite(longitude)), ...
        "Nonfinite optimized sensor coordinates.");
    assert(all(latitude>=latitudeEdges(1) & latitude<=latitudeEdges(end)), ...
        "Optimized latitude lies outside the plotted domain.");
    histogram = histcounts2(latitude,mod(longitude,360),latitudeEdges,longitudeEdges);
    counts = counts+(histogram>0);
end
percent = 100*counts/numel(runStates);
end

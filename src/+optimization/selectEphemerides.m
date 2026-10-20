function [earthPositionsMci,sunPositionsMci] = ...
    selectEphemerides(database,trackingTimes)
% SELECTEPHEMERIDES - Align frozen Earth/Sun histories to requested epochs (s).

fullTimes = double(database.truth.times(:));
indices = zeros(numel(trackingTimes),1);
for timeIndex = 1:numel(trackingTimes)
    [difference,index] = min(abs(fullTimes-trackingTimes(timeIndex)));
    assert(difference < 1e-8, "selectEphemerides:TimeMismatch", ...
        sprintf('Could not align ephemerides with tracking time %.6f s.', ...
        trackingTimes(timeIndex)));
    indices(timeIndex) = index;
end

earthPositionsMci = double(database.ephemeris.earthPositionsMci(:,indices));
sunPositionsMci = double(database.ephemeris.sunPositionsMci(:,indices));
end

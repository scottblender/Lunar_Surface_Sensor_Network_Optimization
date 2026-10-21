function grid = describeDemGrid(latitudeRad,longitudeRad)
% DESCRIBEDEMGRID - Preserve native coverage/spacing before pole and seam padding.
% A regional longitude footprint is the circular arc excluding its largest gap.
% Only a missing half-cell at a pole may be extended; arbitrary regional gaps may not.
arguments
    latitudeRad (:,1) double
    longitudeRad (:,1) double
end
lat = sort(latitudeRad);
lon = unique(mod(longitudeRad,2*pi));
assert(numel(lat)>=2 && numel(lon)>=2 && all(isfinite(lat)) && all(isfinite(lon)) && ...
    all(diff(lat)>0) && min(lat)>=-pi/2-1e-10 && max(lat)<=pi/2+1e-10, ...
    "describeDemGrid:InvalidGrid","DEM requires finite distinct coordinates within lunar latitude bounds.");
latSteps = diff(lat);
lonSteps = diff([lon;lon(1)+2*pi]);
[gap,gapIndex] = max(lonSteps);
% A large unsampled longitude sector must not become a periodic global raster.
otherSteps = lonSteps;
otherSteps(gapIndex) = [];
typicalLonStep = median(otherSteps);
fullLongitude = gap <= 1.5*typicalLonStep+1e-12;
if fullLongitude
    start = 0; span = 2*pi; maximumLonStep = gap;
else
    start = lon(mod(gapIndex,numel(lon))+1);
    span = 2*pi-gap;
    lonSteps(gapIndex) = [];
    maximumLonStep = max(lonSteps);
end
bounds = [lat(1) lat(end)];
if bounds(1)+pi/2 <= 0.5*latSteps(1)+1e-12, bounds(1) = -pi/2; end
if pi/2-bounds(2) <= 0.5*latSteps(end)+1e-12, bounds(2) = pi/2; end
grid = struct("sampleLatitudeBoundsRad",[lat(1) lat(end)], ...
    "latitudeCoverageRad",bounds,"longitudeStartRad",start, ...
    "longitudeSpanRad",span,"fullLongitude",fullLongitude, ...
    "maximumLatitudeStepRad",max(latSteps),"maximumLongitudeStepRad",maximumLonStep, ...
    "medianLatitudeStepRad",median(latSteps),"medianLongitudeStepRad",median(lonSteps), ...
    "sourceGridSize",[numel(latitudeRad) numel(longitudeRad)], ...
    "coverageBasis","original_interpolant_grid");
end

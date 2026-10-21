function jacobians = computeSelectedJacobians(database,sensorIndices)
% COMPUTESELECTEDJACOBIANS - Vectorized exact position Jacobians for selected sites.
% Uses frozen reference trajectories and elevations; no DEM reload or disk Jacobians.
ids = sensorIndices(:);
lat = database.candidates.latitudesRad(ids);
lon = database.candidates.longitudesRad(ids);
radius = database.config.moon.radiusKm + database.candidates.sensorElevationsKm(ids);
xr = radius.*cos(lat).*cos(lon); yr = radius.*cos(lat).*sin(lon); zr = radius.*sin(lat);
times = database.tracking.times(:).';
angle = database.config.moon.theta0Rad + 2*pi/database.config.moon.siderealPeriodSeconds*times;
xs = xr*cos(angle)-yr*sin(angle); ys = xr*sin(angle)+yr*cos(angle);
n = numel(ids); nt = numel(times); no = database.meta.numberOfObjects;
jacobians = zeros(2,3,n,nt,no);
for object = 1:no
    state = database.tracking.referenceStateHistories(:,:,object);
    x = state(1,:)-xs; y = state(2,:)-ys; z = state(3,:)-zr;
    rho2 = x.^2+y.^2; rho = sqrt(rho2); range2 = rho2+z.^2;
    assert(all(rho2>0 & range2>0,"all"),"computeSelectedJacobians:Singular", ...
        "RA/Dec Jacobian is singular for a selected sensor/target.");
    jacobians(1,1,:,:,object) = reshape(-y./rho2,1,1,n,nt);
    jacobians(1,2,:,:,object) = reshape(x./rho2,1,1,n,nt);
    jacobians(2,1,:,:,object) = reshape(-x.*z./(range2.*rho),1,1,n,nt);
    jacobians(2,2,:,:,object) = reshape(-y.*z./(range2.*rho),1,1,n,nt);
    jacobians(2,3,:,:,object) = reshape(rho./range2,1,1,n,nt);
end
end

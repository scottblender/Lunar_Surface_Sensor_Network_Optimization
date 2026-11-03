function angles=networkShapeSignature(locations)
% NETWORKSHAPESIGNATURE - Sorted three spherical side lengths, in degrees.
% Invariant to observer permutation, global rotation AND reflection. Similar
% signatures indicate similar shape, not absolute geographic convergence.
arguments
    locations (3,2) double {mustBeFinite}
end
assert(all(abs(locations(:,1))<=90),"geographicDiagnostics:Latitude","Invalid latitude.");
lat=deg2rad(locations(:,1)); lon=deg2rad(locations(:,2));
x=[cos(lat).*cos(lon),cos(lat).*sin(lon),sin(lat)];
pairs=[1 2;1 3;2 3]; angles=zeros(1,3);
for k=1:3
    a=x(pairs(k,1),:); b=x(pairs(k,2),:);
    angles(k)=rad2deg(atan2(norm(cross(a,b)),dot(a,b)));
end
angles=sort(angles);
end

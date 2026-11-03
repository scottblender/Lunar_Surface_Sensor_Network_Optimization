function [order,distancesKm] = matchThreeObserverLocations(reference,locations,radiusKm,distanceMetric)
% MATCHTHREEOBSERVERLOCATIONS - Unlabeled one-to-one matching of three sites.
% Default minimizes sum/mean distance, preserving existing behavior. The max
% metric minimizes the worst matched sensor distance (bottleneck matching).
% Rows contain [latitudeDeg eastLongitudeDeg]. Observer labels are interchangeable.
arguments
    reference (3,2) double {mustBeFinite}
    locations (3,2) double {mustBeFinite}
    radiusKm (1,1) double {mustBePositive} = 1737.4
    distanceMetric (1,1) string {mustBeMember(distanceMetric,["mean","max"])} = "mean"
end
assert(all(abs(reference(:,1))<=90) && all(abs(locations(:,1))<=90), ...
    "matchThreeObserverLocations:Latitude","Invalid latitude.");
a=deg2rad(reference(:,1)); b=deg2rad(locations(:,1)).';
dlon=deg2rad(reference(:,2)-locations(:,2).');
h=sin((a-b)/2).^2+cos(a).*cos(b).*sin(dlon/2).^2;
cost=2*radiusKm*asin(sqrt(min(1,max(0,h))));
orders=sortrows(perms(1:3)); totals=zeros(6,2);
for k=1:6
    d=cost(sub2ind([3 3],1:3,orders(k,:)));
    primary=sum(d); if distanceMetric=="max", primary=max(d); end
    totals(k,:)=[primary,sum(d)];
end
[~,rank]=sortrows(totals,[1 2]); best=rank(1); order=orders(best,:).';
distancesKm=cost(sub2ind([3 3],(1:3).',order));
end

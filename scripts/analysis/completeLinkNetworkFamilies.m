function labels=completeLinkNetworkFamilies(distances,thresholdKm)
% COMPLETELINKNETWORKFAMILIES - Deterministic complete linkage, no extra toolbox.
% Merge by maximum cross-family distance. Each returned family's diameter in
% the supplied metric is <= thresholdKm. Families are geometric groups, not modes.
arguments
    distances (:,:) double {mustBeFinite,mustBeNonnegative}
    thresholdKm (1,1) double {mustBePositive,mustBeFinite}
end
n=size(distances,1);
if n==0, labels=zeros(0,1); return; end
assert(size(distances,2)==n && max(abs(distances-distances.'),[],"all")<1e-8 && ...
    all(abs(diag(distances))<1e-8),"networkFamilies:Distances","Expected a symmetric distance matrix with zero diagonal.");
work=distances; work(1:n+1:end)=Inf;
members=num2cell((1:n).'); active=true(n,1);
while true
    [value,index]=min(work(:));
    if value>thresholdKm, break; end
    [i,j]=ind2sub([n n],index); a=min(i,j); b=max(i,j);
    merged=max(work(a,:),work(b,:));
    members{a}=[members{a};members{b}]; members{b}=[]; active(b)=false;
    work(a,:)=merged; work(:,a)=merged.';
    work(b,:)=Inf; work(:,b)=Inf; work(a,a)=Inf;
end
labels=zeros(n,1); groups=find(active);
for k=1:numel(groups), labels(members{groups(k)})=k; end
end

function value=diagnosticQuantile(values,q)
% DIAGNOSTICQUANTILE - Linear-interpolated sample quantiles, columns independent.
if isempty(values), value=NaN(numel(q),size(values,2)); return; end
values=sort(values,1); n=size(values,1); q=q(:); x=1+q*(n-1);
value=values(floor(x),:)+(x-floor(x)).*(values(ceil(x),:)-values(floor(x),:));
end

function [objective,metadata] = createBatchedInformationObjective(database,device,batchSize,networkSizes)
% CREATEBATCHEDINFORMATIONOBJECTIVE - Double-precision information score for up to ten sites.
% 'gpu' uses MATLAB GPU arrayfun: one thread per network/object, with epochs
% sequential within a thread. No CUDA compiler or custom MEX is required.
% 'cpu' executes the exact same scalar kernel for data-free numerical tests.
% Visibility is loaded once; geometry/Jacobians are computed on device. The
% kernel applies independent sensor updates sequentially using 2x2 innovation
% Cholesky solves and Joseph updates, algebraically equivalent to CPU stacking.
arguments
    database (1,1) struct
    device (1,1) string {mustBeMember(device,["cpu","gpu"])} = "gpu"
    batchSize (1,1) double {mustBeInteger,mustBePositive} = 60
    networkSizes (1,:) double {mustBeInteger,mustBePositive,mustBeLessThanOrEqual(networkSizes,10)} = 3
end
domain=database.config.domainComparison;
assert(ismember(domain.domain,["global","clps","clps_fixed"]), ...
    "gpuInformation:Domain","Use a paper domain view.");
assert(database.meta.measurementJacobianStorage=="on_demand", ...
    "gpuInformation:Storage","Use the existing on_demand database.");
n=database.meta.numberOfCandidates; nt=database.meta.numberOfOptimizationEpochs;
no=database.meta.numberOfObjects; penalty=database.objective.infeasiblePenalty;
prior=double(database.prior.initialCovariances);
transitions=double(database.tracking.stateTransitionHistories);
noise=double(database.tracking.processNoiseHistories);
reference=double(database.tracking.referenceStateHistories(1:3,:,:));
measurement=double(database.measurement.covariance);
scales=double(database.estimation.stateScales(:));
weights=double(database.estimation.objectWeights(:).');
assert(numel(weights)==no && all(isfinite(weights) & weights>=0) && sum(weights)>0, ...
    "gpuInformation:Weights","Invalid object weights.");
weights=weights/sum(weights);
assert(isequal(size(prior),[6 6 no]) || (no==1 && isequal(size(prior),[6 6])), ...
    "gpuInformation:Dimensions","Invalid prior dimensions.");
assert(size(transitions,3)==nt && size(transitions,4)==no && ...
    size(noise,3)==nt && size(noise,4)==no && size(reference,2)==nt && size(reference,3)==no, ...
    "gpuInformation:Dimensions","Invalid tracking dimensions.");
for object=1:no
    [~,flag]=chol(0.5*(prior(:,:,object)+prior(:,:,object).'));
    assert(flag==0,"gpuInformation:Prior","Prior must be positive definite.");
end
perSiteNoise=size(measurement,3)~=1;
assert(size(measurement,1)==2 && size(measurement,2)==2 && ...
    (size(measurement,3)==1 || size(measurement,3)==n), ...
    "gpuInformation:Noise","Use shared or per-candidate independent 2x2 noise.");
for k=1:size(measurement,3)
    r=measurement(:,:,k); [~,flag]=chol(r);
    assert(flag==0 && isequal(r,r.'),"gpuInformation:Noise","Noise must be symmetric positive definite.");
end
lat=database.candidates.latitudesRad(:); lon=database.candidates.longitudesRad(:);
radius=database.config.moon.radiusKm+database.candidates.sensorElevationsKm(:);
xyz=double([radius.*cos(lat).*cos(lon),radius.*cos(lat).*sin(lon),radius.*sin(lat)]);
angle=database.config.moon.theta0Rad+2*pi/database.config.moon.siderealPeriodSeconds*database.tracking.times(:);
cosine=cos(angle); sine=sin(angle);
estimatedBytes=n*nt*no+8*(numel(prior)+numel(transitions)+numel(noise)+ ...
    numel(reference)+numel(measurement)+numel(xyz)+numel(scales)+numel(weights)+numel(angle)*2);
metadata=struct("device",device,"precision","double","batchSize",batchSize, ...
    "estimatedResidentBytes",estimatedBytes,"numberOfCandidates",n,"numberOfObjects",no, ...
    "numberOfEpochs",nt,"updateRule","sequential independent 2x2 Joseph updates");
if device=="gpu"
    g=gpuDevice;
    assert(estimatedBytes*1.3+512*2^20<g.AvailableMemory,"gpuInformation:Memory", ...
        "Insufficient free GPU memory for frozen visibility and working headroom.");
    metadata.gpuName=string(g.Name); metadata.computeCapability=string(g.ComputeCapability);
    metadata.availableMemoryBefore=g.AvailableMemory;
end
availability=false(n,nt,no);
% Bound host read temporaries; preserve view-local ordering through the loader.
for first=1:4096:n
    ids=(first:min(n,first+4095)).';
    availability(ids,:,:)=optimization.loadChunkedCandidateData(database,ids,"filteredAvailability");
end
if device=="gpu"
    availability=gpuArray(availability); prior=gpuArray(prior);
    transitions=gpuArray(transitions); noise=gpuArray(noise); reference=gpuArray(reference);
    measurement=gpuArray(measurement); xyz=gpuArray(xyz); scales=gpuArray(scales);
    weights=gpuArray(weights); cosine=gpuArray(cosine); sine=gpuArray(sine);
    objects=gpuArray(1:no);
else
    objects=1:no;
end
objective=@evaluate;

    function values=evaluate(networks)
        if iscolumn(networks) && ~ismember(1,networkSizes) && ismember(numel(networks),networkSizes)
            networks=networks.';
        end
        assert(ismatrix(networks) && ismember(size(networks,2),networkSizes), ...
            "gpuInformation:NetworkSize","Expected one network per row with a configured network size.");
        networks=sort(double(networks),2);
        valid=all(isfinite(networks) & networks==round(networks) & networks>=1 & networks<=n,2) & ...
            all(diff(networks,1,2)>0,2);
        if domain.enforceSiteGroups
            for row=find(valid).'
                ids=networks(row,:);
                if isfield(domain,"anchorMembership")
                    valid(row)=optimization.canAssignDistinctAnchors(domain.anchorMembership(ids,:));
                else
                    groups=domain.prefilterSiteIds(database.candidates.originalIndices(ids));
                    valid(row)=all(strlength(groups)>0) && numel(unique(groups))==numel(ids);
                end
            end
        end
        values=repmat(penalty,size(networks,1),1); rows=find(valid);
        for first=1:batchSize:numel(rows)
            selected=rows(first:min(first+batchSize-1,numel(rows)));
            sites=zeros(numel(selected),10);
            sites(:,1:size(networks,2))=networks(selected,:);
            if device=="gpu"
                sites=gpuArray(sites);
                objectIds=objects;
            else
                objectIds=repmat(objects,numel(selected),1);
            end
            columns=cell(1,10);
            for slot=1:10, columns{slot}=sites(:,slot); end
            if device=="cpu"
                columns=cellfun(@(column) repmat(column,1,no),columns,'UniformOutput',false);
            end
            byObject=arrayfun(@trajectory,columns{:},objectIds);
            scores=-sum(byObject.*weights,2);
            if device=="gpu", scores=gather(scores); end
            assert(all(isfinite(scores)),"gpuInformation:Numerics", ...
                "Nonpositive covariance or singular geometry; GPU objective aborted.");
            values(selected)=scores;
        end
    end

% BEGIN GENERATED KERNEL
        function score = trajectory(n1,n2,n3,n4,n5,n6,n7,n8,n9,n10,object)
        % One CUDA thread per network/object; double scalar registers only.
        p11 = 0.5*(prior(1,1,object)+prior(1,1,object));
        p12 = 0.5*(prior(1,2,object)+prior(2,1,object));
        p13 = 0.5*(prior(1,3,object)+prior(3,1,object));
        p14 = 0.5*(prior(1,4,object)+prior(4,1,object));
        p15 = 0.5*(prior(1,5,object)+prior(5,1,object));
        p16 = 0.5*(prior(1,6,object)+prior(6,1,object));
        p22 = 0.5*(prior(2,2,object)+prior(2,2,object));
        p23 = 0.5*(prior(2,3,object)+prior(3,2,object));
        p24 = 0.5*(prior(2,4,object)+prior(4,2,object));
        p25 = 0.5*(prior(2,5,object)+prior(5,2,object));
        p26 = 0.5*(prior(2,6,object)+prior(6,2,object));
        p33 = 0.5*(prior(3,3,object)+prior(3,3,object));
        p34 = 0.5*(prior(3,4,object)+prior(4,3,object));
        p35 = 0.5*(prior(3,5,object)+prior(5,3,object));
        p36 = 0.5*(prior(3,6,object)+prior(6,3,object));
        p44 = 0.5*(prior(4,4,object)+prior(4,4,object));
        p45 = 0.5*(prior(4,5,object)+prior(5,4,object));
        p46 = 0.5*(prior(4,6,object)+prior(6,4,object));
        p55 = 0.5*(prior(5,5,object)+prior(5,5,object));
        p56 = 0.5*(prior(5,6,object)+prior(6,5,object));
        p66 = 0.5*(prior(6,6,object)+prior(6,6,object));
        score = 0;
        for epoch = 1:nt
        f11 = transitions(1,1,epoch,object);
        f12 = transitions(1,2,epoch,object);
        f13 = transitions(1,3,epoch,object);
        f14 = transitions(1,4,epoch,object);
        f15 = transitions(1,5,epoch,object);
        f16 = transitions(1,6,epoch,object);
        f21 = transitions(2,1,epoch,object);
        f22 = transitions(2,2,epoch,object);
        f23 = transitions(2,3,epoch,object);
        f24 = transitions(2,4,epoch,object);
        f25 = transitions(2,5,epoch,object);
        f26 = transitions(2,6,epoch,object);
        f31 = transitions(3,1,epoch,object);
        f32 = transitions(3,2,epoch,object);
        f33 = transitions(3,3,epoch,object);
        f34 = transitions(3,4,epoch,object);
        f35 = transitions(3,5,epoch,object);
        f36 = transitions(3,6,epoch,object);
        f41 = transitions(4,1,epoch,object);
        f42 = transitions(4,2,epoch,object);
        f43 = transitions(4,3,epoch,object);
        f44 = transitions(4,4,epoch,object);
        f45 = transitions(4,5,epoch,object);
        f46 = transitions(4,6,epoch,object);
        f51 = transitions(5,1,epoch,object);
        f52 = transitions(5,2,epoch,object);
        f53 = transitions(5,3,epoch,object);
        f54 = transitions(5,4,epoch,object);
        f55 = transitions(5,5,epoch,object);
        f56 = transitions(5,6,epoch,object);
        f61 = transitions(6,1,epoch,object);
        f62 = transitions(6,2,epoch,object);
        f63 = transitions(6,3,epoch,object);
        f64 = transitions(6,4,epoch,object);
        f65 = transitions(6,5,epoch,object);
        f66 = transitions(6,6,epoch,object);
        t11 = f11*p11 + f12*p12 + f13*p13 + f14*p14 + f15*p15 + f16*p16;
        t12 = f11*p12 + f12*p22 + f13*p23 + f14*p24 + f15*p25 + f16*p26;
        t13 = f11*p13 + f12*p23 + f13*p33 + f14*p34 + f15*p35 + f16*p36;
        t14 = f11*p14 + f12*p24 + f13*p34 + f14*p44 + f15*p45 + f16*p46;
        t15 = f11*p15 + f12*p25 + f13*p35 + f14*p45 + f15*p55 + f16*p56;
        t16 = f11*p16 + f12*p26 + f13*p36 + f14*p46 + f15*p56 + f16*p66;
        t21 = f21*p11 + f22*p12 + f23*p13 + f24*p14 + f25*p15 + f26*p16;
        t22 = f21*p12 + f22*p22 + f23*p23 + f24*p24 + f25*p25 + f26*p26;
        t23 = f21*p13 + f22*p23 + f23*p33 + f24*p34 + f25*p35 + f26*p36;
        t24 = f21*p14 + f22*p24 + f23*p34 + f24*p44 + f25*p45 + f26*p46;
        t25 = f21*p15 + f22*p25 + f23*p35 + f24*p45 + f25*p55 + f26*p56;
        t26 = f21*p16 + f22*p26 + f23*p36 + f24*p46 + f25*p56 + f26*p66;
        t31 = f31*p11 + f32*p12 + f33*p13 + f34*p14 + f35*p15 + f36*p16;
        t32 = f31*p12 + f32*p22 + f33*p23 + f34*p24 + f35*p25 + f36*p26;
        t33 = f31*p13 + f32*p23 + f33*p33 + f34*p34 + f35*p35 + f36*p36;
        t34 = f31*p14 + f32*p24 + f33*p34 + f34*p44 + f35*p45 + f36*p46;
        t35 = f31*p15 + f32*p25 + f33*p35 + f34*p45 + f35*p55 + f36*p56;
        t36 = f31*p16 + f32*p26 + f33*p36 + f34*p46 + f35*p56 + f36*p66;
        t41 = f41*p11 + f42*p12 + f43*p13 + f44*p14 + f45*p15 + f46*p16;
        t42 = f41*p12 + f42*p22 + f43*p23 + f44*p24 + f45*p25 + f46*p26;
        t43 = f41*p13 + f42*p23 + f43*p33 + f44*p34 + f45*p35 + f46*p36;
        t44 = f41*p14 + f42*p24 + f43*p34 + f44*p44 + f45*p45 + f46*p46;
        t45 = f41*p15 + f42*p25 + f43*p35 + f44*p45 + f45*p55 + f46*p56;
        t46 = f41*p16 + f42*p26 + f43*p36 + f44*p46 + f45*p56 + f46*p66;
        t51 = f51*p11 + f52*p12 + f53*p13 + f54*p14 + f55*p15 + f56*p16;
        t52 = f51*p12 + f52*p22 + f53*p23 + f54*p24 + f55*p25 + f56*p26;
        t53 = f51*p13 + f52*p23 + f53*p33 + f54*p34 + f55*p35 + f56*p36;
        t54 = f51*p14 + f52*p24 + f53*p34 + f54*p44 + f55*p45 + f56*p46;
        t55 = f51*p15 + f52*p25 + f53*p35 + f54*p45 + f55*p55 + f56*p56;
        t56 = f51*p16 + f52*p26 + f53*p36 + f54*p46 + f55*p56 + f56*p66;
        t61 = f61*p11 + f62*p12 + f63*p13 + f64*p14 + f65*p15 + f66*p16;
        t62 = f61*p12 + f62*p22 + f63*p23 + f64*p24 + f65*p25 + f66*p26;
        t63 = f61*p13 + f62*p23 + f63*p33 + f64*p34 + f65*p35 + f66*p36;
        t64 = f61*p14 + f62*p24 + f63*p34 + f64*p44 + f65*p45 + f66*p46;
        t65 = f61*p15 + f62*p25 + f63*p35 + f64*p45 + f65*p55 + f66*p56;
        t66 = f61*p16 + f62*p26 + f63*p36 + f64*p46 + f65*p56 + f66*p66;
        p11 = 0.5*(t11*f11 + t12*f12 + t13*f13 + t14*f14 + t15*f15 + t16*f16 + t11*f11 + t12*f12 + t13*f13 + t14*f14 + t15*f15 + t16*f16 + noise(1,1,epoch,object)+noise(1,1,epoch,object));
        p12 = 0.5*(t11*f21 + t12*f22 + t13*f23 + t14*f24 + t15*f25 + t16*f26 + t21*f11 + t22*f12 + t23*f13 + t24*f14 + t25*f15 + t26*f16 + noise(1,2,epoch,object)+noise(2,1,epoch,object));
        p13 = 0.5*(t11*f31 + t12*f32 + t13*f33 + t14*f34 + t15*f35 + t16*f36 + t31*f11 + t32*f12 + t33*f13 + t34*f14 + t35*f15 + t36*f16 + noise(1,3,epoch,object)+noise(3,1,epoch,object));
        p14 = 0.5*(t11*f41 + t12*f42 + t13*f43 + t14*f44 + t15*f45 + t16*f46 + t41*f11 + t42*f12 + t43*f13 + t44*f14 + t45*f15 + t46*f16 + noise(1,4,epoch,object)+noise(4,1,epoch,object));
        p15 = 0.5*(t11*f51 + t12*f52 + t13*f53 + t14*f54 + t15*f55 + t16*f56 + t51*f11 + t52*f12 + t53*f13 + t54*f14 + t55*f15 + t56*f16 + noise(1,5,epoch,object)+noise(5,1,epoch,object));
        p16 = 0.5*(t11*f61 + t12*f62 + t13*f63 + t14*f64 + t15*f65 + t16*f66 + t61*f11 + t62*f12 + t63*f13 + t64*f14 + t65*f15 + t66*f16 + noise(1,6,epoch,object)+noise(6,1,epoch,object));
        p22 = 0.5*(t21*f21 + t22*f22 + t23*f23 + t24*f24 + t25*f25 + t26*f26 + t21*f21 + t22*f22 + t23*f23 + t24*f24 + t25*f25 + t26*f26 + noise(2,2,epoch,object)+noise(2,2,epoch,object));
        p23 = 0.5*(t21*f31 + t22*f32 + t23*f33 + t24*f34 + t25*f35 + t26*f36 + t31*f21 + t32*f22 + t33*f23 + t34*f24 + t35*f25 + t36*f26 + noise(2,3,epoch,object)+noise(3,2,epoch,object));
        p24 = 0.5*(t21*f41 + t22*f42 + t23*f43 + t24*f44 + t25*f45 + t26*f46 + t41*f21 + t42*f22 + t43*f23 + t44*f24 + t45*f25 + t46*f26 + noise(2,4,epoch,object)+noise(4,2,epoch,object));
        p25 = 0.5*(t21*f51 + t22*f52 + t23*f53 + t24*f54 + t25*f55 + t26*f56 + t51*f21 + t52*f22 + t53*f23 + t54*f24 + t55*f25 + t56*f26 + noise(2,5,epoch,object)+noise(5,2,epoch,object));
        p26 = 0.5*(t21*f61 + t22*f62 + t23*f63 + t24*f64 + t25*f65 + t26*f66 + t61*f21 + t62*f22 + t63*f23 + t64*f24 + t65*f25 + t66*f26 + noise(2,6,epoch,object)+noise(6,2,epoch,object));
        p33 = 0.5*(t31*f31 + t32*f32 + t33*f33 + t34*f34 + t35*f35 + t36*f36 + t31*f31 + t32*f32 + t33*f33 + t34*f34 + t35*f35 + t36*f36 + noise(3,3,epoch,object)+noise(3,3,epoch,object));
        p34 = 0.5*(t31*f41 + t32*f42 + t33*f43 + t34*f44 + t35*f45 + t36*f46 + t41*f31 + t42*f32 + t43*f33 + t44*f34 + t45*f35 + t46*f36 + noise(3,4,epoch,object)+noise(4,3,epoch,object));
        p35 = 0.5*(t31*f51 + t32*f52 + t33*f53 + t34*f54 + t35*f55 + t36*f56 + t51*f31 + t52*f32 + t53*f33 + t54*f34 + t55*f35 + t56*f36 + noise(3,5,epoch,object)+noise(5,3,epoch,object));
        p36 = 0.5*(t31*f61 + t32*f62 + t33*f63 + t34*f64 + t35*f65 + t36*f66 + t61*f31 + t62*f32 + t63*f33 + t64*f34 + t65*f35 + t66*f36 + noise(3,6,epoch,object)+noise(6,3,epoch,object));
        p44 = 0.5*(t41*f41 + t42*f42 + t43*f43 + t44*f44 + t45*f45 + t46*f46 + t41*f41 + t42*f42 + t43*f43 + t44*f44 + t45*f45 + t46*f46 + noise(4,4,epoch,object)+noise(4,4,epoch,object));
        p45 = 0.5*(t41*f51 + t42*f52 + t43*f53 + t44*f54 + t45*f55 + t46*f56 + t51*f41 + t52*f42 + t53*f43 + t54*f44 + t55*f45 + t56*f46 + noise(4,5,epoch,object)+noise(5,4,epoch,object));
        p46 = 0.5*(t41*f61 + t42*f62 + t43*f63 + t44*f64 + t45*f65 + t46*f66 + t61*f41 + t62*f42 + t63*f43 + t64*f44 + t65*f45 + t66*f46 + noise(4,6,epoch,object)+noise(6,4,epoch,object));
        p55 = 0.5*(t51*f51 + t52*f52 + t53*f53 + t54*f54 + t55*f55 + t56*f56 + t51*f51 + t52*f52 + t53*f53 + t54*f54 + t55*f55 + t56*f56 + noise(5,5,epoch,object)+noise(5,5,epoch,object));
        p56 = 0.5*(t51*f61 + t52*f62 + t53*f63 + t54*f64 + t55*f65 + t56*f66 + t61*f51 + t62*f52 + t63*f53 + t64*f54 + t65*f55 + t66*f56 + noise(5,6,epoch,object)+noise(6,5,epoch,object));
        p66 = 0.5*(t61*f61 + t62*f62 + t63*f63 + t64*f64 + t65*f65 + t66*f66 + t61*f61 + t62*f62 + t63*f63 + t64*f64 + t65*f65 + t66*f66 + noise(6,6,epoch,object)+noise(6,6,epoch,object));
        for sensor = 1:10
        if sensor==1, site=n1;
        elseif sensor==2, site=n2;
        elseif sensor==3, site=n3;
        elseif sensor==4, site=n4;
        elseif sensor==5, site=n5;
        elseif sensor==6, site=n6;
        elseif sensor==7, site=n7;
        elseif sensor==8, site=n8;
        elseif sensor==9, site=n9;
        else, site=n10; end
        if site==0, break; end
        x = reference(1,epoch,object)-(xyz(site,1)*cosine(epoch)-xyz(site,2)*sine(epoch));
        y = reference(2,epoch,object)-(xyz(site,1)*sine(epoch)+xyz(site,2)*cosine(epoch));
        z = reference(3,epoch,object)-xyz(site,3);
        rho2=x*x+y*y; range2=rho2+z*z;
        if ~(rho2>0 && range2>0), score=NaN; return; end
        if availability(site,epoch,object)
        rho=sqrt(rho2);
        h11=-y/rho2; h12=x/rho2; h13=0;
        h21=-x*z/(range2*rho); h22=-y*z/(range2*rho); h23=rho/range2;
        rindex=1; if perSiteNoise, rindex=site; end
        r11=measurement(1,1,rindex); r12=measurement(1,2,rindex); r22=measurement(2,2,rindex);
        b11 = p11*h11 + p12*h12 + p13*h13;
        b12 = p11*h21 + p12*h22 + p13*h23;
        b21 = p12*h11 + p22*h12 + p23*h13;
        b22 = p12*h21 + p22*h22 + p23*h23;
        b31 = p13*h11 + p23*h12 + p33*h13;
        b32 = p13*h21 + p23*h22 + p33*h23;
        b41 = p14*h11 + p24*h12 + p34*h13;
        b42 = p14*h21 + p24*h22 + p34*h23;
        b51 = p15*h11 + p25*h12 + p35*h13;
        b52 = p15*h21 + p25*h22 + p35*h23;
        b61 = p16*h11 + p26*h12 + p36*h13;
        b62 = p16*h21 + p26*h22 + p36*h23;
        s11=h11*b11+h12*b21+h13*b31+r11;
        s12=h11*b12+h12*b22+h13*b32+r12;
        s21=h21*b11+h22*b21+h23*b31+r12;
        s22=h21*b12+h22*b22+h23*b32+r22;
        if ~(s11>0), score=NaN; return; end
        s12=0.5*(s12+s21); c11=sqrt(s11); c21=s12/c11; pivot=s22-c21*c21;
        if ~(pivot>0), score=NaN; return; end
        c22=sqrt(pivot);
        y1=b11/c11; y2=(b12-c21*y1)/c22;
        k12=y2/c22; k11=(y1-c21*k12)/c11;
        y1=b21/c11; y2=(b22-c21*y1)/c22;
        k22=y2/c22; k21=(y1-c21*k22)/c11;
        y1=b31/c11; y2=(b32-c21*y1)/c22;
        k32=y2/c22; k31=(y1-c21*k32)/c11;
        y1=b41/c11; y2=(b42-c21*y1)/c22;
        k42=y2/c22; k41=(y1-c21*k42)/c11;
        y1=b51/c11; y2=(b52-c21*y1)/c22;
        k52=y2/c22; k51=(y1-c21*k52)/c11;
        y1=b61/c11; y2=(b62-c21*y1)/c22;
        k62=y2/c22; k61=(y1-c21*k62)/c11;
        a11 = 1-k11*h11-k12*h21;
        a12 = 0-k11*h12-k12*h22;
        a13 = 0-k11*h13-k12*h23;
        a14 = 0;
        a15 = 0;
        a16 = 0;
        a21 = 0-k21*h11-k22*h21;
        a22 = 1-k21*h12-k22*h22;
        a23 = 0-k21*h13-k22*h23;
        a24 = 0;
        a25 = 0;
        a26 = 0;
        a31 = 0-k31*h11-k32*h21;
        a32 = 0-k31*h12-k32*h22;
        a33 = 1-k31*h13-k32*h23;
        a34 = 0;
        a35 = 0;
        a36 = 0;
        a41 = 0-k41*h11-k42*h21;
        a42 = 0-k41*h12-k42*h22;
        a43 = 0-k41*h13-k42*h23;
        a44 = 1;
        a45 = 0;
        a46 = 0;
        a51 = 0-k51*h11-k52*h21;
        a52 = 0-k51*h12-k52*h22;
        a53 = 0-k51*h13-k52*h23;
        a54 = 0;
        a55 = 1;
        a56 = 0;
        a61 = 0-k61*h11-k62*h21;
        a62 = 0-k61*h12-k62*h22;
        a63 = 0-k61*h13-k62*h23;
        a64 = 0;
        a65 = 0;
        a66 = 1;
        b11 = a11*p11 + a12*p12 + a13*p13 + a14*p14 + a15*p15 + a16*p16;
        b12 = a11*p12 + a12*p22 + a13*p23 + a14*p24 + a15*p25 + a16*p26;
        b13 = a11*p13 + a12*p23 + a13*p33 + a14*p34 + a15*p35 + a16*p36;
        b14 = a11*p14 + a12*p24 + a13*p34 + a14*p44 + a15*p45 + a16*p46;
        b15 = a11*p15 + a12*p25 + a13*p35 + a14*p45 + a15*p55 + a16*p56;
        b16 = a11*p16 + a12*p26 + a13*p36 + a14*p46 + a15*p56 + a16*p66;
        b21 = a21*p11 + a22*p12 + a23*p13 + a24*p14 + a25*p15 + a26*p16;
        b22 = a21*p12 + a22*p22 + a23*p23 + a24*p24 + a25*p25 + a26*p26;
        b23 = a21*p13 + a22*p23 + a23*p33 + a24*p34 + a25*p35 + a26*p36;
        b24 = a21*p14 + a22*p24 + a23*p34 + a24*p44 + a25*p45 + a26*p46;
        b25 = a21*p15 + a22*p25 + a23*p35 + a24*p45 + a25*p55 + a26*p56;
        b26 = a21*p16 + a22*p26 + a23*p36 + a24*p46 + a25*p56 + a26*p66;
        b31 = a31*p11 + a32*p12 + a33*p13 + a34*p14 + a35*p15 + a36*p16;
        b32 = a31*p12 + a32*p22 + a33*p23 + a34*p24 + a35*p25 + a36*p26;
        b33 = a31*p13 + a32*p23 + a33*p33 + a34*p34 + a35*p35 + a36*p36;
        b34 = a31*p14 + a32*p24 + a33*p34 + a34*p44 + a35*p45 + a36*p46;
        b35 = a31*p15 + a32*p25 + a33*p35 + a34*p45 + a35*p55 + a36*p56;
        b36 = a31*p16 + a32*p26 + a33*p36 + a34*p46 + a35*p56 + a36*p66;
        b41 = a41*p11 + a42*p12 + a43*p13 + a44*p14 + a45*p15 + a46*p16;
        b42 = a41*p12 + a42*p22 + a43*p23 + a44*p24 + a45*p25 + a46*p26;
        b43 = a41*p13 + a42*p23 + a43*p33 + a44*p34 + a45*p35 + a46*p36;
        b44 = a41*p14 + a42*p24 + a43*p34 + a44*p44 + a45*p45 + a46*p46;
        b45 = a41*p15 + a42*p25 + a43*p35 + a44*p45 + a45*p55 + a46*p56;
        b46 = a41*p16 + a42*p26 + a43*p36 + a44*p46 + a45*p56 + a46*p66;
        b51 = a51*p11 + a52*p12 + a53*p13 + a54*p14 + a55*p15 + a56*p16;
        b52 = a51*p12 + a52*p22 + a53*p23 + a54*p24 + a55*p25 + a56*p26;
        b53 = a51*p13 + a52*p23 + a53*p33 + a54*p34 + a55*p35 + a56*p36;
        b54 = a51*p14 + a52*p24 + a53*p34 + a54*p44 + a55*p45 + a56*p46;
        b55 = a51*p15 + a52*p25 + a53*p35 + a54*p45 + a55*p55 + a56*p56;
        b56 = a51*p16 + a52*p26 + a53*p36 + a54*p46 + a55*p56 + a56*p66;
        b61 = a61*p11 + a62*p12 + a63*p13 + a64*p14 + a65*p15 + a66*p16;
        b62 = a61*p12 + a62*p22 + a63*p23 + a64*p24 + a65*p25 + a66*p26;
        b63 = a61*p13 + a62*p23 + a63*p33 + a64*p34 + a65*p35 + a66*p36;
        b64 = a61*p14 + a62*p24 + a63*p34 + a64*p44 + a65*p45 + a66*p46;
        b65 = a61*p15 + a62*p25 + a63*p35 + a64*p45 + a65*p55 + a66*p56;
        b66 = a61*p16 + a62*p26 + a63*p36 + a64*p46 + a65*p56 + a66*p66;
        u11 = 0.5*(b11*a11 + b12*a12 + b13*a13 + b14*a14 + b15*a15 + b16*a16 + b11*a11 + b12*a12 + b13*a13 + b14*a14 + b15*a15 + b16*a16) + k11*r11*k11 + k11*r12*k12 + k12*r12*k11 + k12*r22*k12;
        u12 = 0.5*(b11*a21 + b12*a22 + b13*a23 + b14*a24 + b15*a25 + b16*a26 + b21*a11 + b22*a12 + b23*a13 + b24*a14 + b25*a15 + b26*a16) + k11*r11*k21 + k11*r12*k22 + k12*r12*k21 + k12*r22*k22;
        u13 = 0.5*(b11*a31 + b12*a32 + b13*a33 + b14*a34 + b15*a35 + b16*a36 + b31*a11 + b32*a12 + b33*a13 + b34*a14 + b35*a15 + b36*a16) + k11*r11*k31 + k11*r12*k32 + k12*r12*k31 + k12*r22*k32;
        u14 = 0.5*(b11*a41 + b12*a42 + b13*a43 + b14*a44 + b15*a45 + b16*a46 + b41*a11 + b42*a12 + b43*a13 + b44*a14 + b45*a15 + b46*a16) + k11*r11*k41 + k11*r12*k42 + k12*r12*k41 + k12*r22*k42;
        u15 = 0.5*(b11*a51 + b12*a52 + b13*a53 + b14*a54 + b15*a55 + b16*a56 + b51*a11 + b52*a12 + b53*a13 + b54*a14 + b55*a15 + b56*a16) + k11*r11*k51 + k11*r12*k52 + k12*r12*k51 + k12*r22*k52;
        u16 = 0.5*(b11*a61 + b12*a62 + b13*a63 + b14*a64 + b15*a65 + b16*a66 + b61*a11 + b62*a12 + b63*a13 + b64*a14 + b65*a15 + b66*a16) + k11*r11*k61 + k11*r12*k62 + k12*r12*k61 + k12*r22*k62;
        u22 = 0.5*(b21*a21 + b22*a22 + b23*a23 + b24*a24 + b25*a25 + b26*a26 + b21*a21 + b22*a22 + b23*a23 + b24*a24 + b25*a25 + b26*a26) + k21*r11*k21 + k21*r12*k22 + k22*r12*k21 + k22*r22*k22;
        u23 = 0.5*(b21*a31 + b22*a32 + b23*a33 + b24*a34 + b25*a35 + b26*a36 + b31*a21 + b32*a22 + b33*a23 + b34*a24 + b35*a25 + b36*a26) + k21*r11*k31 + k21*r12*k32 + k22*r12*k31 + k22*r22*k32;
        u24 = 0.5*(b21*a41 + b22*a42 + b23*a43 + b24*a44 + b25*a45 + b26*a46 + b41*a21 + b42*a22 + b43*a23 + b44*a24 + b45*a25 + b46*a26) + k21*r11*k41 + k21*r12*k42 + k22*r12*k41 + k22*r22*k42;
        u25 = 0.5*(b21*a51 + b22*a52 + b23*a53 + b24*a54 + b25*a55 + b26*a56 + b51*a21 + b52*a22 + b53*a23 + b54*a24 + b55*a25 + b56*a26) + k21*r11*k51 + k21*r12*k52 + k22*r12*k51 + k22*r22*k52;
        u26 = 0.5*(b21*a61 + b22*a62 + b23*a63 + b24*a64 + b25*a65 + b26*a66 + b61*a21 + b62*a22 + b63*a23 + b64*a24 + b65*a25 + b66*a26) + k21*r11*k61 + k21*r12*k62 + k22*r12*k61 + k22*r22*k62;
        u33 = 0.5*(b31*a31 + b32*a32 + b33*a33 + b34*a34 + b35*a35 + b36*a36 + b31*a31 + b32*a32 + b33*a33 + b34*a34 + b35*a35 + b36*a36) + k31*r11*k31 + k31*r12*k32 + k32*r12*k31 + k32*r22*k32;
        u34 = 0.5*(b31*a41 + b32*a42 + b33*a43 + b34*a44 + b35*a45 + b36*a46 + b41*a31 + b42*a32 + b43*a33 + b44*a34 + b45*a35 + b46*a36) + k31*r11*k41 + k31*r12*k42 + k32*r12*k41 + k32*r22*k42;
        u35 = 0.5*(b31*a51 + b32*a52 + b33*a53 + b34*a54 + b35*a55 + b36*a56 + b51*a31 + b52*a32 + b53*a33 + b54*a34 + b55*a35 + b56*a36) + k31*r11*k51 + k31*r12*k52 + k32*r12*k51 + k32*r22*k52;
        u36 = 0.5*(b31*a61 + b32*a62 + b33*a63 + b34*a64 + b35*a65 + b36*a66 + b61*a31 + b62*a32 + b63*a33 + b64*a34 + b65*a35 + b66*a36) + k31*r11*k61 + k31*r12*k62 + k32*r12*k61 + k32*r22*k62;
        u44 = 0.5*(b41*a41 + b42*a42 + b43*a43 + b44*a44 + b45*a45 + b46*a46 + b41*a41 + b42*a42 + b43*a43 + b44*a44 + b45*a45 + b46*a46) + k41*r11*k41 + k41*r12*k42 + k42*r12*k41 + k42*r22*k42;
        u45 = 0.5*(b41*a51 + b42*a52 + b43*a53 + b44*a54 + b45*a55 + b46*a56 + b51*a41 + b52*a42 + b53*a43 + b54*a44 + b55*a45 + b56*a46) + k41*r11*k51 + k41*r12*k52 + k42*r12*k51 + k42*r22*k52;
        u46 = 0.5*(b41*a61 + b42*a62 + b43*a63 + b44*a64 + b45*a65 + b46*a66 + b61*a41 + b62*a42 + b63*a43 + b64*a44 + b65*a45 + b66*a46) + k41*r11*k61 + k41*r12*k62 + k42*r12*k61 + k42*r22*k62;
        u55 = 0.5*(b51*a51 + b52*a52 + b53*a53 + b54*a54 + b55*a55 + b56*a56 + b51*a51 + b52*a52 + b53*a53 + b54*a54 + b55*a55 + b56*a56) + k51*r11*k51 + k51*r12*k52 + k52*r12*k51 + k52*r22*k52;
        u56 = 0.5*(b51*a61 + b52*a62 + b53*a63 + b54*a64 + b55*a65 + b56*a66 + b61*a51 + b62*a52 + b63*a53 + b64*a54 + b65*a55 + b66*a56) + k51*r11*k61 + k51*r12*k62 + k52*r12*k61 + k52*r22*k62;
        u66 = 0.5*(b61*a61 + b62*a62 + b63*a63 + b64*a64 + b65*a65 + b66*a66 + b61*a61 + b62*a62 + b63*a63 + b64*a64 + b65*a65 + b66*a66) + k61*r11*k61 + k61*r12*k62 + k62*r12*k61 + k62*r22*k62;
        p11 = u11;
        p12 = u12;
        p13 = u13;
        p14 = u14;
        p15 = u15;
        p16 = u16;
        p22 = u22;
        p23 = u23;
        p24 = u24;
        p25 = u25;
        p26 = u26;
        p33 = u33;
        p34 = u34;
        p35 = u35;
        p36 = u36;
        p44 = u44;
        p45 = u45;
        p46 = u46;
        p55 = u55;
        p56 = u56;
        p66 = u66;
        end
        end
        % Cholesky of normalized covariance: same logdet metric as CPU.
        pivot=p11/(scales(1)*scales(1));
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l11=sqrt(pivot); score=score-2*log(l11);
        l21=(p12/(scales(2)*scales(1)))/l11;
        l31=(p13/(scales(3)*scales(1)))/l11;
        l41=(p14/(scales(4)*scales(1)))/l11;
        l51=(p15/(scales(5)*scales(1)))/l11;
        l61=(p16/(scales(6)*scales(1)))/l11;
        pivot=p22/(scales(2)*scales(2))-l21*l21;
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l22=sqrt(pivot); score=score-2*log(l22);
        l32=(p23/(scales(3)*scales(2))-l31*l21)/l22;
        l42=(p24/(scales(4)*scales(2))-l41*l21)/l22;
        l52=(p25/(scales(5)*scales(2))-l51*l21)/l22;
        l62=(p26/(scales(6)*scales(2))-l61*l21)/l22;
        pivot=p33/(scales(3)*scales(3))-l31*l31-l32*l32;
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l33=sqrt(pivot); score=score-2*log(l33);
        l43=(p34/(scales(4)*scales(3))-l41*l31-l42*l32)/l33;
        l53=(p35/(scales(5)*scales(3))-l51*l31-l52*l32)/l33;
        l63=(p36/(scales(6)*scales(3))-l61*l31-l62*l32)/l33;
        pivot=p44/(scales(4)*scales(4))-l41*l41-l42*l42-l43*l43;
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l44=sqrt(pivot); score=score-2*log(l44);
        l54=(p45/(scales(5)*scales(4))-l51*l41-l52*l42-l53*l43)/l44;
        l64=(p46/(scales(6)*scales(4))-l61*l41-l62*l42-l63*l43)/l44;
        pivot=p55/(scales(5)*scales(5))-l51*l51-l52*l52-l53*l53-l54*l54;
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l55=sqrt(pivot); score=score-2*log(l55);
        l65=(p56/(scales(6)*scales(5))-l61*l51-l62*l52-l63*l53-l64*l54)/l55;
        pivot=p66/(scales(6)*scales(6))-l61*l61-l62*l62-l63*l63-l64*l64-l65*l65;
        if ~(pivot>0) || ~isfinite(pivot), score=NaN; return; end
        l66=sqrt(pivot); score=score-2*log(l66);
        end
        score=score/nt;
        end
% END GENERATED KERNEL
end

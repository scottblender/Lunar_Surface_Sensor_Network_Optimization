function J = roundAndPenalize(x,objectiveFcn,problem)
% ROUNDANDPENALIZE Discrete candidate-index objective for continuous PSO.
% Round and sort; duplicate/out-of-bounds index vectors get the same
% infeasible penalty as optimization.networkObjective. No index repair.
indices = sort(round(double(x(:).')));
if numel(indices) ~= problem.nvars || ...
        any(~isfinite(indices)) || ...
        any(indices < problem.lb) || any(indices > problem.ub) || ...
        numel(unique(indices)) ~= problem.nvars
    J = problem.infeasiblePenalty;
    return
end
J = objectiveFcn(indices);
end

function J = roundAndPenalize(x,objectiveFcn,problem)
% ROUNDANDPENALIZE - Discrete candidate-index objective for continuous PSO.
%
% Inputs:
%   - x - Continuous particle coordinates.
%   - objectiveFcn, problem - Discrete objective, bounds, and infeasible penalty.
%
% Outputs:
%   - J - Objective of sorted rounded IDs, or a penalty for invalid IDs.

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

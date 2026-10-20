function result = runABC(objectiveFcn,problem,config)
% RUNABC - Run discrete artificial bee colony optimization within an FE budget.
%
% Inputs:
%   - objectiveFcn - Scalar minimization objective on distinct sensor-site IDs.
%   - problem - Common integer bounds and sensor-ordering constraints.
%   - config - FE budget, even colony size, parallel flag, display, and abcLimit.
%
% Outputs:
%   - result - Best network, scores, and strictly budgeted FE history.
%
% See also optimization.runOptimizer.

budget = config.functionEvaluationBudget;
colonySize = config.populationSize;
limit = 20;
if isfield(config,"abcLimit"), limit = config.abcLimit; end
validateattributes(budget,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(colonySize,{'numeric'},{'scalar','integer','>=',2,'finite'});
validateattributes(limit,{'numeric'},{'scalar','integer','positive','finite'});
assert(mod(colonySize,2) == 0,"runABC:ColonySize", ...
    "ABC populationSize must be even (half are food sources).");
nFood = colonySize/2;
assert(budget >= nFood,"runABC:InsufficientBudget", ...
    "ABC FE budget must cover all %d initial food sources.",nFood);
nvars = problem.nvars;
validateattributes(nvars,{'numeric'},{'scalar','integer','positive','finite'});
lb = double(problem.lb(:).');
ub = double(problem.ub(:).');
% The shared lunar formulation has one contiguous candidate set for each
% sensor, and only strict ordering constraints. Reject other formulations.
assert(numel(lb) == nvars && numel(ub) == nvars && ...
    all(lb == lb(1)) && all(ub == ub(1)) && ...
    isfinite(lb(1)) && isfinite(ub(1)) && ...
    lb(1) == round(lb(1)) && ub(1) == round(ub(1)) && ...
    ub(1)-lb(1)+1 >= nvars,"runABC:Bounds", ...
    "ABC requires common integer bounds with enough distinct candidate IDs.");
expectedA = zeros(max(0,nvars-1),nvars);
for k = 1:nvars-1, expectedA(k,k:k+1) = [1 -1]; end
assert((isempty(problem.A) || isequal(problem.A,expectedA)) && ...
    (isempty(problem.A) || isequal(problem.b(:),-ones(nvars-1,1))) && ...
    isempty(problem.Aeq) && isempty(problem.beq), ...
    "runABC:Constraints","ABC supports only strict sensor-ID ordering.");

foods = zeros(nFood,nvars);
for i = 1:nFood, foods(i,:) = randomNetwork(); end
trials = zeros(nFood,1);
fe = 0;
historyFe = zeros(0,1);
historyJ = zeros(0,1);
bestX = [];
bestJ = Inf;
iteration = 0;
costs = evaluate(foods);
record();

while fe < budget
    iteration = iteration+1;
    % Employed bees: one candidate for each food source.
    candidates = zeros(nFood,nvars);
    for i = 1:nFood, candidates(i,:) = neighbor(i); end
    values = evaluate(candidates);
    select((1:numel(values)).',candidates,values);
    record();
    if fe >= budget, break, end

    % Onlookers: shifted fitness works with either positive or negative J.
    fitness = zeros(nFood,1);
    valid = isfinite(costs) & costs < problem.infeasiblePenalty;
    if any(valid)
        fitness(valid) = 1./(1+max(costs(valid)-min(costs(valid)),0));
    else
        fitness(:) = 1;
    end
    cumulative = cumsum(fitness/sum(fitness));
    cumulative(end) = 1;
    parents = zeros(nFood,1);
    for j = 1:nFood
        parents(j) = find(rand <= cumulative,1);
        candidates(j,:) = neighbor(parents(j));
    end
    values = evaluate(candidates);
    select(parents(1:numel(values)),candidates,values);
    record();
    if fe >= budget, break, end

    % Scouts replace stagnated foods; the historical best is kept separately.
    scouts = find(trials >= limit);
    candidates = zeros(numel(scouts),nvars);
    for j = 1:numel(scouts), candidates(j,:) = randomNetwork(); end
    values = evaluate(candidates);
    for j = 1:numel(values)
        foods(scouts(j),:) = candidates(j,:);
        costs(scouts(j)) = values(j);
        trials(scouts(j)) = 0;
    end
    record();
end
assert(~isempty(bestX),"runABC:NoFeasibleNetwork", ...
    "ABC found no finite, non-penalty sensor network.");
output = struct("funccount",fe,"iterations",iteration, ...
    "message","Function evaluation budget reached.","algorithm","ABC");
result = struct("x",bestX(:),"fval",bestJ,"exitflag",0, ...
    "output",output,"functionEvaluations",fe, ...
    "solverFunctionEvaluations",fe, ...
    "history",struct("fe",historyFe,"bestJ",historyJ), ...
    "numberOfGenerations",iteration, ...
    "finalPopulation",foods,"finalScores",costs);

    function x = randomNetwork()
        x = sort(randperm(ub(1)-lb(1)+1,nvars)+lb(1)-1);
    end

    function v = neighbor(i)
        v = foods(i,:);
        dimension = randi(nvars);
        peer = randi(nFood);
        if rand < 0.5
            % Discrete difference move, followed by a global replacement if
            % rounding or collisions would leave the food unchanged.
            proposal = round(v(dimension)+(2*rand-1)* ...
                (v(dimension)-foods(peer,dimension)));
            proposal = max(lb(1),min(ub(1),proposal));
        else
            proposal = randi([lb(1),ub(1)]);
        end
        if ismember(proposal,v)
            % Sample an unused ID without allocating the full candidate set.
            occupied = sort(v-lb(1)+1);
            remaining = ub(1)-lb(1)+1-nvars;
            if remaining == 0, return, end
            rank = randi(remaining);
            for q = 1:nvars
                if occupied(q) <= rank, rank = rank+1; end
            end
            proposal = lb(1)+rank-1;
        end
        v(dimension) = proposal;
        v = sort(v);
    end

    function values = evaluate(points)
        count = min(size(points,1),budget-fe);
        values = zeros(count,1);
        if config.useParallel
            parfor row = 1:count
                values(row) = objectiveFcn(points(row,:));
            end
        else
            for row = 1:count
                values(row) = objectiveFcn(points(row,:));
            end
        end
        fe = fe+count;
        values(~isfinite(values)) = Inf;
        [candidateJ,index] = min(values);
        if ~isempty(candidateJ) && candidateJ < bestJ && ...
                candidateJ < problem.infeasiblePenalty
            bestJ = candidateJ;
            bestX = points(index,:);
        end
    end

    function select(parents,points,values)
        for row = 1:numel(values)
            i = parents(row);
            if values(row) < costs(i)
                foods(i,:) = points(row,:);
                costs(i) = values(row);
                trials(i) = 0;
            else
                trials(i) = trials(i)+1;
            end
        end
    end

    function record()
        if isempty(bestX), return, end
        if isempty(historyFe) || fe > historyFe(end)
            historyFe(end+1,1) = fe;
            historyJ(end+1,1) = bestJ;
            if strcmpi(config.display,"iter")
                fprintf("ABC | FE = %d/%d | bestJ = %.6g\n",fe,budget,bestJ);
            end
        end
    end
end

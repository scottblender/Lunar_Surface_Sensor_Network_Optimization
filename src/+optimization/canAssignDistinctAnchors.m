function [feasible,assignment] = canAssignDistinctAnchors(membership)
% CANASSIGNDISTINCTANCHORS - Bipartite matching, including overlapping circles.
membership = logical(membership);
owner = zeros(1,size(membership,2));
assignment = zeros(size(membership,1),1);
feasible = false;
for sensor = 1:size(membership,1)
    visited = false(1,size(membership,2));
    if ~augment(sensor), return; end
end
for anchor=1:numel(owner)
    if owner(anchor)>0, assignment(owner(anchor))=anchor; end
end
feasible = true;
    function found = augment(sensor)
        found = false;
        for anchor = find(membership(sensor,:))
            if visited(anchor), continue; end
            visited(anchor) = true;
            if owner(anchor)==0 || augment(owner(anchor))
                owner(anchor)=sensor; found=true; return;
            end
        end
    end
end

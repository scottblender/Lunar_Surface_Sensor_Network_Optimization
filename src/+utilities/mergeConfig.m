function output = mergeConfig(defaults,override)
% MERGECONFIG - Recursively merge scalar-struct configuration fields.

output = defaults;
fields = fieldnames(override);
for k = 1:numel(fields)
    name = fields{k};
    value = override.(name);
    if isfield(output,name) && isstruct(output.(name)) && ...
            isscalar(output.(name)) && isstruct(value) && isscalar(value)
        output.(name) = utilities.mergeConfig(output.(name),value);
    else
        output.(name) = value;
    end
end
end

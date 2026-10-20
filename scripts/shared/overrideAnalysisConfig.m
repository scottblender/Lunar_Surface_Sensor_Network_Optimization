function output = overrideAnalysisConfig(defaults,override)
% OVERRIDEANALYSISCONFIG - Apply top-level overrides, including new fields.

output = defaults;
fields = fieldnames(override);
for k = 1:numel(fields)
    output.(fields{k}) = override.(fields{k});
end
end

function tests = testAnalysisSetup
tests = functiontests(localfunctions);
end

function testAnalysisPathsAndConfigMerges(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root);
verifyEqual(testCase,setupProject(),root);
entries = {'database','buildProductionOptimizationDatabase'; ...
    'optimization','runGlobalOptimization'; ...
    'refinement','runDiscreteRadiusStudy'; ...
    'validation','validateOptimizationStudy'; ...
    'manuscript','generateManuscriptArtifacts'; ...
    'domain_comparison','generateDomainComparisonProducts'; ...
    'shared','publicationPlotStyle'};
for k = 1:size(entries,1)
    verifyEqual(testCase,which(entries{k,2}), ...
        fullfile(root,'scripts',entries{k,1},[entries{k,2} '.m']));
end
defaults = struct('a',1,'nested',struct('x',2,'y',3));
override = struct('nested',struct('x',4),'newField',5);
shallow = overrideAnalysisConfig(defaults,override);
deep = mergeAnalysisConfig(defaults,override);
verifyEqual(testCase,shallow.nested,struct('x',4));
verifyEqual(testCase,deep.nested,struct('x',4,'y',3));
verifyEqual(testCase,deep.newField,5);
verifyEqual(testCase,deep.a,1);
end

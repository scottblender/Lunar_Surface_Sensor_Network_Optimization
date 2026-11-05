function efficiency=plotGaObserverEfficiency(studyDirectory,independentRuns,options)
% PLOTGAOBSERVEREFFICIENCY - Print FE and the manuscript efficiency score.
% Equal weighting of normalized mean objective, mean runtime and mean IQR.
arguments
    studyDirectory (1,1) string
    independentRuns (1,1) double = Inf
    options.RequestedFE (1,:) double = []
end
report=loadGaObserverPlotData(studyDirectory,independentRuns,options.RequestedFE);
saved=load(fullfile(studyDirectory,"ga_convergence_study.mat"),"result");
summary=summarizeGaSearchSettings(report,saved.result.records);
efficiency=table(summary.Setting,summary.Efficiency,'VariableNames',{'FE','Efficiency'});
out=report.outputDirectory; if ~isfolder(out), mkdir(out); end
writetable(efficiency,fullfile(out,"fe_efficiency.csv"));
disp(efficiency);
end

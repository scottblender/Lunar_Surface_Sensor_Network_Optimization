function efficiency=plotGaObserverEfficiency(studyDirectory,independentRuns,options)
% PLOTGAOBSERVEREFFICIENCY - Print FE and marginal efficiency by FE budget.
% Mean relative improvement in objective and IQR per relative runtime increase.
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

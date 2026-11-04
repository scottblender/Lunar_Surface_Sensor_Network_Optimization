function plots=plotGaRunCountConvergence(studyDirectory,demFile,runCounts,options)
% PLOTGARUNCOUNTCONVERGENCE - Study 2 polar and boxplots across run counts.
% One fixed FE, one best-run reference from the largest selected prefix.
% Defaults to the saved config.runCounts; no optimization rerun is needed.
arguments
    studyDirectory (1,1) string
    demFile (1,1) string = ""
    runCounts (1,:) double = []
    options.RequestedFE (1,1) double = Inf
end
polar=plotGaLocationConvergence(studyDirectory,demFile,Inf, ...
    CompareBy="runs",RunCounts=runCounts,RequestedFE=options.RequestedFE);
spread=plotGaObserverSpread(studyDirectory,Inf, ...
    CompareBy="runs",RunCounts=runCounts,RequestedFE=options.RequestedFE);
plots=struct("outputDirectory",polar.outputDirectory,"polar",polar,"spread",spread);
end

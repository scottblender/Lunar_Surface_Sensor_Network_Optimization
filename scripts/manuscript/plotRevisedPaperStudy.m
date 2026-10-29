function plotRevisedPaperStudy(study)
% PLOTREVISEDPAPERSTUDY - Global random-network distributions and selected networks.
out=string(study.config.outputDirectory);
f=figure('Visible','off','Position',[100 100 1200 600]);
cleanup=onCleanup(@()close(f)); %#ok<NASGU>
hold on;
names=strings(numel(study.cases),1);
for k=1:numel(study.cases)
    current=study.cases{k}; names(k)=current.name;
    saved=load(fullfile(current.folder,"global_benchmark.mat"),"benchmark");
    values=saved.benchmark.objectives;
    boxchart(repmat(k,numel(values),1),values,'BoxFaceColor',[0.3 0.55 0.8]);
    scatter(repmat(k,numel(current.runObjectives),1),current.runObjectives,35,[0.65 0.25 0.15],'filled');
end
xticks(1:numel(names)); xticklabels(strrep(names,"_"," ")); xtickangle(25);
ylabel('Negative information gain (lower is better)');
title('Global random networks (boxes); selected networks (points)');
grid on;
exportgraphics(f,fullfile(out,"global_monte_carlo_comparison.png"),'Resolution',180);
exportgraphics(f,fullfile(out,"global_monte_carlo_comparison.pdf"),'ContentType','vector');
end

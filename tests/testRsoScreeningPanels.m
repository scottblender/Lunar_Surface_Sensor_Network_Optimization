function tests = testRsoScreeningPanels
tests = functiontests(localfunctions);
end

function testBothDomainsRetainAllTwentyRsos(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"scripts"));
full = repmat([50 10 5 5 5 25],20,1);
polar = repmat([60 5 5 5 5 20],20,1);
names = ["Horizon","Terrain","Earth","Sun","Earth + Sun","Accepted"];
fig = plotConstraintScreeningPanels(full,polar,names,lines(6),10,"information");
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
axesHandles = findall(fig,"Type","axes");
verifyNumElements(testCase,axesHandles,2);
for ax = axesHandles.'
    verifyEqual(testCase,ax.YTick,1:20);
    verifyEqual(testCase,string(ax.YTickLabel(:)),compose("RSO %02d",(1:20).'));
    verifyEqual(testCase,ax.XLim,[0 100]);
    bars = findall(ax,"Type","bar");
    verifyNumElements(testCase,bars,6);
    total = zeros(1,20);
    for bar = bars.'
        verifyNumElements(testCase,bar.YData,20);
        total = total+bar.YData(:).';
    end
    verifyEqual(testCase,total,100*ones(1,20));
end
end

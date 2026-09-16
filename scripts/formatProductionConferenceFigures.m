function report = formatProductionConferenceFigures(results,userConfig)
% FORMATPRODUCTIONCONFERENCEFIGURES Resize and re-export conference figures.
%
% The publication style intentionally uses large source-font sizes because
% the EPS files are reduced when placed in LaTeX. This post-processing step
% gives those fonts enough canvas area, prevents crowded axis ticks, and
% repairs annotations that otherwise overlap a tiled layout.
%
% Inputs
%   results    - output from runProductionConferenceResults up through the
%                production/per-RSO plotting stages
%   userConfig - optional structure; currently supports exportResolution
%
% Existing output filenames are overwritten intentionally so the repository
% maintains one canonical set of manuscript-ready figures.

arguments
    results (1,1) struct
    userConfig (1,1) struct = struct()
end

style = publicationPlotStyle();
config = struct();
config.exportResolution = 600;
config = mergeStruct(config,userConfig);

report = struct();
report.version = "conference_figure_format_v1";
report.formattedFiles = strings(0,1);

%% Single-axis vector figures
if isfield(results,"production")
    production = results.production;
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"convergence", ...
        [style.exportWidthInches style.exportHeightInches],"vector", ...
        config.exportResolution,true)];
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"meanObjective", ...
        [style.exportWidthInches style.exportHeightInches],"vector", ...
        config.exportResolution,false)];
    report.formattedFiles = [report.formattedFiles; ...
        formatFigureGroup(production,"objectiveDistributions", ...
        [style.exportWidthInches style.exportHeightInches],"vector", ...
        config.exportResolution,false)];

    %% DEM-backed 1x2 geometry
    if isfield(production,"geometry")
        report.formattedFiles = [report.formattedFiles; ...
            formatFigureGroup(production,"geometry", ...
            [style.wideFigureWidthInches style.wideFigureHeightInches], ...
            "image",config.exportResolution,false)];
    end

    %% 2x2 selection-frequency maps
    if isfield(production,"networkLocations")
        fields = fieldnames(production.networkLocations);
        for k = 1:numel(fields)
            entry = production.networkLocations.(fields{k});
            if ~isfield(entry,"figure") || ~isgraphics(entry.figure)
                continue
            end
            fig = entry.figure;
            setFigureCanvas(fig,style.gridFigureWidthInches, ...
                style.gridFigureHeightInches);

            % The original long sentence became crowded when the manuscript
            % font was enlarged. Keep the same meaning in a shorter caption-
            % style annotation and give it a wider text box. Search by the
            % String property rather than a graphics-class name so this works
            % consistently across MATLAB releases.
            stringObjects = findall(fig,"-property","String");
            for j = 1:numel(stringObjects)
                try
                    currentText = string(stringObjects(j).String);
                    if any(contains(currentText,"selection frequency", ...
                            "IgnoreCase",true))
                        stringObjects(j).String = ...
                            "Marker size \propto selection frequency";
                        if isprop(stringObjects(j),"Interpreter")
                            stringObjects(j).Interpreter = "tex";
                        end
                        if isprop(stringObjects(j),"FontName")
                            stringObjects(j).FontName = style.fontName;
                        end
                        if isprop(stringObjects(j),"FontSize")
                            stringObjects(j).FontSize = style.annotationFontSize;
                        end
                        if isprop(stringObjects(j),"FontWeight")
                            stringObjects(j).FontWeight = "bold";
                        end
                        if isprop(stringObjects(j),"Position")
                            stringObjects(j).Position = [0.14 0.006 0.72 0.05];
                        end
                    end
                catch
                end
            end

            drawnow;
            outputFile = string(entry.outputFile);
            exportgraphics(fig,outputFile,"ContentType","image", ...
                "Resolution",config.exportResolution, ...
                "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
            report.formattedFiles(end+1,1) = outputFile; %#ok<AGROW>
        end
    end
end

%% Per-RSO heatmaps
if isfield(results,"perRsoEkf")
    heatmaps = results.perRsoEkf;
    if isfield(heatmaps,"positionRmseFigure") && ...
            isgraphics(heatmaps.positionRmseFigure)
        setFigureCanvas(heatmaps.positionRmseFigure, ...
            style.heatmapWidthInches,style.heatmapHeightInches);
        drawnow;
        exportgraphics(heatmaps.positionRmseFigure, ...
            heatmaps.positionRmseOutputFile,"ContentType","image", ...
            "Resolution",config.exportResolution, ...
            "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
        report.formattedFiles(end+1,1) = ...
            string(heatmaps.positionRmseOutputFile); %#ok<AGROW>
    end

    if isfield(heatmaps,"measurementAvailabilityFigure") && ...
            isgraphics(heatmaps.measurementAvailabilityFigure)
        setFigureCanvas(heatmaps.measurementAvailabilityFigure, ...
            style.heatmapWidthInches,style.heatmapHeightInches);
        drawnow;
        exportgraphics(heatmaps.measurementAvailabilityFigure, ...
            heatmaps.measurementAvailabilityOutputFile,"ContentType","image", ...
            "Resolution",config.exportResolution, ...
            "BackgroundColor",style.backgroundColor,"Colorspace","rgb");
        report.formattedFiles(end+1,1) = ...
            string(heatmaps.measurementAvailabilityOutputFile); %#ok<AGROW>
    end
end

fprintf("\nReformatted %d conference figure files for large LaTeX typography.\n", ...
    numel(report.formattedFiles));

end

%% ------------------------------------------------------------------------
function files = formatFigureGroup(parent,fieldName,canvasSize,contentType, ...
    resolution,fixConvergenceTicks)
files = strings(0,1);
if ~isfield(parent,fieldName)
    return
end
group = parent.(fieldName);
fields = fieldnames(group);
for k = 1:numel(fields)
    entry = group.(fields{k});
    if ~isfield(entry,"figure") || ~isgraphics(entry.figure)
        continue
    end
    fig = entry.figure;
    setFigureCanvas(fig,canvasSize(1),canvasSize(2));

    if fixConvergenceTicks
        axesHandles = findall(fig,"Type","axes");
        for j = 1:numel(axesHandles)
            ax = axesHandles(j);
            limits = xlim(ax);
            if all(isfinite(limits)) && limits(2) > limits(1)
                ticks = linspace(limits(1),limits(2),5);
                ax.XTick = ticks;
                ax.XTickLabel = compose("%.0f",ticks);
            end
        end
    end

    drawnow;
    outputFile = string(entry.outputFile);
    if contentType == "vector"
        exportgraphics(fig,outputFile,"ContentType","vector", ...
            "BackgroundColor","white","Colorspace","rgb");
    else
        exportgraphics(fig,outputFile,"ContentType","image", ...
            "Resolution",resolution,"BackgroundColor","white", ...
            "Colorspace","rgb");
    end
    files(end+1,1) = outputFile; %#ok<AGROW>
end
end

function setFigureCanvas(fig,widthInches,heightInches)
fig.Units = "inches";
position = fig.Position;
fig.Position = [position(1:2) widthInches heightInches];
fig.PaperUnits = "inches";
fig.PaperSize = [widthInches heightInches];
fig.PaperPosition = [0 0 widthInches heightInches];
fig.PaperPositionMode = "manual";
end

function output = mergeStruct(defaults,override)
output = defaults;
fields = fieldnames(override);
for k = 1:numel(fields)
    output.(fields{k}) = override.(fields{k});
end
end

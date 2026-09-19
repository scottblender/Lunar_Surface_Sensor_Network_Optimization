function outputFile = writeOptimizationWorkflowTikz(userConfig)
% WRITEOPTIMIZATIONWORKFLOWTIKZ Write the manuscript optimization workflow.
%
% This is kept synchronized with the current AAS manuscript source. The
% workflow is a process diagram rather than a numerical MATLAB figure.

arguments
    userConfig (1,1) struct = struct()
end

scriptDirectory=fileparts(mfilename("fullpath"));
projectRoot=fileparts(scriptDirectory);
outputDirectory=fullfile(projectRoot,"results","manuscript_artifacts");
if isfield(userConfig,"outputDirectory")
    outputDirectory=string(userConfig.outputDirectory);
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end

outputFile=fullfile(outputDirectory,"optimization_workflow.tex");
fid=fopen(outputFile,"w");
assert(fid>=0,"Could not open optimization workflow output file.");
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>

lines = [
"\begin{figure}[htbp]"
"    \centering"
"    \begin{tikzpicture}["
"        font=\footnotesize,"
"        >=Latex,"
"        pre/.style={"
"            draw,"
"            rounded corners=1.2pt,"
"            align=center,"
"            minimum height=10.5mm,"
"            text width=29mm,"
"            inner sep=2pt"
"        },"
"        search/.style={"
"            draw,"
"            rounded corners=1.2pt,"
"            align=center,"
"            minimum height=10mm,"
"            text width=30mm,"
"            inner sep=2pt"
"        },"
"        db/.style={"
"            draw,"
"            rounded corners=1.2pt,"
"            align=center,"
"            minimum height=10.5mm,"
"            text width=29mm,"
"            inner sep=2pt,"
"            very thick"
"        },"
"        decision/.style={"
"            draw,"
"            diamond,"
"            aspect=2.05,"
"            align=center,"
"            inner sep=1pt,"
"            text width=21mm"
"        },"
"        line/.style={->, thick}"
"    ]"
""
"    % Precomputation"
"    \node[font=\bfseries, anchor=west] at (-1.20,0.95) {Precomputation};"
"    \node[pre] (terrain) at (0,0) {Lunar DEM and\\candidate grid};"
"    \node[pre] (rso) at (3.80,0) {RSO population and\\orbit propagation};"
"    \node[pre, text width=34mm] (precompute) at (7.60,0)"
"        {Visibility, measurement,\\IOD, and estimation\\precomputation};"
"    \node[db] (database) at (11.40,0) {Frozen optimization\\database};"
""
"    \draw[line] (terrain.east) -- (rso.west);"
"    \draw[line] (rso.east) -- (precompute.west);"
"    \draw[line] (precompute.east) -- (database.west);"
""
"    % Genetic-algorithm search: first row"
"    \node[font=\bfseries, anchor=west] at (-1.20,-1.25) {Genetic-algorithm search};"
"    \node[search] (config) at (0,-2.15) {Define $N_s$, objective,\\and FE budget};"
"    \node[search] (init) at (3.80,-2.15) {Initialize integer-feasible\\GA population};"
"    \node[search] (candidate) at (7.60,-2.15) {Generate candidate\\network $\mathbf{x}$};"
"    \node[search] (retrieve) at (11.40,-2.15) {Retrieve selected-site\\data};"
""
"    \draw[line] (config.east) -- (init.west);"
"    \draw[line] (init.east) -- (candidate.west);"
"    \draw[line] (candidate.east) -- (retrieve.west);"
"    \draw[line] (database.south) -- (retrieve.north);"
""
"    % Genetic-algorithm search: second row"
"    \node[search] (objective) at (0,-4.35) {Evaluate coverage or\\information cost};"
"    \node[search] (update) at (3.80,-4.35) {Update population and\\best-so-far incumbent};"
"    \node[decision] (stop) at (8.00,-4.35) {FE budget\\reached?};"
"    \node[search] (result) at (11.80,-4.35) {Return best feasible\\sensor network};"
""
"    % Selected-site data feed and shared return junction"
"    \coordinate (retrieveTurn) at (11.40,-3.25);"
"    \coordinate (candidateJunction) at (7.60,-3.25);"
"    \coordinate (objectiveTurn) at (0,-3.25);"
""
"    \draw[line]"
"        (retrieve.south)"
"        -- (retrieveTurn)"
"        -- (candidateJunction)"
"        -- (objectiveTurn)"
"        -- (objective.north);"
""
"    \draw[line] (candidateJunction) -- (candidate.south);"
""
"    % Continue-search branch; only the shared upward segment carries an arrowhead."
"    \coordinate (loopbottom) at ($(stop.south)+(0,-7mm)$);"
"    \coordinate (loopleft) at ($(loopbottom)+(-18mm,0)$);"
"    \draw[thick]"
"        (stop.south)"
"        -- (loopbottom)"
"        -- (loopleft)"
"        |- (candidateJunction);"
""
"    \node[font=\scriptsize, fill=white, inner sep=0.8pt]"
"        at ($(loopbottom)!0.50!(loopleft)+(0,-3.0mm)$) {No};"
""
"    % Main optimization path"
"    \draw[line] (objective.east) -- (update.west);"
"    \draw["
"        line,"
"        preaction={draw=white,line width=3.2pt,-}"
"    ] (update.east) -- (stop.west);"
"    \draw[line] (stop.east) -- (result.west);"
""
"    \node[font=\scriptsize, fill=white, inner sep=0.8pt]"
"        at ($(stop.east)!0.50!(result.west)+(-0.15,4.3mm)$) {Yes};"
""
"    \end{tikzpicture}"
"    \caption{Lunar-surface sensor-network optimization workflow.}"
"    \label{fig:optimization_workflow}"
"\end{figure}"
];

for lineIndex=1:numel(lines)
    fprintf(fid,"%s\n",lines(lineIndex));
end
end

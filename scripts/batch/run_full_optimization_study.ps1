# ---------------- run_full_optimization_study.ps1 ----------------
param(
    [string]$MatlabExe = "",
    [int]$EvalBudget = 6000,
    [int]$NumberOfRuns = 20,
    [int]$BaseSeed = 1000
)

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------------
# Project paths
# -------------------------------------------------------------------------

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RunnerFile = Join-Path $ProjectRoot "scripts\runGlobalOptimization.m"

if (-not (Test-Path $RunnerFile)) {
    throw "Cannot find runGlobalOptimization.m at: $RunnerFile"
}

# -------------------------------------------------------------------------
# MATLAB executable
# -------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($MatlabExe)) {

    $matlabCommand = Get-Command matlab.exe -ErrorAction SilentlyContinue

    if ($matlabCommand) {
        $MatlabExe = $matlabCommand.Source
    }
    else {
        $MatlabExe = "C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
    }
}

if (-not (Test-Path $MatlabExe)) {
    throw "Cannot find matlab.exe. Pass -MatlabExe or add MATLAB to PATH."
}

# -------------------------------------------------------------------------
# Validate study configuration
# -------------------------------------------------------------------------

$PopulationSize = 60

if ($EvalBudget -lt $PopulationSize -or
    ($EvalBudget % $PopulationSize) -ne 0) {

    throw "EvalBudget must be a positive multiple of $PopulationSize."
}

if ($NumberOfRuns -lt 1) {
    throw "NumberOfRuns must be at least 1."
}

if ($BaseSeed -lt 0) {
    throw "BaseSeed must be nonnegative."
}

# -------------------------------------------------------------------------
# Study definition
# -------------------------------------------------------------------------

$NetworkSizes = @(3, 5, 7, 10)
$Objectives = @("information", "coverage")

$TotalCases = $NetworkSizes.Count * $Objectives.Count
$CompletedCases = 0

# -------------------------------------------------------------------------
# Batch logs
# -------------------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$LogRoot = Join-Path `
    (Join-Path $ProjectRoot "results") `
    "batch_logs\production_$Timestamp"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

function Format-TimeSpan {
    param(
        [double]$Seconds
    )

    if ($Seconds -lt 0) {
        return "--:--:--"
    }

    $timeSpan = [TimeSpan]::FromSeconds($Seconds)

    return "{0:00}:{1:00}:{2:00}" -f `
        [math]::Floor($timeSpan.TotalHours), `
        $timeSpan.Minutes, `
        $timeSpan.Seconds
}

function Invoke-LunarOptimization {
    param(
        [int]$NetworkSize,
        [string]$Objective
    )

    $caseName = "ga_$($Objective)_n$NetworkSize"

    $stdoutLog = Join-Path $LogRoot "$caseName.stdout.log"
    $stderrLog = Join-Path $LogRoot "$caseName.stderr.log"
    $consoleLog = Join-Path $LogRoot "$caseName.log"

    $projectRootMatlab = $ProjectRoot.Replace("'", "''")

    # Use MATLAB character-vector literals here rather than double-quoted
    # MATLAB strings. Start-Process may remove embedded double quotes while
    # assembling the -batch command line, which would turn information into
    # an unresolved MATLAB variable instead of the intended string value.
    $matlabCommand = @"
cd('$projectRootMatlab');
addpath('scripts');

config = struct();
config.networkSize = $NetworkSize;
config.objectiveMode = '$Objective';
config.functionEvaluationBudget = $EvalBudget;
config.populationSize = $PopulationSize;
config.numberOfRuns = $NumberOfRuns;
config.baseSeed = $BaseSeed;

config.useParallel = true;
config.parallelRestartEachRun = false;
config.parallelRetryOnFailure = true;
config.closeParallelPoolAtEnd = true;
config.useParallelDatabaseConstant = true;

config.display = 'iter';

studyState = runGlobalOptimization(config);
"@

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Starting production case"
    Write-Host "============================================================"
    Write-Host "Network size:    $NetworkSize"
    Write-Host "Objective:       $Objective"
    Write-Host "FE budget/run:   $EvalBudget"
    Write-Host "Runs:            $NumberOfRuns"
    Write-Host "Base seed:       $BaseSeed"
    Write-Host ""

    try {

        $process = Start-Process `
            -FilePath $MatlabExe `
            -ArgumentList @(
                "-batch",
                "`"$matlabCommand`""
            ) `
            -WorkingDirectory $ProjectRoot `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -NoNewWindow `
            -Wait `
            -PassThru

        $matlabExitCode = $process.ExitCode

        if (Test-Path $consoleLog) {
            Remove-Item $consoleLog -Force
        }

        if (Test-Path $stdoutLog) {
            Get-Content $stdoutLog | Add-Content $consoleLog
            Get-Content $stdoutLog
        }

        if (Test-Path $stderrLog) {
            Get-Content $stderrLog | Add-Content $consoleLog

            $stderrContent = Get-Content $stderrLog

            if ($stderrContent) {
                $stderrContent | Write-Host
            }
        }

        if ($matlabExitCode -ne 0) {

            throw `
                "MATLAB failed for Ns=$NetworkSize, objective=$Objective " +
                "with exit code $matlabExitCode. See: $consoleLog"
        }
    }
    finally {

        Remove-Item `
            $stdoutLog `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-Item `
            $stderrLog `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Completed -> Ns=$NetworkSize | $Objective"
    Write-Host "Log       -> $consoleLog"
}

# -------------------------------------------------------------------------
# Run production study
# -------------------------------------------------------------------------

$StudyTimer = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($NetworkSize in $NetworkSizes) {

    foreach ($Objective in $Objectives) {

        $CurrentCase = $CompletedCases + 1

        if ($CompletedCases -gt 0) {

            $AverageCaseSeconds = `
                $StudyTimer.Elapsed.TotalSeconds / $CompletedCases

            $RemainingCases = `
                $TotalCases - $CompletedCases

            $EstimatedRemainingSeconds = `
                $AverageCaseSeconds * $RemainingCases

            $EtaText = `
                Format-TimeSpan $EstimatedRemainingSeconds
        }
        else {
            $EtaText = "calculating..."
        }

        $PercentComplete = `
            [math]::Round(
                100 * $CompletedCases / $TotalCases,
                1
            )

        $status = `
            "Case $CurrentCase of $TotalCases | " +
            "Ns=$NetworkSize | $Objective | ETA $EtaText"

        Write-Progress `
            -Activity "Lunar surface optimization study" `
            -Status $status `
            -PercentComplete $PercentComplete

        Invoke-LunarOptimization `
            -NetworkSize $NetworkSize `
            -Objective $Objective

        $CompletedCases++

        $AverageCaseSeconds = `
            $StudyTimer.Elapsed.TotalSeconds / $CompletedCases

        $RemainingCases = `
            $TotalCases - $CompletedCases

        $EstimatedRemainingSeconds = `
            $AverageCaseSeconds * $RemainingCases

        $PercentComplete = `
            [math]::Round(
                100 * $CompletedCases / $TotalCases,
                1
            )

        $status = `
            "$CompletedCases of $TotalCases complete | " +
            "ETA $(Format-TimeSpan $EstimatedRemainingSeconds)"

        Write-Progress `
            -Activity "Lunar surface optimization study" `
            -Status $status `
            -PercentComplete $PercentComplete
    }
}

$StudyTimer.Stop()

Write-Progress `
    -Activity "Lunar surface optimization study" `
    -Completed

# -------------------------------------------------------------------------
# Final summary
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "Production optimization study complete"
Write-Host "============================================================"
Write-Host "Network sizes:      $($NetworkSizes -join ', ')"
Write-Host "Objectives:         $($Objectives -join ', ')"
Write-Host "FE budget / run:    $EvalBudget"
Write-Host "Runs / case:        $NumberOfRuns"
Write-Host "Total cases:        $TotalCases"
Write-Host "Total runtime:      $(Format-TimeSpan $StudyTimer.Elapsed.TotalSeconds)"
Write-Host "Batch logs:"
Write-Host "  $LogRoot"
Write-Host ""
# -------------------------------------------------------------------------

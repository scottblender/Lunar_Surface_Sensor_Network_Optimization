# ---------------- run_full_optimization_study.ps1 ----------------
param(
    [string]$MatlabExe = "",
    [int]$EvalBudget = 6000,
    [int]$NumberOfRuns = 20,
    [int]$BaseSeed = 1000,
    [int]$ParallelWorkers = 7,
    [int]$StartCase = 1
)

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------------
# Project paths
# -------------------------------------------------------------------------

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RunnerFile = Join-Path $ProjectRoot "scripts\runGlobalOptimization.m"
$BatchEntry = Join-Path $ProjectRoot "scripts\batch\run_lunar_batch_entry.m"

if (-not (Test-Path $RunnerFile)) {
    throw "Cannot find runGlobalOptimization.m at: $RunnerFile"
}

if (-not (Test-Path $BatchEntry)) {
    throw "Cannot find MATLAB batch entry at: $BatchEntry"
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

if ($ParallelWorkers -lt 1) {
    throw "ParallelWorkers must be at least 1."
}

# -------------------------------------------------------------------------
# Study definition
# -------------------------------------------------------------------------

$NetworkSizes = @(3, 5, 7, 10)
$Objectives = @("information", "coverage")

$Cases = @()
foreach ($NetworkSize in $NetworkSizes) {
    foreach ($Objective in $Objectives) {
        $Cases += [PSCustomObject]@{
            NetworkSize = $NetworkSize
            Objective = $Objective
        }
    }
}

$TotalCases = $Cases.Count

if ($StartCase -lt 1 -or $StartCase -gt $TotalCases) {
    throw "StartCase must be between 1 and $TotalCases."
}

$CasesToRun = @($Cases[($StartCase - 1)..($TotalCases - 1)])
$TotalScheduledCases = $CasesToRun.Count
$TotalScheduledRuns = $TotalScheduledCases * $NumberOfRuns
$CompletedScheduledRuns = 0

# -------------------------------------------------------------------------
# Batch logs
# -------------------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot = Join-Path `
    (Join-Path $ProjectRoot "results") `
    "batch_logs\production_$Timestamp"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$BatchEntryMatlab = $BatchEntry.Replace("'", "''")

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

function Format-TimeSpan {
    param([double]$Seconds)

    if ($Seconds -lt 0) {
        return "--:--:--"
    }

    $timeSpan = [TimeSpan]::FromSeconds($Seconds)

    return "{0:00}:{1:00}:{2:00}" -f `
        [math]::Floor($timeSpan.TotalHours), `
        $timeSpan.Minutes, `
        $timeSpan.Seconds
}

function Update-StudyProgress {
    param(
        [int]$AbsoluteCase,
        [int]$RunInCase,
        [int]$NetworkSize,
        [string]$Objective
    )

    if ($script:CompletedScheduledRuns -gt 0) {
        $averageRunSeconds = `
            $script:StudyTimer.Elapsed.TotalSeconds / `
            $script:CompletedScheduledRuns

        $remainingRuns = `
            $script:TotalScheduledRuns - `
            $script:CompletedScheduledRuns

        $estimatedRemainingSeconds = `
            $averageRunSeconds * $remainingRuns

        $etaText = Format-TimeSpan $estimatedRemainingSeconds
    }
    else {
        $etaText = "calculating..."
    }

    $percentComplete = [math]::Round(
        100 * $script:CompletedScheduledRuns / `
        $script:TotalScheduledRuns,
        1
    )

    $seed = $script:BaseSeed + $RunInCase - 1

    $status = `
        "$($script:CompletedScheduledRuns) of $($script:TotalScheduledRuns) runs | " +
        "case $AbsoluteCase of $($script:TotalCases) | " +
        "Ns=$NetworkSize | $Objective | seed $seed | ETA $etaText"

    Write-Progress `
        -Activity "Lunar surface optimization study" `
        -Status $status `
        -PercentComplete $percentComplete
}

function Invoke-LunarOptimization {
    param(
        [int]$NetworkSize,
        [string]$Objective,
        [int]$AbsoluteCase,
        [int]$ScheduledCaseIndex
    )

    $caseName = "ga_$($Objective)_n$NetworkSize"
    $consoleLog = Join-Path $LogRoot "$caseName.log"

    if (Test-Path $consoleLog) {
        Remove-Item $consoleLog -Force
    }

    # Match the proven batch-runner structure from the cislunar study:
    # PowerShell supplies configuration through environment variables and
    # MATLAB executes one stable batch-entry script for the whole case.
    $env:PROJECT_ROOT = $ProjectRoot
    $env:NETWORK_SIZE = "$NetworkSize"
    $env:OBJECTIVE_MODE = $Objective
    $env:EVAL_BUDGET = "$EvalBudget"
    $env:POPULATION_SIZE = "$PopulationSize"
    $env:NUMBER_OF_RUNS = "$NumberOfRuns"
    $env:BASE_SEED = "$BaseSeed"
    $env:PARALLEL_WORKERS = "$ParallelWorkers"

    $batchCommand = "run('$BatchEntryMatlab')"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Starting production case $AbsoluteCase of $TotalCases"
    Write-Host "============================================================"
    Write-Host "Network size:      $NetworkSize"
    Write-Host "Objective:         $Objective"
    Write-Host "FE budget/run:     $EvalBudget"
    Write-Host "Runs:              $NumberOfRuns"
    Write-Host "Seeds:             $BaseSeed-$($BaseSeed + $NumberOfRuns - 1)"
    Write-Host "Parallel workers:  $ParallelWorkers"
    Write-Host "Log:               $consoleLog"
    Write-Host ""

    $caseRunOffset = ($ScheduledCaseIndex - 1) * $NumberOfRuns
    $lastReportedRun = 0

    # Stream MATLAB output through PowerShell rather than waiting silently
    # for all 20 runs in a case. Full output is retained in the case log;
    # the console only shows useful run/case milestones.
    & $MatlabExe -batch $batchCommand 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Add-Content -Path $consoleLog -Value $line -Encoding UTF8

        if ($line -match '^\s*Run\s+(\d+)\s+complete\s*$') {
            $runInCase = [int]$Matches[1]

            if ($runInCase -gt $lastReportedRun) {
                $lastReportedRun = $runInCase
                $script:CompletedScheduledRuns = `
                    $caseRunOffset + $runInCase

                Update-StudyProgress `
                    -AbsoluteCase $AbsoluteCase `
                    -RunInCase $runInCase `
                    -NetworkSize $NetworkSize `
                    -Objective $Objective

                Write-Host `
                    "Completed run $runInCase of $NumberOfRuns " +
                    "for Ns=$NetworkSize | $Objective"
            }
        }
        elseif (
            $line -match '^Starting process pool' -or
            $line -match '^Parallel pool ready' -or
            $line -match '^Global optimization study complete' -or
            $line -match '^Results saved to:' -or
            $line -match '^Shutting down parallel pool' -or
            $line -match '^Parallel pool shut down successfully' -or
            $line -match '^Error using ' -or
            $line -match '^Caused by:' -or
            $line -match '^ERROR:'
        ) {
            Write-Host $line
        }
    }

    $matlabExitCode = $LASTEXITCODE

    if ($matlabExitCode -ne 0) {
        throw `
            "MATLAB failed for Ns=$NetworkSize, objective=$Objective " +
            "with exit code $matlabExitCode. See: $consoleLog"
    }

    if ($lastReportedRun -ne $NumberOfRuns) {
        throw `
            "MATLAB exited successfully, but only $lastReportedRun of " +
            "$NumberOfRuns run completions were observed. See: $consoleLog"
    }

    $script:CompletedScheduledRuns = `
        $caseRunOffset + $NumberOfRuns

    Update-StudyProgress `
        -AbsoluteCase $AbsoluteCase `
        -RunInCase $NumberOfRuns `
        -NetworkSize $NetworkSize `
        -Objective $Objective

    Write-Host ""
    Write-Host "Completed case -> Ns=$NetworkSize | $Objective"
    Write-Host "Log            -> $consoleLog"
}

# -------------------------------------------------------------------------
# Run production study
# -------------------------------------------------------------------------

$script:StudyTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:TotalScheduledRuns = $TotalScheduledRuns
$script:TotalCases = $TotalCases
$script:BaseSeed = $BaseSeed
$script:CompletedScheduledRuns = 0

$ScheduledCaseIndex = 0

foreach ($Case in $CasesToRun) {
    $ScheduledCaseIndex++

    $NetworkSize = $Case.NetworkSize
    $Objective = $Case.Objective
    $AbsoluteCase = $StartCase + $ScheduledCaseIndex - 1

    Update-StudyProgress `
        -AbsoluteCase $AbsoluteCase `
        -RunInCase 1 `
        -NetworkSize $NetworkSize `
        -Objective $Objective

    Invoke-LunarOptimization `
        -NetworkSize $NetworkSize `
        -Objective $Objective `
        -AbsoluteCase $AbsoluteCase `
        -ScheduledCaseIndex $ScheduledCaseIndex
}

$script:StudyTimer.Stop()

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
Write-Host "Parallel workers:   $ParallelWorkers"
Write-Host "Started at case:    $StartCase of $TotalCases"
Write-Host "Cases this launch:  $TotalScheduledCases"
Write-Host "Runs this launch:   $TotalScheduledRuns"
Write-Host "Total runtime:      $(Format-TimeSpan $script:StudyTimer.Elapsed.TotalSeconds)"
Write-Host "Batch logs:"
Write-Host "  $LogRoot"
Write-Host ""
# -------------------------------------------------------------------------

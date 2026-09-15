# ---------------- run_full_optimization_study.ps1 ----------------
param(
    [string]$MatlabExe = "",
    [int]$EvalBudget = 6000,
    [int]$NumberOfRuns = 20,
    [int]$BaseSeed = 1000,
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
$TotalScheduledRuns = $CasesToRun.Count * $NumberOfRuns
$CompletedRuns = 0

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
        [string]$Objective,
        [int]$Seed
    )

    if ($script:CompletedRuns -gt 0) {
        $averageRunSeconds = `
            $script:StudyTimer.Elapsed.TotalSeconds / $script:CompletedRuns

        $remainingRuns = `
            $script:TotalScheduledRuns - $script:CompletedRuns

        $etaText = Format-TimeSpan ($averageRunSeconds * $remainingRuns)
    }
    else {
        $etaText = "calculating..."
    }

    $percentComplete = [math]::Round(
        100 * $script:CompletedRuns / $script:TotalScheduledRuns,
        1
    )

    $status = `
        "$($script:CompletedRuns) of $($script:TotalScheduledRuns) runs | " +
        "case $AbsoluteCase of $($script:TotalCases) | " +
        "run $RunInCase of $NumberOfRuns | " +
        "Ns=$NetworkSize | $Objective | seed $Seed | ETA $etaText"

    Write-Progress `
        -Activity "Lunar surface optimization study" `
        -Status $status `
        -PercentComplete $percentComplete
}

function Invoke-LunarOptimizationRun {
    param(
        [int]$NetworkSize,
        [string]$Objective,
        [int]$Seed,
        [int]$RunInCase,
        [int]$AbsoluteCase
    )

    $seedCode = $Seed.ToString("0000")
    $runName = "ga_$($Objective)_n$($NetworkSize)_seed$seedCode"

    $stdoutLog = Join-Path $LogRoot "$runName.stdout.log"
    $stderrLog = Join-Path $LogRoot "$runName.stderr.log"
    $consoleLog = Join-Path $LogRoot "$runName.log"

    $env:PROJECT_ROOT = $ProjectRoot
    $env:NETWORK_SIZE = "$NetworkSize"
    $env:OBJECTIVE_MODE = $Objective
    $env:EVAL_BUDGET = "$EvalBudget"
    $env:POPULATION_SIZE = "$PopulationSize"
    $env:BASE_SEED = "$Seed"

    $batchCommand = "run('$BatchEntryMatlab')"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Case $AbsoluteCase of $TotalCases | Run $RunInCase of $NumberOfRuns"
    Write-Host "============================================================"
    Write-Host "Network size:   $NetworkSize"
    Write-Host "Objective:      $Objective"
    Write-Host "Seed:           $Seed"
    Write-Host "FE budget:      $EvalBudget"
    Write-Host ""

    try {
        $process = Start-Process `
            -FilePath $MatlabExe `
            -ArgumentList @("-batch", "`"$batchCommand`"") `
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
        }

        if (Test-Path $stderrLog) {
            Get-Content $stderrLog | Add-Content $consoleLog
        }

        if ($matlabExitCode -ne 0) {
            Write-Host ""
            Write-Host "MATLAB failed. Last log lines:"
            if (Test-Path $consoleLog) {
                Get-Content $consoleLog -Tail 40 | ForEach-Object { Write-Host $_ }
            }

            throw `
                "MATLAB failed for Ns=$NetworkSize, objective=$Objective, " +
                "seed=$Seed with exit code $matlabExitCode. See: $consoleLog"
        }
    }
    finally {
        Remove-Item $stdoutLog -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrLog -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Completed -> Ns=$NetworkSize | $Objective | seed $Seed"
    Write-Host "Log       -> $consoleLog"
}

# -------------------------------------------------------------------------
# Run production study
# -------------------------------------------------------------------------

$script:StudyTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:TotalScheduledRuns = $TotalScheduledRuns
$script:TotalCases = $TotalCases
$script:CompletedRuns = 0

$ScheduledCaseIndex = 0

foreach ($Case in $CasesToRun) {
    $ScheduledCaseIndex++

    $NetworkSize = $Case.NetworkSize
    $Objective = $Case.Objective
    $AbsoluteCase = $StartCase + $ScheduledCaseIndex - 1

    for ($RunInCase = 1; $RunInCase -le $NumberOfRuns; $RunInCase++) {
        $Seed = $BaseSeed + $RunInCase - 1

        Update-StudyProgress `
            -AbsoluteCase $AbsoluteCase `
            -RunInCase $RunInCase `
            -NetworkSize $NetworkSize `
            -Objective $Objective `
            -Seed $Seed

        Invoke-LunarOptimizationRun `
            -NetworkSize $NetworkSize `
            -Objective $Objective `
            -Seed $Seed `
            -RunInCase $RunInCase `
            -AbsoluteCase $AbsoluteCase

        $script:CompletedRuns++

        Update-StudyProgress `
            -AbsoluteCase $AbsoluteCase `
            -RunInCase $RunInCase `
            -NetworkSize $NetworkSize `
            -Objective $Objective `
            -Seed $Seed
    }
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
Write-Host "Seeds / case:       $BaseSeed-$($BaseSeed + $NumberOfRuns - 1)"
Write-Host "Started at case:    $StartCase of $TotalCases"
Write-Host "Runs this launch:   $TotalScheduledRuns"
Write-Host "Total runtime:      $(Format-TimeSpan $script:StudyTimer.Elapsed.TotalSeconds)"
Write-Host "Batch logs:"
Write-Host "  $LogRoot"
Write-Host ""
# -------------------------------------------------------------------------

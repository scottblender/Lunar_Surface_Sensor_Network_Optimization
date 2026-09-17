# ---------------- run_full_optimization_study.ps1 ----------------
param(
    [string]$MatlabExe = "",
    [int]$EvalBudget = 12000,
    [int]$NumberOfRuns = 20,
    [int]$BaseSeed = 1000,
    [int]$ParallelWorkers = 7,
    [int]$StartCase = 1
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RunnerFile = Join-Path $ProjectRoot "scripts\runGlobalOptimization.m"
$BatchEntry = Join-Path $ProjectRoot "scripts\batch\run_lunar_batch_entry.m"

if (-not (Test-Path $RunnerFile)) {
    throw "Cannot find runGlobalOptimization.m at: $RunnerFile"
}
if (-not (Test-Path $BatchEntry)) {
    throw "Cannot find MATLAB batch entry at: $BatchEntry"
}

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

$PopulationSize = 60
$NetworkSizes = @(3, 5, 7, 10)
$Objectives = @("information", "coverage")
$TotalCases = $NetworkSizes.Count * $Objectives.Count

if ($EvalBudget -lt $PopulationSize -or ($EvalBudget % $PopulationSize) -ne 0) {
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
if ($StartCase -lt 1 -or $StartCase -gt $TotalCases) {
    throw "StartCase must be between 1 and $TotalCases."
}

$CasesThisLaunch = $TotalCases - $StartCase + 1
$TotalScheduledRuns = $CasesThisLaunch * $NumberOfRuns

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot = Join-Path (Join-Path $ProjectRoot "results") "batch_logs\production_$Timestamp"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$stdoutLog = Join-Path $LogRoot "full_study.stdout.log"
$stderrLog = Join-Path $LogRoot "full_study.stderr.log"
$consoleLog = Join-Path $LogRoot "full_study.log"

$BatchEntryMatlab = $BatchEntry.Replace("'", "''")
$batchCommand = "run('$BatchEntryMatlab')"

$env:PROJECT_ROOT = $ProjectRoot
$env:EVAL_BUDGET = "$EvalBudget"
$env:POPULATION_SIZE = "$PopulationSize"
$env:NUMBER_OF_RUNS = "$NumberOfRuns"
$env:BASE_SEED = "$BaseSeed"
$env:START_CASE = "$StartCase"
$env:PARALLEL_WORKERS = "$ParallelWorkers"

Write-Host ""
Write-Host "============================================================"
Write-Host "Lunar surface production optimization"
Write-Host "============================================================"
Write-Host "Network sizes:      $($NetworkSizes -join ', ')"
Write-Host "Objectives:         $($Objectives -join ', ')"
Write-Host "FE budget / run:    $EvalBudget"
Write-Host "Runs / case:        $NumberOfRuns"
Write-Host "Seeds / case:       $BaseSeed-$($BaseSeed + $NumberOfRuns - 1)"
Write-Host "Parallel workers:   $ParallelWorkers"
Write-Host "Start case:         $StartCase of $TotalCases"
Write-Host "Runs this launch:   $TotalScheduledRuns"
Write-Host "Log directory:      $LogRoot"
Write-Host ""
Write-Host "Launching MATLAB using the same Start-Process -Wait pattern as the cislunar batch scripts..."
Write-Host "MATLAB output is written to the batch log while the study runs."

$StudyTimer = [System.Diagnostics.Stopwatch]::StartNew()

Push-Location $ProjectRoot
try {
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
                Get-Content $consoleLog -Tail 60 | ForEach-Object { Write-Host $_ }
            }
            throw "MATLAB failed with exit code $matlabExitCode. See: $consoleLog"
        }
    }
    finally {
        Remove-Item $stdoutLog -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrLog -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
    $StudyTimer.Stop()
}

Write-Host ""
Write-Host "============================================================"
Write-Host "Production optimization study complete"
Write-Host "============================================================"
Write-Host "Total runtime:      $([TimeSpan]::FromSeconds($StudyTimer.Elapsed.TotalSeconds))"
Write-Host "Batch log:"
Write-Host "  $consoleLog"
Write-Host ""
# -------------------------------------------------------------------------

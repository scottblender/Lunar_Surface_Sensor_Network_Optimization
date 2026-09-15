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
$TotalCases = $NetworkSizes.Count * $Objectives.Count

if ($StartCase -lt 1 -or $StartCase -gt $TotalCases) {
    throw "StartCase must be between 1 and $TotalCases."
}

$CasesThisLaunch = $TotalCases - $StartCase + 1
$TotalScheduledRuns = $CasesThisLaunch * $NumberOfRuns

# -------------------------------------------------------------------------
# Batch logs
# -------------------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogRoot = Join-Path `
    (Join-Path $ProjectRoot "results") `
    "batch_logs\production_$Timestamp"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$stdoutLog = Join-Path $LogRoot "full_study.stdout.log"
$stderrLog = Join-Path $LogRoot "full_study.stderr.log"
$consoleLog = Join-Path $LogRoot "full_study.log"

$BatchEntryMatlab = $BatchEntry.Replace("'", "''")
$batchCommand = "run('$BatchEntryMatlab')"

# -------------------------------------------------------------------------
# MATLAB environment
# -------------------------------------------------------------------------

$env:PROJECT_ROOT = $ProjectRoot
$env:EVAL_BUDGET = "$EvalBudget"
$env:POPULATION_SIZE = "$PopulationSize"
$env:NUMBER_OF_RUNS = "$NumberOfRuns"
$env:BASE_SEED = "$BaseSeed"
$env:START_CASE = "$StartCase"
$env:PARALLEL_WORKERS = "$ParallelWorkers"

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
        [int]$CompletedRuns,
        [int]$AbsoluteCase,
        [int]$RunInCase,
        [int]$NetworkSize,
        [string]$Objective
    )

    if ($CompletedRuns -gt 0) {
        $averageRunSeconds = $StudyTimer.Elapsed.TotalSeconds / $CompletedRuns
        $remainingRuns = $TotalScheduledRuns - $CompletedRuns
        $etaText = Format-TimeSpan ($averageRunSeconds * $remainingRuns)
    }
    else {
        $etaText = "calculating..."
    }

    $percentComplete = [math]::Round(
        100 * $CompletedRuns / $TotalScheduledRuns,
        1
    )

    $seed = $BaseSeed + [math]::Max($RunInCase - 1, 0)

    $status = `
        "$CompletedRuns of $TotalScheduledRuns runs | " +
        "case $AbsoluteCase of $TotalCases | " +
        "run $RunInCase of $NumberOfRuns | " +
        "Ns=$NetworkSize | $Objective | seed $seed | ETA $etaText"

    Write-Progress `
        -Activity "Lunar surface optimization study" `
        -Status $status `
        -PercentComplete $percentComplete
}

function Process-MatlabLine {
    param([string]$Line)

    if ($Line -match '^BATCH_POOL_START\|(\d+)$') {
        Write-Host "Starting one shared parallel pool with $($Matches[1]) workers..."
        return
    }

    if ($Line -match '^BATCH_POOL_READY\|(\d+)$') {
        Write-Host "Shared parallel pool ready with $($Matches[1]) workers."
        return
    }

    if ($Line -match '^BATCH_CASE_START\|(\d+)\|(\d+)\|(.+)$') {
        $script:CurrentCase = [int]$Matches[1]
        $script:CurrentNetworkSize = [int]$Matches[2]
        $script:CurrentObjective = $Matches[3]
        $script:CurrentRunInCase = 0

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "Case $($script:CurrentCase) of $TotalCases"
        Write-Host "============================================================"
        Write-Host "Network size: $($script:CurrentNetworkSize)"
        Write-Host "Objective:    $($script:CurrentObjective)"
        Write-Host "Runs:         $NumberOfRuns"
        Write-Host "FE/run:       $EvalBudget"
        Write-Host ""
        return
    }

    if ($Line -match '^\s*Run\s+(\d+)\s+complete\s*$') {
        $runInCase = [int]$Matches[1]

        if ($runInCase -gt $script:CurrentRunInCase) {
            $script:CurrentRunInCase = $runInCase
            $script:CompletedRuns++

            Update-StudyProgress `
                -CompletedRuns $script:CompletedRuns `
                -AbsoluteCase $script:CurrentCase `
                -RunInCase $runInCase `
                -NetworkSize $script:CurrentNetworkSize `
                -Objective $script:CurrentObjective

            $seed = $BaseSeed + $runInCase - 1
            Write-Host "Completed run $runInCase of $NumberOfRuns | seed $seed"
        }
        return
    }

    if ($Line -match '^BATCH_CASE_COMPLETE\|(\d+)\|(\d+)\|(.+)$') {
        Write-Host "Completed case -> Ns=$($Matches[2]) | $($Matches[3])"
        return
    }

    if ($Line -eq 'BATCH_POOL_STOP') {
        Write-Host "Shutting down shared parallel pool..."
        return
    }

    if ($Line -eq 'BATCH_POOL_STOPPED') {
        Write-Host "Shared parallel pool shut down successfully."
        return
    }

    if ($Line -eq 'BATCH_STUDY_COMPLETE') {
        Write-Host "MATLAB production study complete."
        return
    }
}

# -------------------------------------------------------------------------
# Launch one MATLAB process for the entire study
# -------------------------------------------------------------------------

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

$StudyTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:CompletedRuns = 0
$script:CurrentCase = $StartCase
$script:CurrentNetworkSize = 0
$script:CurrentObjective = "starting"
$script:CurrentRunInCase = 0

$process = Start-Process `
    -FilePath $MatlabExe `
    -ArgumentList @("-batch", "`"$batchCommand`"") `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -NoNewWindow `
    -PassThru

$stdoutLinesRead = 0

try {
    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 750

        if (Test-Path $stdoutLog) {
            $allLines = @(Get-Content $stdoutLog)

            if ($allLines.Count -gt $stdoutLinesRead) {
                $newLines = $allLines[$stdoutLinesRead..($allLines.Count - 1)]
                $stdoutLinesRead = $allLines.Count

                foreach ($line in $newLines) {
                    Process-MatlabLine -Line $line
                }
            }
        }
    }

    $process.WaitForExit()

    # Drain any final stdout written immediately before process exit.
    if (Test-Path $stdoutLog) {
        $allLines = @(Get-Content $stdoutLog)

        if ($allLines.Count -gt $stdoutLinesRead) {
            $newLines = $allLines[$stdoutLinesRead..($allLines.Count - 1)]
            foreach ($line in $newLines) {
                Process-MatlabLine -Line $line
            }
        }
    }

    if (Test-Path $consoleLog) {
        Remove-Item $consoleLog -Force
    }

    if (Test-Path $stdoutLog) {
        Get-Content $stdoutLog | Add-Content $consoleLog
    }

    if (Test-Path $stderrLog) {
        Get-Content $stderrLog | Add-Content $consoleLog
    }

    if ($process.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "MATLAB failed. Last log lines:"
        if (Test-Path $consoleLog) {
            Get-Content $consoleLog -Tail 60 | ForEach-Object { Write-Host $_ }
        }

        throw "MATLAB failed with exit code $($process.ExitCode). See: $consoleLog"
    }

    if ($script:CompletedRuns -ne $TotalScheduledRuns) {
        throw `
            "MATLAB exited successfully, but only $($script:CompletedRuns) " +
            "of $TotalScheduledRuns run completions were observed. See: $consoleLog"
    }
}
finally {
    $StudyTimer.Stop()
    Write-Progress -Activity "Lunar surface optimization study" -Completed
}

# -------------------------------------------------------------------------
# Final summary
# -------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "Production optimization study complete"
Write-Host "============================================================"
Write-Host "Completed runs:     $($script:CompletedRuns)"
Write-Host "Total runtime:      $(Format-TimeSpan $StudyTimer.Elapsed.TotalSeconds)"
Write-Host "Batch log:"
Write-Host "  $consoleLog"
Write-Host ""
# -------------------------------------------------------------------------

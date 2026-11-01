#requires -Version 5.1
<#
.SYNOPSIS
Launch one MATLAB GA convergence request for three global observers.
.EXAMPLE
.\scripts\batch\run_ga_convergence.ps1 -Study 1 -DatabaseFile 'D:\Lunar Data\optimization_database.mat' -ValidateOnly
.EXAMPLE
.\scripts\batch\run_ga_convergence.ps1 -Study 1 -DatabaseFile 'D:\Lunar Data\optimization_database.mat' -RunCounts 2 -FunctionEvaluationBudgets 120,240 -PopulationSize 60 -OutputDirectory 'results/ga_smoke'
.EXAMPLE
.\scripts\batch\run_ga_convergence.ps1 -Study 2 -DatabaseFile 'D:\Lunar Data\optimization_database.mat' -SelectedBudget 12000
.EXAMPLE
.\scripts\batch\run_ga_convergence.ps1 -Study 3 -DatabaseFile 'D:\Lunar Data\optimization_database.mat' -SelectedBudget 12000 -HigherBudget 15000 -ConfirmationRuns 1000
#>
[CmdletBinding()]
param(
    [ValidateSet('1','2','3','Custom')][string]$Study = '1',
    [Parameter(Mandatory=$true)][string]$DatabaseFile,
    [string]$OutputDirectory,
    [int[]]$RunCounts,
    [int[]]$FunctionEvaluationBudgets,
    [int]$SelectedBudget,
    [int]$HigherBudget,
    [int]$ConfirmationRuns = 1000,
    [int]$PopulationSize = 60,
    [long]$BaseSeed = 1000,
    [ValidateSet('serial','runs','population','gpu')][string]$ParallelMode = 'gpu',
    [int]$MaxWorkers = 7,
    [bool]$Resume = $true,
    [switch]$ValidateOnly,
    [string]$MatlabExe = 'matlab',
    [string]$LogDirectory = 'results/ga_launch_logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$previousDirectory = (Get-Location).Path
$previousRequest = [Environment]::GetEnvironmentVariable('LUNAR_GA_REQUEST','Process')
$matlabExitCode = 0

try {
    # This script resides at <repo>/scripts/batch/run_ga_convergence.ps1.
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).ProviderPath
    Set-Location -LiteralPath $repoRoot
    function Resolve-RepoPath([string]$PathValue) {
        if ([System.IO.Path]::IsPathRooted($PathValue)) {
            return [System.IO.Path]::GetFullPath($PathValue)
        }
        return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
    }

    if (-not $PSBoundParameters.ContainsKey('RunCounts')) {
        switch ($Study) {
            '1' { $RunCounts = @(100) }
            '2' { $RunCounts = @(20,50,100,250,500,1000) }
            '3' { $RunCounts = @($ConfirmationRuns) }
            'Custom' { throw 'Custom study requires -RunCounts.' }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('FunctionEvaluationBudgets')) {
        switch ($Study) {
            '1' { $FunctionEvaluationBudgets = @(6000,9000,12000,15000) }
            '2' {
                if ($SelectedBudget -le 0) { throw 'Study 2 requires -SelectedBudget, chosen after reviewing Study 1.' }
                $FunctionEvaluationBudgets = @($SelectedBudget)
            }
            '3' {
                if ($SelectedBudget -le 0 -or $HigherBudget -le $SelectedBudget) {
                    throw 'Study 3 requires -SelectedBudget and -HigherBudget greater than the selected budget.'
                }
                $FunctionEvaluationBudgets = @($SelectedBudget,$HigherBudget)
            }
            'Custom' { throw 'Custom study requires -FunctionEvaluationBudgets.' }
        }
    }
    if (-not $OutputDirectory) {
        switch ($Study) {
            '1' { $OutputDirectory = 'results/ga_convergence_study1' }
            '2' { $OutputDirectory = 'results/ga_convergence_study2' }
            '3' { $OutputDirectory = 'results/ga_convergence_study3' }
            'Custom' { throw 'Custom study requires -OutputDirectory.' }
        }
    }
    if ($PopulationSize -lt 2) { throw 'PopulationSize must be >= 2.' }
    if ($MaxWorkers -lt 1) { throw 'MaxWorkers must be positive.' }
    if ($BaseSeed -lt 0) { throw 'BaseSeed must be nonnegative.' }
    if ($RunCounts.Count -eq 0) { throw 'RunCounts cannot be empty.' }
    foreach ($count in $RunCounts) {
        if ($count -lt 2) { throw "Invalid run count $count (minimum 2)." }
    }
    if ($FunctionEvaluationBudgets.Count -eq 0) { throw 'FunctionEvaluationBudgets cannot be empty.' }
    foreach ($budget in $FunctionEvaluationBudgets) {
        if ($budget -lt $PopulationSize -or ($budget % $PopulationSize) -ne 0) {
            throw "FE budget $budget must be >= population size $PopulationSize and divisible by it."
        }
    }
    $maxCount = ($RunCounts | Measure-Object -Maximum).Maximum
    if ($BaseSeed + [long]$maxCount - 1 -gt [uint32]::MaxValue) {
        throw 'BaseSeed + max(RunCounts) - 1 exceeds uint32.'
    }
    $dbPath = Resolve-RepoPath $DatabaseFile
    if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) { throw "Database MAT file not found: $dbPath" }
    if ([System.IO.Path]::GetExtension($dbPath) -ine '.mat') { throw 'DatabaseFile must point to a .mat file.' }
    $outputPath = Resolve-RepoPath $OutputDirectory
    $logsPath = Resolve-RepoPath $LogDirectory
    $trimmedOutput = $outputPath.TrimEnd([char[]]@('\','/'))
    $trimmedLogs = $logsPath.TrimEnd([char[]]@('\','/'))
    if ($trimmedLogs -eq $trimmedOutput -or $trimmedLogs.StartsWith($trimmedOutput + [System.IO.Path]::DirectorySeparatorChar,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'LogDirectory must be outside OutputDirectory.'
    }
    if (-not (Test-Path -LiteralPath 'scripts/batch/run_ga_convergence_entry.m' -PathType Leaf)) {
        throw 'MATLAB entry point is missing. Merge the GA-support PR before running.'
    }
    # Validation-only does not create the experiment output directory. Logs are separate.
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
    $requestPath = Join-Path $logsPath "ga_request_${Study}_${stamp}.json"
    $logPath = Join-Path $logsPath "ga_matlab_${Study}_${stamp}.log"
    $request = [ordered]@{
        schemaVersion = 1
        databaseFile = $dbPath
        outputDirectory = $outputPath
        runCounts = [int[]]$RunCounts
	functionEvaluationBudgets = [int[]]$FunctionEvaluationBudgets
        populationSize = [int]$PopulationSize
        baseSeed = [long]$BaseSeed
        parallelMode = $ParallelMode
        maxWorkers = [int]$MaxWorkers
        resume = [bool]$Resume
        validateOnly = [bool]$ValidateOnly.IsPresent
    }
    $json = ConvertTo-Json -InputObject $request -Depth 5
	$parsed = $json | ConvertFrom-Json

	if ($parsed.runCounts -isnot [array]) {
   	 throw 'runCounts must serialize as a JSON array.'
	}

	if ($parsed.functionEvaluationBudgets -isnot [array]) {
    	throw 'functionEvaluationBudgets must serialize as a JSON array.'
	}
    [System.IO.File]::WriteAllText($requestPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    [Environment]::SetEnvironmentVariable('LUNAR_GA_REQUEST',$requestPath,'Process')
    Write-Host "Study: $Study | Request: $requestPath | Log: $logPath"
    Write-Host "Runs: $($RunCounts -join ', ') | FE budgets: $($FunctionEvaluationBudgets -join ', ') | Mode: $ParallelMode"
    # MATLAB owns the entire sweep. Never launch once per run/seed.
    # Let MATLAB write its log and stream progress directly to the console.
    # PowerShell 5.1 converts redirected native stderr into terminating
    # NativeCommandError records under ErrorActionPreference=Stop, masking
    # MATLAB's assertion text and bypassing our process exit-code handling.
    & $MatlabExe -wait -logfile $logPath -batch "run('scripts/batch/run_ga_convergence_entry.m')"
    $matlabExitCode = $LASTEXITCODE
    if ($null -eq $matlabExitCode) { $matlabExitCode = 1 }
    if ($matlabExitCode -ne 0) { throw "MATLAB failed with exit code $matlabExitCode. See $logPath" }
    Write-Host "MATLAB completed successfully. Request: $requestPath"
}
finally {
    [Environment]::SetEnvironmentVariable('LUNAR_GA_REQUEST',$previousRequest,'Process')
    Set-Location -LiteralPath $previousDirectory
}

#requires -Version 5.1
<#
.SYNOPSIS
Run or resume the three-domain paper study with live MATLAB progress and a log.
#>
[CmdletBinding()]
param(
    [string]$DatabaseFile = '',
    [string]$OutputDirectory = 'results/paper_study_global_25_100_no_surrogate',
    [string]$MatlabExe = 'matlab',
    [switch]$ValidateOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$previousDirectory = (Get-Location).Path
$previousRequest = [Environment]::GetEnvironmentVariable('LUNAR_PAPER_STUDY_REQUEST','Process')
try {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).ProviderPath
    Set-Location -LiteralPath $repoRoot
    function Resolve-RepoPath([string]$Value) {
        if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
        return [IO.Path]::GetFullPath((Join-Path $repoRoot $Value))
    }
    if (!$DatabaseFile) {
        $resultsPath = Join-Path $repoRoot 'results'
        $masters = @()
        if (Test-Path -LiteralPath $resultsPath -PathType Container) {
            $masters = @(Get-ChildItem -LiteralPath $resultsPath -Recurse -File -Filter 'optimization_database.mat' |
                Where-Object { $_.Directory.Name -eq 'paper_shared' })
        }
        if ($masters.Count -ne 1) {
            $masters | ForEach-Object { Write-Host $_.FullName }
            throw "Expected one paper_shared master under results. Found $($masters.Count). Use -DatabaseFile to specify the master."
        }
        $DatabaseFile = $masters[0].FullName
    }
    $dbPath = Resolve-RepoPath $DatabaseFile
    if (!(Test-Path -LiteralPath $dbPath -PathType Leaf)) { throw "Database not found: $dbPath" }
    $outputPath = Resolve-RepoPath $OutputDirectory
    $logsPath = Join-Path $repoRoot 'results/paper_study_logs'
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
    $requestPath = Join-Path $logsPath "paper_study_$stamp.json"
    $logPath = Join-Path $logsPath "paper_study_$stamp.log"
    $request = @{
        databaseFile = $dbPath
        outputDirectory = $outputPath
        validateOnly = $ValidateOnly.IsPresent
    }
    [IO.File]::WriteAllText($requestPath, (ConvertTo-Json -InputObject $request), (New-Object Text.UTF8Encoding($false)))
    [Environment]::SetEnvironmentVariable('LUNAR_PAPER_STUDY_REQUEST',$requestPath,'Process')
    Write-Host "Database: $dbPath"
    Write-Host "Output: $outputPath | Log: $logPath"
    # MATLAB logs native output without PowerShell 5.1 stderr redirection.
    & $MatlabExe -wait -logfile $logPath -batch "run('scripts/batch/run_paper_study_entry.m')"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "MATLAB paper study failed (exit $exitCode). See $logPath" }
}
finally {
    [Environment]::SetEnvironmentVariable('LUNAR_PAPER_STUDY_REQUEST',$previousRequest,'Process')
    Set-Location -LiteralPath $previousDirectory
}

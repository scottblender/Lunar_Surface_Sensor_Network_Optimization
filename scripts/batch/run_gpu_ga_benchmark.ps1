#requires -Version 5.1
<#
.SYNOPSIS
Benchmark CPU versus GPU: global three-observer information GA, 6000 FE, 20 seeds per backend.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DatabaseFile,
    [string]$OutputDirectory = 'results/gpu_ga_benchmark_6000fe_20runs',
    [ValidateSet('serial','population','runs')][string]$CpuParallelMode = 'population',
    [ValidateRange(1,10000)][int]$MaxWorkers = 4,
    [ValidateRange(0,4294967276)][long]$BaseSeed = 1000,
    [string]$MatlabExe = 'matlab'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$previousDirectory = (Get-Location).Path
$previousRequest = [Environment]::GetEnvironmentVariable('LUNAR_GPU_BENCHMARK_REQUEST','Process')
try {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).ProviderPath
    Set-Location -LiteralPath $repoRoot
    function Resolve-RepoPath([string]$Value) {
        if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
        return [IO.Path]::GetFullPath((Join-Path $repoRoot $Value))
    }
    $dbPath = Resolve-RepoPath $DatabaseFile
    $outputPath = Resolve-RepoPath $OutputDirectory
    if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) { throw "Database not found: $dbPath" }
    if (Test-Path -LiteralPath $outputPath) { throw "Choose a new benchmark output directory: $outputPath" }
    $logsPath = Join-Path $repoRoot 'results/ga_launch_logs'
    New-Item -ItemType Directory -Force -Path $logsPath | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
    $requestPath = Join-Path $logsPath "gpu_benchmark_$stamp.json"
    $logPath = Join-Path $logsPath "gpu_benchmark_$stamp.log"
    $request = [ordered]@{
        databaseFile = $dbPath; outputDirectory = $outputPath
        cpuParallelMode = $CpuParallelMode; maxWorkers = $MaxWorkers; baseSeed = $BaseSeed
    }
    [IO.File]::WriteAllText($requestPath, (ConvertTo-Json -InputObject $request), (New-Object Text.UTF8Encoding($false)))
    [Environment]::SetEnvironmentVariable('LUNAR_GPU_BENCHMARK_REQUEST',$requestPath,'Process')
    Write-Host "20 CPU runs + 20 GPU runs | 6000 requested FE/run | 3 global observers | information objective"
    Write-Host "Output: $outputPath | Log: $logPath"
    & $MatlabExe -wait -logfile $logPath -batch "run('scripts/batch/run_gpu_ga_benchmark_entry.m')"
    if ($LASTEXITCODE -ne 0) { throw "MATLAB benchmark failed (exit $LASTEXITCODE). See $logPath" }
}
finally {
    [Environment]::SetEnvironmentVariable('LUNAR_GPU_BENCHMARK_REQUEST',$previousRequest,'Process')
    Set-Location -LiteralPath $previousDirectory
}

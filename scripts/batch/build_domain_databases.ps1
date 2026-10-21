# Build requested domains sequentially, with fresh MATLAB processes and bounded chunks.
[CmdletBinding()]
param(
    [string]$MatlabExe = "matlab",
    [ValidateSet("clps", "south75", "south0", "global")]
    [string[]]$Domains = @("clps", "south75", "south0", "global"),
    [string]$DemFile = "",
    [string]$OutputRoot = "",
    [string]$SiteFile = "",
    [ValidateRange(0.001, 10000)][double]$SpacingKm = 15,
    [ValidateRange(1, 100000)][int]$MaxCandidatesPerChunk = 500,
    [ValidateRange(0.001, 0.1)][double]$ClpsRadiusKm = 0.1,
    [ValidateRange(0.001, 0.1)][double]$ClpsSpacingKm = 0.025,
    [ValidateRange(0, 2147483647)][int]$Seed = 1000,
    [ValidateRange(1, 10000)][int[]]$NetworkSizes = @(3),
    [switch]$PlanOnly,
    [switch]$PreflightOnly,
    # Explicit scientific tolerance, in meters. Zero uses the candidate spacing.
    [ValidateRange(0, 10000000)][double]$MaximumDemSpacingMeters = 0,
    [switch]$ContinueOnError
)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (!$DemFile) { $DemFile = Join-Path $ProjectRoot "data/Synthetic_Lunar_DEM.mat" }
if (!$OutputRoot) { $OutputRoot = Join-Path $ProjectRoot "results/domain_databases" }
if (!$SiteFile) { $SiteFile = Join-Path $ProjectRoot "config/clps_sites.csv" }
$DemFile = [IO.Path]::GetFullPath($DemFile)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$SiteFile = [IO.Path]::GetFullPath($SiteFile)
$MatlabCommand = Get-Command $MatlabExe -ErrorAction Stop
$Entry = (Join-Path $PSScriptRoot "run_domain_database_entry.m").Replace("'", "''")
$LogRoot = Join-Path $OutputRoot ("batch_logs/" + (Get-Date -Format "yyyyMMdd_HHmmss_fff"))
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
if ($PlanOnly -and $PreflightOnly) { throw "Choose PlanOnly or PreflightOnly, not both." }
$PreviousRequest = $env:LUNAR_DB_REQUEST
$Failures = @()
# Validate ALL requested domains before any database process can start.
$Phases = @("preflight", "build")
if ($PlanOnly) { $Phases = @("plan") }
if ($PreflightOnly) { $Phases = @("preflight") }
try {
  foreach ($Phase in $Phases) {
    foreach ($Domain in ($Domains | Select-Object -Unique)) {
        $RequestFile = Join-Path $LogRoot "$Domain.$Phase.request.json"
        $Request = @{
            projectRoot = $ProjectRoot
            domain = $Domain
            options = @{
                demFile = $DemFile; outputRoot = $OutputRoot; siteFile = $SiteFile
                spacingKm = $SpacingKm; maximumCandidatesPerChunk = $MaxCandidatesPerChunk
                clpsRadiusKm = $ClpsRadiusKm; clpsSpacingKm = $ClpsSpacingKm
                seed = $Seed; networkSizes = @($NetworkSizes); planOnly = [bool]$PlanOnly
                preflightOnly = ($Phase -eq "preflight")
            }
        }
        # Omit the optional tolerance when using the default. PowerShell's empty
        # subexpression can serialize as null, which MATLAB may decode as struct().
        if ($MaximumDemSpacingMeters -gt 0) {
            $Request.options.maximumDemSpacingMeters = $MaximumDemSpacingMeters
        }
        # UTF-8 without BOM works with MATLAB jsondecode on Windows and Linux.
        [IO.File]::WriteAllText($RequestFile, ($Request | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
        $env:LUNAR_DB_REQUEST = $RequestFile
        $LogFile = Join-Path $LogRoot "$Domain.$Phase.log"
        Write-Host "$Phase $Domain; log: $LogFile"
        & $MatlabCommand.Source -wait -logfile $LogFile -batch "run('$Entry')"
        $Code = $LASTEXITCODE
        if ($Code -ne 0) {
            $Failures += "$Domain/$Phase"
            if (!$ContinueOnError) { throw "MATLAB failed for $Domain (exit $Code). See $LogFile" }
        }
    }
    if ($Failures.Count) { throw "Failed preflight/builds: $($Failures -join ', '). No later phases started. Logs: $LogRoot" }
  }
} finally {
    $env:LUNAR_DB_REQUEST = $PreviousRequest
}
if ($Failures.Count) { throw "Failed domains: $($Failures -join ', '). Logs: $LogRoot" }
Write-Host "All requested domain phases completed. Logs: $LogRoot"

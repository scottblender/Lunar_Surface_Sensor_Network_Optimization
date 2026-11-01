# Exercise the real launcher with a native executable under Windows PowerShell 5.1.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$launcher = Join-Path $repoRoot 'scripts/batch/run_ga_convergence.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lunar launcher test ' + [guid]::NewGuid())
$oldDirectory = (Get-Location).Path
$oldRequest = [Environment]::GetEnvironmentVariable('LUNAR_GA_REQUEST','Process')
$oldExitCode = [Environment]::GetEnvironmentVariable('LUNAR_TEST_MATLAB_EXIT_CODE','Process')
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $fakeMatlab = Join-Path $testRoot 'fake_matlab.exe'
    $source = @'
using System;
using System.IO;
public static class FakeMatlab {
    public static int Main(string[] args) {
        int i = Array.IndexOf(args, "-logfile");
        if (i < 0 || i + 1 >= args.Length) return 99;
        int code = Int32.Parse(Environment.GetEnvironmentVariable("LUNAR_TEST_MATLAB_EXIT_CODE"));
        string message = code == 0 ? "Synthetic MATLAB success" : "Error using assert\nSynthetic MATLAB assertion detail";
        File.WriteAllText(args[i + 1], message);
        if (code == 0) Console.Out.WriteLine(message);
        else Console.Error.WriteLine(message);
        return code;
    }
}
'@
    Add-Type -TypeDefinition $source -OutputAssembly $fakeMatlab -OutputType ConsoleApplication
    $database = Join-Path $testRoot 'database.mat'
    [IO.File]::WriteAllText($database, '')
    [Environment]::SetEnvironmentVariable('LUNAR_GA_REQUEST','previous-request-sentinel','Process')
    Set-Location -LiteralPath $testRoot
    foreach ($code in @(7,0)) {
        [Environment]::SetEnvironmentVariable('LUNAR_TEST_MATLAB_EXIT_CODE',[string]$code,'Process')
        $logs = Join-Path $testRoot "logs_$code"
        $caught = ''
        try {
            & $launcher -Study 1 -DatabaseFile $database -RunCounts 2 `
                -FunctionEvaluationBudgets 120 -OutputDirectory (Join-Path $testRoot "out_$code") `
                -LogDirectory $logs -MatlabExe $fakeMatlab
        }
        catch { $caught = $_.Exception.Message }
        if ($code -eq 7 -and $caught -notlike '*MATLAB failed with exit code 7*') {
            throw "Native stderr masked process exit handling: $caught"
        }
        if ($code -eq 0 -and $caught) { throw "Success was treated as failure: $caught" }
        if ((Get-Location).Path -ne $testRoot) { throw 'Working directory was not restored.' }
        if ($env:LUNAR_GA_REQUEST -ne 'previous-request-sentinel') { throw 'Request environment was not restored.' }
        $log = Get-ChildItem -LiteralPath $logs -Filter '*.log' | Select-Object -First 1
        $content = Get-Content -LiteralPath $log.FullName -Raw
        if ($code -eq 7 -and $content -notlike '*Synthetic MATLAB assertion detail*') {
            throw 'Detailed MATLAB error is missing from the log.'
        }
    }
    Write-Host 'PASS: native stderr, nonzero/success exit handling, logs, paths with spaces, environment restoration.'
}
finally {
    Set-Location -LiteralPath $oldDirectory
    [Environment]::SetEnvironmentVariable('LUNAR_GA_REQUEST',$oldRequest,'Process')
    [Environment]::SetEnvironmentVariable('LUNAR_TEST_MATLAB_EXIT_CODE',$oldExitCode,'Process')
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

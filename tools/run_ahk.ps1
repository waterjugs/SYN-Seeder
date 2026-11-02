# Runs a Windows program for CI, prints what it writes, and stops it if it
# hangs. Exits with the program's exit code, or 1 if it had to be stopped.
#
#   ./tools/run_ahk.ps1 -Program ahk\AutoHotkey64.exe -Arguments /ErrorStdOut, tests\run_tests.ahk
#
# AutoHotkey and SynSeeder.exe are window programs, so PowerShell wouldn't
# wait for them or show their output if they were run directly.
param(
    [Parameter(Mandatory = $true)][string]$Program,
    [string[]]$Arguments = @(),
    [int]$Seconds = 600
)
$out = [IO.Path]::GetTempFileName()
$err = [IO.Path]::GetTempFileName()
$options = @{ FilePath = $Program; NoNewWindow = $true; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
if ($Arguments.Count) { $options.ArgumentList = $Arguments }
$process = Start-Process @options
$null = $process.Handle  # keeps the exit code readable once it has ended
$finished = $process.WaitForExit($Seconds * 1000)
if (-not $finished) {
    $process.Kill($true)
    $process.WaitForExit()
}
Get-Content -LiteralPath $out, $err -Encoding utf8
Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
if (-not $finished) {
    Write-Output "::error::$Program $Arguments didn't finish within $Seconds seconds"
    exit 1
}
exit $process.ExitCode

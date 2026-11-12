# Runs a Windows program for CI, prints what it writes, and stops it if it
# hangs. Exits with the program's exit code, or 1 if it had to be stopped.
# With -Expect, a program that exits with 0 must also end its output with a
# line matching that pattern (a test summary), or this exits with 1.
#
#   ./tools/run_ahk.ps1 -Program ahk\AutoHotkey64.exe -Arguments /ErrorStdOut, tests\run_tests.ahk
#
# AutoHotkey and SynSeeder.exe are window programs, so PowerShell wouldn't
# wait for them or show their output if they were run directly.
param(
    [Parameter(Mandatory = $true)][string]$Program,
    [string[]]$Arguments = @(),
    [int]$Seconds = 600,
    [string]$Expect = ""
)
$out = [IO.Path]::GetTempFileName()
$err = [IO.Path]::GetTempFileName()
# Start-Process joins the arguments with spaces and quotes none of them, so
# one with a space in it (a path under C:\Users\Jane Doe) would arrive as
# two. Each is quoted here the way Windows programs read their command line.
$quoted = @(foreach ($argument in $Arguments) {
    if ($argument -ne '' -and $argument -notmatch '[\s"]') { $argument }
    else { '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
})
$options = @{ FilePath = $Program; NoNewWindow = $true; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
if ($quoted.Count) { $options.ArgumentList = $quoted }
$process = Start-Process @options
$null = $process.Handle  # keeps the exit code readable once it has ended
$finished = $process.WaitForExit($Seconds * 1000)
if (-not $finished) {
    $process.Kill($true)
    $process.WaitForExit()
}
$printed = @(Get-Content -LiteralPath $out -Encoding utf8)
$printed
Get-Content -LiteralPath $err -Encoding utf8
Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
if (-not $finished) {
    Write-Output "::error::$Program $Arguments didn't finish within $Seconds seconds"
    exit 1
}
if ($process.ExitCode -eq 0 -and $Expect -ne "") {
    $last = @($printed | Where-Object { "$_".Trim() -ne "" }) | Select-Object -Last 1
    if ("$last" -notmatch $Expect) {
        Write-Output "::error::$Program $Arguments exited with 0, but its last line isn't like '$Expect'"
        exit 1
    }
}
exit $process.ExitCode

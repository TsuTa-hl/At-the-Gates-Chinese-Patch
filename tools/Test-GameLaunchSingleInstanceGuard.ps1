param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "Test-GameLaunch.ps1"
if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Missing smoke-test script: $scriptPath"
}

$lockName = "Local\AtGChinesePatch.TestGameLaunch.Test.$([Guid]::NewGuid().ToString('N'))"
$mutex = [System.Threading.Mutex]::new($false, $lockName)
$lockTaken = $false

try {
    $lockTaken = $mutex.WaitOne(0)
    if (!$lockTaken) {
        throw "Failed to acquire test mutex."
    }

    $missingGamePath = Join-Path $PSScriptRoot "__missing_game_path__"
    $outPath = Join-Path ([System.IO.Path]::GetTempPath()) "atg-smoke-lock-$([Guid]::NewGuid().ToString('N')).out.txt"
    $errPath = Join-Path ([System.IO.Path]::GetTempPath()) "atg-smoke-lock-$([Guid]::NewGuid().ToString('N')).err.txt"
    # Windows PowerShell 5.1 builds Start-Process' environment dictionary from
    # the inherited block.  Some Win11-hosted runners expose both PATH and Path,
    # which differ only by case and make Start-Process throw before the child
    # starts.  ProcessStartInfo with UseShellExecute=false inherits the block
    # without re-materializing that case-insensitive dictionary.
    $quote = {
        param([string]$value)
        "'" + ($value -replace "'", "''") + "'"
    }
    $childCommand = "& $(& $quote $scriptPath) -SmokeLockName $(& $quote $lockName) -GamePath $(& $quote $missingGamePath)"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $child = [Diagnostics.Process]::new()
    $child.StartInfo = $psi
    if (!$child.Start()) {
        throw "Failed to start the smoke-test child process."
    }
    $stdoutTask = $child.StandardOutput.ReadToEndAsync()
    $stderrTask = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    $exitCode = $child.ExitCode
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [IO.File]::WriteAllText($outPath, $stdout)
    [IO.File]::WriteAllText($errPath, $stderr)
    $text = $stdout + "`n" + $stderr
    $child.Dispose()

    if ($exitCode -eq 0) {
        throw "Expected Test-GameLaunch.ps1 to fail when another smoke test holds the same lock."
    }

    if ($text -notmatch "smoke test is already running") {
        throw "Expected single-instance lock failure, got: $text"
    }

    if ($text -match "Game executable not found|Unable to resolve") {
        throw "The smoke-test lock must fail before path resolution or launch checks. Output: $text"
    }
}
finally {
    if ($lockTaken) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
    foreach ($path in @($outPath, $errPath)) {
        if (![string]::IsNullOrWhiteSpace($path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

"Game launch single-instance guard validation passed."

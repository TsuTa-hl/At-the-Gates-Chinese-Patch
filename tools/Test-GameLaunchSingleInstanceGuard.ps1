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
    $child = Start-Process -FilePath "powershell" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $scriptPath,
        "-SmokeLockName",
        $lockName,
        "-GamePath",
        $missingGamePath
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outPath -RedirectStandardError $errPath
    $exitCode = $child.ExitCode
    $text = ((Get-Content -LiteralPath $outPath -Raw -ErrorAction SilentlyContinue) + "`n" +
        (Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue))

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

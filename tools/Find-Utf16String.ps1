param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Needle,

    [int]$ContextChars = 48,

    [int]$MaxMatches = 200
)

$ErrorActionPreference = "Stop"

function Test-PrintableAsciiCodeUnit {
    param([int]$Code)
    return ($Code -ge 32 -and $Code -le 126) -or $Code -eq 9 -or $Code -eq 10 -or $Code -eq 13
}

$needleBytes = [Text.Encoding]::Unicode.GetBytes($Needle)
$shown = 0

foreach ($item in $Path) {
    $files = @()
    if (Test-Path -LiteralPath $item -PathType Container) {
        $files = Get-ChildItem -LiteralPath $item -Recurse -File
    } elseif (Test-Path -LiteralPath $item -PathType Leaf) {
        $files = @(Get-Item -LiteralPath $item)
    } else {
        Write-Warning "Path not found: $item"
        continue
    }

    foreach ($file in $files) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        for ($i = 0; $i -le $bytes.Length - $needleBytes.Length; $i++) {
            if ($bytes[$i] -ne $needleBytes[0]) {
                continue
            }

            $matched = $true
            for ($j = 1; $j -lt $needleBytes.Length; $j++) {
                if ($bytes[$i + $j] -ne $needleBytes[$j]) {
                    $matched = $false
                    break
                }
            }

            if (!$matched) {
                continue
            }

            $start = $i
            for ($pos = $i - 2; $pos -ge 0 -and ($i - $pos) / 2 -le $ContextChars; $pos -= 2) {
                $code = $bytes[$pos] + ($bytes[$pos + 1] -shl 8)
                if (!(Test-PrintableAsciiCodeUnit $code)) {
                    break
                }
                $start = $pos
            }

            $end = $i + $needleBytes.Length
            for ($pos = $end; $pos -lt $bytes.Length - 1 -and ($pos - $end) / 2 -le $ContextChars; $pos += 2) {
                $code = $bytes[$pos] + ($bytes[$pos + 1] -shl 8)
                if (!(Test-PrintableAsciiCodeUnit $code)) {
                    break
                }
                $end = $pos + 2
            }

            $context = [Text.Encoding]::Unicode.GetString($bytes, $start, $end - $start)
            [pscustomobject]@{
                File = $file.FullName
                Offset = $i
                Context = $context
            }

            $shown++
            if ($shown -ge $MaxMatches) {
                return
            }
        }
    }
}

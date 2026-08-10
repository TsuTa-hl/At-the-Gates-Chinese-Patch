Set-StrictMode -Version Latest

function Get-AtGLocalizationInputDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $relativePaths = @(
        "source\English.original.xml",
        "translations\zh-CN.json",
        "translations\runtime-text-key-additions.json",
        "translations\runtime-display-strings.json",
        "translations\hardcoded-strings.json",
        "translations\hardcoded-common-strings.json",
        "translations\hardcoded-ui-il-strings.json",
        "translations\hardcoded-ui-offsets.json",
        "translations\hardcoded-ui-il-rewrite.json",
        "translations\hardcoded-common-il-rewrite.json",
        "translations\hardcoded-common-offsets.json",
        "translations\hardcoded-game-il-rewrite.json",
        "translations\hardcoded-elftools-il-rewrite.json",
        "translations\config-node-strings.json",
        "translations\config-node-extra-strings.json",
        "translations\config-node-onmap-strings.json",
        "translations\config-node-misc-strings.json"
    )

    $configDirectory = Join-Path $resolvedRoot "source\Content\Config"
    if (Test-Path -LiteralPath $configDirectory -PathType Container) {
        $relativePaths += @(Get-ChildItem -LiteralPath $configDirectory -Filter "*.original.xml" -File -Recurse |
            ForEach-Object {
                $_.FullName.Substring($resolvedRoot.Length).TrimStart([char[]]@([char]'\', [char]'/')).Replace([char]'/', [char]'\')
            })
    }

    $existing = @($relativePaths | Sort-Object -Unique | ForEach-Object {
        $relative = ([string]$_).Replace([char]'/', [char]'\')
        $fullPath = Join-Path $resolvedRoot $relative
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            [pscustomobject]@{ RelativePath = $relative; FullPath = $fullPath }
        }
    })
    $missing = @($relativePaths | Sort-Object -Unique | Where-Object {
        !(Test-Path -LiteralPath (Join-Path $resolvedRoot $_) -PathType Leaf)
    })

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = New-Object byte[] 65536
        foreach ($item in $existing) {
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($item.RelativePath + "`n")
            [void]$sha.TransformBlock($pathBytes, 0, $pathBytes.Length, $pathBytes, 0)

            $stream = [System.IO.File]::OpenRead($item.FullPath)
            try {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    [void]$sha.TransformBlock($buffer, 0, $read, $buffer, 0)
                }
            }
            finally {
                $stream.Dispose()
            }
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        $digest = ([System.BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        Digest = $digest
        Files = @($existing | ForEach-Object { $_.RelativePath })
        MissingFiles = $missing
    }
}

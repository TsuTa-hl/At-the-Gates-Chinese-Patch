Set-StrictMode -Version Latest

# These files were introduced by released Chinese-patch revisions rather than by
# At the Gates itself.  Keep this small registry with the installer so an old
# or incomplete manifest can still be removed without guessing from a player's
# version, Steam build, or file hashes.
$script:AtGLegacyPatchOnlyExactPaths = @(
    '.atg-build-report.json',
    'AtG.RuntimeText.dll',
    'Content\Text\AtG.RuntimeText.tsv',
    'Content\Fonts\AtG.RuntimeGlyphWarmset.tsv',
    'Content\Fonts\NotoSansSC-Bold.otf',
    'Content\Fonts\NotoSansSC-Regular.otf',
    'Content\Fonts\OFL.txt',
    'Content\Images\Interface\Components\Fonts\.atg-merged-fonts'
)

function Get-AtGLegacyPatchOnlyEntries {
    [CmdletBinding()]
    param()

    return @($script:AtGLegacyPatchOnlyExactPaths | ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_
            Reason = 'HistoricalChinesePatchArtifact'
        }
    })
}

function Test-AtGLegacyPatchOnlyArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $normalized = $RelativePath.Trim().Replace([char]'/', [char]'\')
    if ($normalized -in $script:AtGLegacyPatchOnlyExactPaths) {
        return $true
    }

    # Earlier builds used Chinese-named ClanCard alias directories. They are
    # deterministic patch artifacts, whereas the six original English
    # discipline directories are game assets and must never be removed here.
    $parts = $normalized.Split([char[]]@('\'))
    return $parts.Count -ge 7 -and
        $parts[0] -eq 'Content' -and
        $parts[1] -eq 'Images' -and
        $parts[2] -eq 'Interface' -and
        $parts[3] -eq 'ScreenSpecific' -and
        $parts[4] -eq 'ClanCard' -and
        $parts[5] -match '[\u4E00-\u9FFF]'
}

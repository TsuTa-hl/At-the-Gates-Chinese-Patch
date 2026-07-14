param(
    [string[]]$MapPaths = @(
        "$PSScriptRoot\..\translations\hardcoded-ui-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-common-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-game-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-elftools-il-rewrite.json",
        "$PSScriptRoot\..\translations\hardcoded-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-common-strings.json",
        "$PSScriptRoot\..\translations\hardcoded-ui-il-strings.json"
    )
)

$ErrorActionPreference = "Stop"

function Get-TagSignatures([string]$Text) {
    $signatures = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($Text, "\[[^\]]+\]")) {
        $tag = $match.Value
        $inner = $tag.Substring(1, $tag.Length - 2)

        if ($inner -match "^(\?\?\?|[+-]?###|\*|ICON:|COLOR:|/|FONT:|HOTKEY:|BLANK-LINE|NEWLINE)") {
            $signatures.Add($tag)
        }
        elseif ($inner.Contains("|")) {
            $parts = $inner.Split("|")
            $target = $parts[$parts.Length - 1]
            # The shipped UI has one legacy plural alias that is not a concept
            # key. It must be normalized to the registered UPGRADE concept.
            if ($target -eq "UPGRADES") {
                $target = "UPGRADE"
            }
            # These legacy UI labels do not resolve to a Concepts entry in the
            # shipped game. Their translations deliberately render as plain
            # text; Test-ConceptLinkTargets.ps1 verifies that no invalid link
            # remains.
            if ($target -in @("RESPECT", "RELATIONS")) {
                continue
            }
            $signatures.Add("[|$target]")
        }
        else {
            $signatures.Add($tag)
        }
    }

    return @($signatures | Sort-Object)
}

$errors = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($mapPath in $MapPaths) {
    if (!(Test-Path -LiteralPath $mapPath)) {
        throw "Translation map not found: $mapPath"
    }

    [object[]]$entries = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $entries) {
        if ($null -eq $entry.PSObject.Properties["Original"] -or $null -eq $entry.PSObject.Properties["Translation"]) {
            continue
        }

        $sourceTags = @(Get-TagSignatures ([string]$entry.Original))
        # ConvertTags maps this legacy bare verb token to the NOBLE concept link.
        if ([string]$entry.TypeFullName -eq "AtTheGatesCommon.ns_Text.Text" -and
            [string]$entry.MethodName -eq "ConvertTags" -and
            [string]$entry.Original -eq "[Ennoble]") {
            $sourceTags = @("[|NOBLE]")
        }
        if ($sourceTags.Count -eq 0) {
            continue
        }

        $checked++
        $translationTags = @(Get-TagSignatures ([string]$entry.Translation))
        if (($sourceTags -join [char]31) -eq ($translationTags -join [char]31)) {
            continue
        }

        $location = @()
        if ($entry.PSObject.Properties["TypeFullName"]) { $location += [string]$entry.TypeFullName }
        if ($entry.PSObject.Properties["MethodToken"]) { $location += [string]$entry.MethodToken }
        if ($entry.PSObject.Properties["ILOffset"]) { $location += "IL_$($entry.ILOffset)" }
        $errors.Add("$(Split-Path -Leaf $mapPath) :: $($location -join ' / ') :: '$($entry.Original)' -> '$($entry.Translation)'")
    }
}

if ($errors.Count -gt 0) {
    $errors | Select-Object -First 80 | ForEach-Object { Write-Warning $_ }
    if ($errors.Count -gt 80) {
        Write-Warning "... plus $($errors.Count - 80) more rich-text tag mismatch(es)."
    }
    throw "Rich-text tag preservation failed with $($errors.Count) mismatch(es) across $checked tagged translation entries."
}

Write-Host "Rich-text tag preservation passed for $checked tagged translation entries."

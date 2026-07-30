param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$PatchedXml = "$PSScriptRoot\..\patch\Content\Text\English.xml"
)

$ErrorActionPreference = "Stop"

function Get-EntryMap([string]$Path) {
    $xml = [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    $map = @{}
    foreach ($entry in $xml.SelectNodes("//e")) {
        $map[$entry.ntry] = $entry.InnerText
    }
    return $map
}

function Get-Tags([string]$Text) {
    # Some legacy source text contains a split rich-text link such as
    # `[Researching]|STUDY]`. Treat it as one intended concept tag so a
    # corrected localized `[研究|STUDY]` is accepted without weakening normal
    # tag-count validation.
    # `TEXT.Tip.HarvestingResources.1` also contains the one-off misspelling
    # `[Construct|CONSTURCT]`. Normalize only that literal source defect to its
    # existing CONSTRUCT concept key so the localized link remains interactive.
    $Text = $Text.Replace("[Construct|CONSTURCT]", "[Construct|CONSTRUCT]")
    $malformed = [regex]::Matches($Text, "\[[^\]]+\]\|([A-Z][A-Z0-9-]*)\]")
    $normalizedText = $Text
    foreach ($match in $malformed) {
        $normalizedText = $normalizedText.Replace($match.Value, "")
    }
    $matches = [regex]::Matches($normalizedText, "\[[^\]]+\]")
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) {
        $items.Add((Get-TagSignature $match.Value))
    }
    foreach ($match in $malformed) {
        $items.Add("[|$($match.Groups[1].Value)]")
    }
    return $items
}

function Get-TagSignature([string]$Tag) {
    if ($Tag -match "^\[(\?\?\?|[+-]?###|\*|ICON:|COLOR:|/|FONT:)") {
        return $Tag
    }

    $inner = $Tag.Substring(1, $Tag.Length - 2)
    if ($inner.Contains("|")) {
        $parts = $inner.Split("|")
        return "[|$($parts[$parts.Length - 1])]"
    }

    return $Tag
}

$source = Get-EntryMap $SourceXml
$patched = Get-EntryMap $PatchedXml
$errors = New-Object System.Collections.Generic.List[string]

foreach ($key in $source.Keys) {
    if (!$patched.ContainsKey($key)) {
        $errors.Add("Missing key: $key")
        continue
    }

    $sourceTags = @(Get-Tags $source[$key])
    $patchedTags = @(Get-Tags $patched[$key])
    $sourceSorted = @($sourceTags | Sort-Object)
    $patchedSorted = @($patchedTags | Sort-Object)

    if ($sourceSorted.Count -ne $patchedSorted.Count) {
        $errors.Add("Tag count changed: $key")
        continue
    }

    for ($i = 0; $i -lt $sourceSorted.Count; $i++) {
        if ($sourceSorted[$i] -ne $patchedSorted[$i]) {
            $errors.Add("Tag changed: $key :: '$($sourceSorted[$i])' -> '$($patchedSorted[$i])'")
            break
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | Select-Object -First 80 | ForEach-Object { Write-Warning $_ }
    if ($errors.Count -gt 80) {
        Write-Warning "... plus $($errors.Count - 80) more tag errors."
    }
    throw "Tag validation failed with $($errors.Count) issue(s)."
}

Write-Host "Tag validation passed for $($source.Count) entries."

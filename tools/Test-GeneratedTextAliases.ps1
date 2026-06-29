param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$PatchedXml = "$PSScriptRoot\..\patch\Content\Text\English.xml",
    [string[]]$BaseKeyPrefixes = @(
        "TEXT.Name.Resource.",
        "TEXT.Name.Profession.",
        "TEXT.Name.Discipline.",
        "TEXT.Name.Structure.",
        "TEXT.Name.Deposit."
    ),
    [string[]]$Suffixes = @("SINGULAR", "PLURAL")
)

$ErrorActionPreference = "Stop"

function Get-EntryMap([string]$Path) {
    $xml = [xml](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    $map = @{}
    foreach ($entry in $xml.SelectNodes("//e")) {
        $map[[string]$entry.ntry] = [string]$entry.InnerText
    }
    return $map
}

$source = Get-EntryMap $SourceXml
$patched = Get-EntryMap $PatchedXml
$errors = New-Object System.Collections.Generic.List[string]

foreach ($key in @($source.Keys | Sort-Object)) {
    if ($key.Contains(":")) {
        continue
    }

    $matchesPrefix = $false
    foreach ($prefix in $BaseKeyPrefixes) {
        if ($key.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            $matchesPrefix = $true
            break
        }
    }
    if (!$matchesPrefix) {
        continue
    }

    if (!$patched.ContainsKey($key)) {
        $errors.Add("Missing base key: $key")
        continue
    }

    foreach ($suffix in $Suffixes) {
        $aliasKey = "${key}:$suffix"
        if (!$patched.ContainsKey($aliasKey)) {
            $errors.Add("Missing generated alias: $aliasKey")
            continue
        }

        if ($patched[$aliasKey] -ne $patched[$key]) {
            $errors.Add("Alias text differs: $aliasKey")
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | Select-Object -First 80 | ForEach-Object { Write-Warning $_ }
    if ($errors.Count -gt 80) {
        Write-Warning "... plus $($errors.Count - 80) more generated alias errors."
    }
    throw "Generated text alias validation failed with $($errors.Count) issue(s)."
}

Write-Host "Generated text alias validation passed."

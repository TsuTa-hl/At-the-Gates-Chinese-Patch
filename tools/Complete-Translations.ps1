param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$TranslationJson = "$PSScriptRoot\..\translations\zh-CN.json",
    [string]$CachePath = "$PSScriptRoot\..\translations\translate-cache.json",
    [int]$MaxBatchChars = 3500,
    [int]$DelayMs = 150,
    [switch]$UseExternalTranslation
)

$ErrorActionPreference = "Stop"

function ConvertFrom-JsonFileToHashtable([string]$Path) {
    $table = @{}
    if (!(Test-Path -LiteralPath $Path)) {
        return $table
    }

    $object = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $object.PSObject.Properties) {
        $table[$property.Name] = [string]$property.Value
    }
    return $table
}

function Write-HashtableAsJson([hashtable]$Table, [string]$Path, [object[]]$Entries) {
    $ordered = [ordered]@{}
    foreach ($entry in $Entries) {
        $key = [string]$entry.ntry
        if ($Table.ContainsKey($key)) {
            $ordered[$key] = $Table[$key]
        }
    }

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $ordered | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Localize-TagDisplay([string]$Text) {
    if ($null -eq $script:TagDisplayMap) {
        $glossaryPath = Join-Path $PSScriptRoot "..\translations\tag-glossary.json"
        $script:TagDisplayMap = ConvertFrom-JsonFileToHashtable $glossaryPath
    }

    $trimmed = $Text.Trim()
    if ($script:TagDisplayMap.ContainsKey($trimmed)) {
        return $script:TagDisplayMap[$trimmed]
    }
    return $Text
}

function Convert-Tag([string]$Tag) {
    $inner = $Tag.Substring(1, $Tag.Length - 2)
    if ($inner.StartsWith("???") -or $inner.StartsWith("###") -or $inner.StartsWith("+###") -or
        $inner.StartsWith("-###") -or $inner.StartsWith("ICON:") -or $inner.StartsWith("COLOR:") -or
        $inner.StartsWith("/COLOR") -or $inner.StartsWith("FONT:") -or $inner.StartsWith("/FONT") -or
        $inner.StartsWith("HOTKEY:") -or $inner -eq "*") {
        return $Tag
    }

    if ($inner.Contains("|")) {
        $parts = $inner.Split("|")
        for ($i = 0; $i -lt $parts.Length; $i++) {
            if ($parts[$i] -match "^(###|\+###|-###|\?\?\?|[A-Z0-9_-]+(:.*)?$)") {
                continue
            }
            $parts[$i] = Localize-TagDisplay $parts[$i]
        }
        return "[" + ($parts -join "|") + "]"
    }

    return $Tag
}

function Protect-Tags([string]$Text) {
    $tags = @{}
    $index = 0
    $protected = [regex]::Replace($Text, "\[[^\]]+\]", {
        param($match)
        $token = "ATGTAG{0:D4}" -f $script:ProtectIndex
        $tags[$token] = Convert-Tag $match.Value
        $script:ProtectIndex++
        return $token
    })
    return [pscustomobject]@{
        Text = $protected
        Tags = $tags
    }
}

function Restore-Tags([string]$Text, [hashtable]$Tags) {
    $result = $Text
    foreach ($key in ($Tags.Keys | Sort-Object { $_ } -Descending)) {
        $pattern = [regex]::Escape($key)
        $result = [regex]::Replace($result, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Tags[$key] }, "IgnoreCase")
    }
    return $result.Trim()
}

function Invoke-Translate([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $body = @{
        client = "gtx"
        sl = "en"
        tl = "zh-CN"
        dt = "t"
        q = $Text
    }

    $response = Invoke-RestMethod -Uri "https://translate.googleapis.com/translate_a/single" -Method Post -Body $body -UseBasicParsing -TimeoutSec 60
    return (($response[0] | ForEach-Object { $_[0] }) -join "")
}

function Split-BatchResult([string]$Translated, [object[]]$Jobs) {
    $parts = @{}
    for ($i = 0; $i -lt $Jobs.Count; $i++) {
        $start = "ATGENTRY{0:D4}" -f $i
        $end = "ATGENTRY{0:D4}" -f ($i + 1)
        $pattern = "(?s)" + [regex]::Escape($start) + "\s*(.*?)\s*" + [regex]::Escape($end)
        $match = [regex]::Match($Translated, $pattern)
        if (!$match.Success) {
            return $null
        }
        $parts[$Jobs[$i].Key] = $match.Groups[1].Value.Trim()
    }
    return $parts
}

$xml = [xml](Get-Content -LiteralPath $SourceXml -Raw -Encoding UTF8)
$entries = @($xml.SelectNodes("//e"))
$translations = ConvertFrom-JsonFileToHashtable $TranslationJson
$cache = ConvertFrom-JsonFileToHashtable $CachePath

$jobs = New-Object System.Collections.Generic.List[object]
foreach ($entry in $entries) {
    $key = [string]$entry.ntry
    if ($translations.ContainsKey($key) -and ![string]::IsNullOrWhiteSpace($translations[$key])) {
        continue
    }

    $script:ProtectIndex = 0
    $protected = Protect-Tags $entry.InnerText
    $jobs.Add([pscustomobject]@{
        Key = $key
        Source = $entry.InnerText
        ProtectedText = $protected.Text
        Tags = $protected.Tags
    })
}

Write-Host "Missing translations: $($jobs.Count)"

$uncached = @()
foreach ($job in $jobs) {
    if ($cache.ContainsKey($job.ProtectedText)) {
        $translations[$job.Key] = Restore-Tags $cache[$job.ProtectedText] $job.Tags
    }
    else {
        $uncached += $job
    }
}

Write-Host "Need network translations: $($uncached.Count)"

if ($uncached.Count -gt 0 -and !$UseExternalTranslation) {
    throw "External translation is required for uncached missing entries. Re-run with -UseExternalTranslation only if you approve sending game text to the translation endpoint."
}

$batch = New-Object System.Collections.Generic.List[object]
$batchChars = 0

function Flush-Batch {
    param([System.Collections.Generic.List[object]]$Batch)

    if ($Batch.Count -eq 0) {
        return
    }

    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Batch.Count; $i++) {
        [void]$builder.AppendLine(("ATGENTRY{0:D4}" -f $i))
        [void]$builder.AppendLine($Batch[$i].ProtectedText)
    }
    [void]$builder.AppendLine(("ATGENTRY{0:D4}" -f $Batch.Count))

    $translatedBatch = Invoke-Translate $builder.ToString()
    $split = Split-BatchResult $translatedBatch @($Batch)
    if ($null -eq $split) {
        Write-Warning "Batch split failed; falling back to per-entry translation for $($Batch.Count) entries."
        foreach ($job in $Batch) {
            $translated = Invoke-Translate $job.ProtectedText
            $cache[$job.ProtectedText] = $translated
            $translations[$job.Key] = Restore-Tags $translated $job.Tags
            if ($DelayMs -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
        }
    }
    else {
        foreach ($job in $Batch) {
            $translated = [string]$split[$job.Key]
            $cache[$job.ProtectedText] = $translated
            $translations[$job.Key] = Restore-Tags $translated $job.Tags
        }
        if ($DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    $cache | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CachePath -Encoding UTF8
    Write-Host "Translated batch: $($Batch.Count)"
}

foreach ($job in $uncached) {
    $entryChars = $job.ProtectedText.Length + 32
    if ($batch.Count -gt 0 -and ($batchChars + $entryChars) -gt $MaxBatchChars) {
        Flush-Batch $batch
        $batch.Clear()
        $batchChars = 0
    }
    $batch.Add($job)
    $batchChars += $entryChars
}
Flush-Batch $batch

Write-HashtableAsJson $translations $TranslationJson $entries
Write-Host "Translation file updated: $TranslationJson"

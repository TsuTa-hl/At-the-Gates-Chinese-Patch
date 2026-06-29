param(
    [string]$SourceXml = "$PSScriptRoot\..\source\English.original.xml",
    [string]$OutputCsv = "$PSScriptRoot\..\translations\entries.csv"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $SourceXml)) {
    throw "Source XML not found: $SourceXml"
}

$xml = [xml](Get-Content -LiteralPath $SourceXml -Raw -Encoding UTF8)
$entries = $xml.SelectNodes("//e") | ForEach-Object {
    [pscustomobject]@{
        Key  = $_.ntry
        Text = $_.InnerText
    }
}

$outDir = Split-Path -Parent $OutputCsv
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$entries | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Host "Exported $($entries.Count) entries to $OutputCsv"

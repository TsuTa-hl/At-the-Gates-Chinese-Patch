param(
    [string]$CsvOutputPath = ".\docs\review\known-texts.csv",
    [string]$OutputPath = "",
    [string]$UnmappedDllCsv = "",
    [string]$StaticCandidatesCsv = "",
    [string]$DiscoveryCacheDirectory = ".\docs\review\generated",
    [string[]]$AdditionalDllCatalogCsv = @(),
    [switch]$NoRebuildDiscoveryInputs,
    [switch]$AggregateDuplicates
)

$ErrorActionPreference = "Stop"

function ConvertTo-ReviewLine {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    $text = $text -replace "`r`n", "\n"
    $text = $text -replace "`n", "\n"
    $text = $text -replace "`r", "\n"
    $text = $text -replace "`t", " "
    $text = $text -replace " {2,}", " "
    return $text.Trim()
}

function Get-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $raw = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }
    return $raw | ConvertFrom-Json
}

$records = New-Object System.Collections.Generic.List[object]
$mappedDllEntryKeys = [System.Collections.Generic.HashSet[string]]::new()
$mappedDllTranslationsByEntryKey = @{}
$mappedDllTranslationsByAssemblyOriginal = @{}

if ([string]::IsNullOrWhiteSpace($CsvOutputPath)) {
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $outputDirectory = Split-Path -Parent $OutputPath
        $outputLeaf = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
        if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
            $CsvOutputPath = "$outputLeaf.csv"
        }
        else {
            $CsvOutputPath = Join-Path $outputDirectory "$outputLeaf.csv"
        }
    }
    else {
        $CsvOutputPath = ".\docs\review\known-texts.csv"
    }
}

if ([string]::IsNullOrWhiteSpace($DiscoveryCacheDirectory)) {
    $DiscoveryCacheDirectory = ".\docs\review\generated"
}

New-Item -ItemType Directory -Force -Path $DiscoveryCacheDirectory | Out-Null

if ([string]::IsNullOrWhiteSpace($StaticCandidatesCsv)) {
    $StaticCandidatesCsv = Join-Path $DiscoveryCacheDirectory "static-text-candidates.csv"
}

$defaultDllCatalogs = @(
    [pscustomobject]@{
        Assembly = "UI"
        Source = ".\source\AtTheGatesUI.original.dll"
        Csv = (Join-Path $DiscoveryCacheDirectory "ui-ldstr-catalog.csv")
        Json = (Join-Path $DiscoveryCacheDirectory "ui-ldstr-catalog.json")
    },
    [pscustomobject]@{
        Assembly = "Common"
        Source = ".\source\AtTheGatesCommon.original.dll"
        Csv = (Join-Path $DiscoveryCacheDirectory "common-ldstr-catalog.csv")
        Json = (Join-Path $DiscoveryCacheDirectory "common-ldstr-catalog.json")
    },
    [pscustomobject]@{
        Assembly = "Game"
        Source = ".\source\AtTheGatesGame.original.exe"
        Csv = (Join-Path $DiscoveryCacheDirectory "game-ldstr-catalog.csv")
        Json = (Join-Path $DiscoveryCacheDirectory "game-ldstr-catalog.json")
    },
    [pscustomobject]@{
        Assembly = "ElfTools"
        Source = ".\source\ElfTools.original.dll"
        Csv = (Join-Path $DiscoveryCacheDirectory "elftools-ldstr-catalog.csv")
        Json = (Join-Path $DiscoveryCacheDirectory "elftools-ldstr-catalog.json")
    }
)

if ($AdditionalDllCatalogCsv.Count -eq 0) {
    $AdditionalDllCatalogCsv = @($defaultDllCatalogs | ForEach-Object { $_.Csv })
}

function Test-AtGDiscoveryOutputStale {
    param(
        [string]$OutputPath,
        [string[]]$InputPath
    )

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        return $true
    }

    $outputTime = (Get-Item -LiteralPath $OutputPath).LastWriteTimeUtc
    foreach ($path in @($InputPath)) {
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).LastWriteTimeUtc -gt $outputTime) {
            return $true
        }
    }

    return $false
}

function Invoke-AtGDiscoveryScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).Path
    $splat = @{}
    foreach ($key in $Arguments.Keys) {
        $splat[$key] = $Arguments[$key]
    }

    & $resolvedScript @splat | Out-Host
}

function Initialize-KnownTextDiscoveryInputs {
    if ($NoRebuildDiscoveryInputs) {
        return
    }

    $configInputs = @(
        ".\tools\Export-StaticTextCandidates.ps1",
        ".\translations\config-node-strings.json",
        ".\translations\config-node-extra-strings.json"
    ) + @((Get-ChildItem -LiteralPath ".\source\Content\Config\Primary" -Filter "*.original.xml" -File | ForEach-Object { $_.FullName }))

    if (Test-AtGDiscoveryOutputStale -OutputPath $StaticCandidatesCsv -InputPath $configInputs) {
        $staticJson = [System.IO.Path]::ChangeExtension($StaticCandidatesCsv, ".json")
        Invoke-AtGDiscoveryScript -ScriptPath ".\tools\Export-StaticTextCandidates.ps1" -Arguments @{
            OutputCsv = $StaticCandidatesCsv
            OutputJson = $staticJson
        }
    }

    foreach ($catalog in @($defaultDllCatalogs)) {
        if (Test-AtGDiscoveryOutputStale -OutputPath $catalog.Csv -InputPath @($catalog.Source, ".\tools\Export-DllLdstrCatalog.ps1", ".\tools\AtGManagedMetadata.ps1")) {
            Invoke-AtGDiscoveryScript -ScriptPath ".\tools\Export-DllLdstrCatalog.ps1" -Arguments @{
                DllPath = $catalog.Source
                OutputCsv = $catalog.Csv
                OutputJson = $catalog.Json
            }
        }
    }
}

function Add-MappedOriginalTranslation {
    param(
        [string]$Assembly,
        [string]$Original,
        [string]$Translation
    )

    $assemblyKey = Get-AssemblyKeyFromSourceName $Assembly
    if ([string]::IsNullOrWhiteSpace($assemblyKey) -or [string]::IsNullOrWhiteSpace($Original)) {
        return
    }

    $key = "$assemblyKey$([char]31)$Original"
    if (-not $script:mappedDllTranslationsByAssemblyOriginal.ContainsKey($key)) {
        $script:mappedDllTranslationsByAssemblyOriginal[$key] = [pscustomobject]@{
            Translation = $Translation
            Ambiguous = $false
        }
        return
    }

    $existing = $script:mappedDllTranslationsByAssemblyOriginal[$key]
    if ([string]$existing.Translation -ne [string]$Translation) {
        $existing.Ambiguous = $true
    }
}

function Get-ReviewKey {
    param(
        [string]$Assembly,
        [string]$MethodToken,
        [object]$ILOffset
    )

    if ([string]::IsNullOrWhiteSpace($Assembly) -or
        [string]::IsNullOrWhiteSpace($MethodToken) -or
        $null -eq $ILOffset -or
        [string]::IsNullOrWhiteSpace([string]$ILOffset)) {
        return ""
    }

    return "$Assembly|$MethodToken|$([int]$ILOffset)"
}

function Get-ReviewKeyFromObject {
    param(
        [object]$Entry,
        [string]$DefaultAssembly = ""
    )

    if ($null -eq $Entry) {
        return ""
    }

    $assembly = $DefaultAssembly
    if ($Entry.PSObject.Properties["Assembly"] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.Assembly)) {
        $assembly = [string]$Entry.Assembly
    }

    return Get-ReviewKey -Assembly $assembly -MethodToken ([string]$Entry.MethodToken) -ILOffset $Entry.ILOffset
}

function ConvertTo-ReviewArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value | ForEach-Object { $_ })
}

function New-TrialAttemptIndex {
    $index = @{}

    $trialBatchPaths = @(
        ".\translations\trial-auto-display-main-batch.json",
        ".\translations\trial-auto-display-short-batch.json",
        ".\translations\trial-concept-tags-batch.json",
        ".\translations\trial-exact-phrase-batch.json",
        ".\translations\trial-ui-notification-labels.json",
        ".\translations\trial-auto-display-more-ui-batch.json",
        ".\translations\trial-auto-display-more-ui2-batch.json",
        ".\translations\trial-auto-display-more-ui2-exact-batch.json",
        ".\translations\trial-review-ui3-batch.json",
        ".\translations\trial-review-ui4-batch.json",
        ".\translations\trial-review-ui5-batch.json",
        ".\translations\trial-review-ui6-batch.json",
        ".\translations\trial-retry-skipped-ui1-exact-batch.json",
        ".\translations\trial-ui-exact-next1-batch.json",
        ".\translations\trial-ui-exact-next2-batch.json",
        ".\translations\trial-ui-exact-next3-batch.json",
        ".\translations\trial-ui-exact-next4-batch.json",
        ".\translations\trial-ui-exact-next5-batch.json",
        ".\translations\trial-ui-exact-next6-batch.json",
        ".\translations\trial-ui-exact-next7-batch.json",
        ".\translations\trial-ui-exact-next8-batch.json",
        ".\translations\trial-common-placement-failures-1-batch.json",
        ".\translations\trial-common-property-details-1-batch.json",
        ".\translations\trial-common-property-details-2-batch.json",
        ".\translations\trial-common-property-details-3-batch.json",
        ".\translations\trial-common-property-details-4-batch.json",
        ".\translations\trial-common-property-details-5-batch.json",
        ".\translations\trial-common-property-details-6-batch.json",
        ".\translations\trial-common-property-details-7-batch.json",
        ".\translations\trial-common-property-details-8-batch.json",
        ".\translations\trial-common-battle-projection-1-batch.json",
        ".\translations\trial-common-battle-projection-2-batch.json",
        ".\translations\trial-ui-notification-details-1-batch.json",
        ".\translations\trial-ui-diplomacy-1-batch.json",
        ".\translations\trial-common-profession-tooltip-1-batch.json",
        ".\translations\trial-common-resource-tech-tooltip-1-batch.json",
        ".\translations\trial-common-clan-structure-tooltip-1-batch.json",
        ".\translations\trial-common-economy-tooltip-1-batch.json",
        ".\translations\trial-common-structure-apprentice-1-batch.json",
        ".\translations\trial-ui-help-tips-1-batch.json",
        ".\translations\trial-ui-diplomacy-profession-actions-1-batch.json",
        ".\translations\trial-common-game-abilities-1-batch.json",
        ".\translations\trial-common-game-description-1-batch.json",
        ".\translations\trial-common-game-description-retry-1-batch.json",
        ".\translations\trial-ui-dialog-actions-1-batch.json",
        ".\translations\trial-ui-dialog-actions-retry-1-batch.json",
        ".\translations\trial-common-condition-text-1-batch.json",
        ".\translations\trial-common-condition-text-retry-1-batch.json",
        ".\translations\trial-common-tooltip-fragments-1-batch.json",
        ".\translations\trial-common-resource-tooltip-2-batch.json",
        ".\translations\trial-common-concepts-help-1-batch.json",
        ".\translations\trial-common-concepts-help-2-batch.json",
        ".\translations\trial-common-concepts-help-3-batch.json",
        ".\translations\trial-common-concept-tags-2-batch.json",
        ".\translations\trial-common-concept-tags-3-batch.json",
        ".\translations\trial-common-concepts-help-4-batch.json",
        ".\translations\trial-common-concepts-help-5-batch.json",
        ".\translations\trial-common-concepts-help-6-batch.json",
        ".\translations\trial-common-concepts-help-7-batch.json",
        ".\translations\trial-common-concepts-help-8-batch.json",
        ".\translations\trial-common-concepts-help-9-batch.json",
        ".\translations\trial-common-concepts-help-10-batch.json",
        ".\translations\trial-common-concepts-help-11-batch.json",
        ".\translations\trial-common-concepts-help-12-batch.json",
        ".\translations\trial-common-concepts-help-13-safe-retry-batch.json",
        ".\translations\trial-common-concepts-help-14-batch.json",
        ".\translations\trial-common-concepts-help-15-batch.json",
        ".\translations\trial-common-concepts-help-16-batch.json",
        ".\translations\trial-common-concepts-help-17-batch.json",
        ".\translations\trial-common-concepts-help-18-batch.json",
        ".\translations\trial-common-concepts-help-19-batch.json",
        ".\translations\trial-common-zone-trait-placement-1-batch.json",
        ".\translations\trial-common-zone-trait-placement-2-batch.json",
        ".\translations\trial-common-map-placement-1-batch.json",
        ".\translations\trial-common-map-placement-2-batch.json",
        ".\translations\trial-common-config-description-1-batch.json",
        ".\translations\trial-game-art-hotkeys-1-batch.json",
        ".\translations\trial-game-static-checks-1-batch.json",
        ".\translations\trial-game-static-checks-2-batch.json",
        ".\translations\trial-game-static-checks-3-batch.json",
        ".\translations\trial-game-static-checks-4-batch.json",
        ".\translations\trial-common-command-status-1-batch.json",
        ".\translations\trial-ui-visible-misc-1-batch.json",
        ".\translations\trial-ui-tooltip-visible-1-batch.json",
        ".\translations\trial-ui-visible-misc-2-batch.json",
        ".\translations\trial-common-sage-effects-1-batch.json",
        ".\translations\trial-common-visible-misc-1-batch.json",
        ".\translations\trial-ui-visible-misc-3-batch.json",
        ".\translations\trial-common-tooltip-visible-2-exact-batch.json",
        ".\translations\trial-common-human-readable-text-1-batch.json",
        ".\translations\trial-common-property-readable-text-1-batch.json",
        ".\translations\trial-common-readable-text-2-batch.json",
        ".\translations\trial-common-readable-text-3-batch.json",
        ".\translations\trial-game-static-checks-5-batch.json",
        ".\translations\trial-ui-visible-misc-4-batch.json",
        ".\translations\trial-common-tostring-labels-1-batch.json",
        ".\translations\trial-final-visible-fragments-1-batch.json",
        ".\translations\trial-elftools-display-tooltips-1-batch.json"
    )

    foreach ($path in $trialBatchPaths) {
        $data = Get-JsonFile $path
        foreach ($entry in ConvertTo-ReviewArray $data) {
            $key = Get-ReviewKeyFromObject -Entry $entry
            if ([string]::IsNullOrWhiteSpace($key)) {
                continue
            }

            if (-not $index.ContainsKey($key)) {
                $index[$key] = [pscustomobject]@{
                    Attempted = "Yes"
                    AttemptStatus = "TrialBatch"
                    FailureReason = ""
                    Translation = ConvertTo-ReviewLine $entry.Translation
                    Evidence = Split-Path -Leaf $path
                }
            }
        }
    }

    if (Test-Path -LiteralPath ".\.tmp\trial-localization") {
        foreach ($path in Get-ChildItem -LiteralPath ".\.tmp\trial-localization" -Recurse -File | Where-Object { $_.Name -in @("accepted.json", "rejected.json") }) {
            $data = Get-JsonFile $path.FullName
            $isRejected = $path.Name -eq "rejected.json"
            foreach ($entry in ConvertTo-ReviewArray $data) {
                $key = Get-ReviewKeyFromObject -Entry $entry
                if ([string]::IsNullOrWhiteSpace($key)) {
                    continue
                }

                $failure = ""
                if ($isRejected) {
                    $failure = "Rejected by trial fast-fail; see $($path.FullName)."
                    if ([string]$entry.MethodToken -eq "0x06000125" -and [int]$entry.ILOffset -eq 1774 -and [string]$entry.Original -eq "Leave ") {
                        $failure = "Rejected at build time because this IL rewrite conflicts with verified UI offset patch 490295 for original 'Leave'. Migrate or remove that offset fallback before retrying."
                    }
                }

                $index[$key] = [pscustomobject]@{
                    Attempted = "Yes"
                    AttemptStatus = if ($isRejected) { "Rejected" } else { "AcceptedSmoke" }
                    FailureReason = $failure
                    Translation = ConvertTo-ReviewLine $entry.Translation
                    Evidence = $path.FullName
                }
            }
        }
    }

    $trialState = Get-JsonFile ".\docs\agent\trial-localization-state.json"
    if ($null -ne $trialState) {
        foreach ($entry in ConvertTo-ReviewArray $trialState.knownRejectedSingles) {
            $key = Get-ReviewKey -Assembly ([string]$entry.assembly) -MethodToken ([string]$entry.methodToken) -ILOffset $entry.ilOffset
            if ([string]::IsNullOrWhiteSpace($key)) {
                continue
            }

            $index[$key] = [pscustomobject]@{
                Attempted = "Yes"
                AttemptStatus = "Rejected"
                FailureReason = ConvertTo-ReviewLine $entry.reason
                Translation = ""
                Evidence = "docs/agent/trial-localization-state.json:$($entry.batchId)"
            }
        }
    }

    return $index
}

$trialAttemptIndex = New-TrialAttemptIndex

function Get-TrialAttempt {
    param(
        [string]$Assembly,
        [string]$MethodToken,
        [object]$ILOffset
    )

    $key = Get-ReviewKey -Assembly $Assembly -MethodToken $MethodToken -ILOffset $ILOffset
    if (-not [string]::IsNullOrWhiteSpace($key) -and $trialAttemptIndex.ContainsKey($key)) {
        return $trialAttemptIndex[$key]
    }

    return $null
}

function Add-KnownText {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$Original,
        [AllowNull()][string]$Translation,
        [string]$Kind = "",
        [string]$Status = "",
        [string]$Locator = "",
        [string]$Safety = "",
        [string]$LocalizationAttempted = "",
        [string]$AttemptStatus = "",
        [string]$FailureReason = "",
        [string]$Notes = ""
    )

    $cleanOriginal = ConvertTo-ReviewLine $Original
    if ([string]::IsNullOrWhiteSpace($cleanOriginal)) {
        return
    }

    $records.Add([pscustomobject]@{
        SourceFile = $SourceFile
        Original = $cleanOriginal
        Translation = ConvertTo-ReviewLine $Translation
        Kind = $Kind
        Status = $Status
        Locator = ConvertTo-ReviewLine $Locator
        Safety = ConvertTo-ReviewLine $Safety
        LocalizationAttempted = ConvertTo-ReviewLine $LocalizationAttempted
        AttemptStatus = ConvertTo-ReviewLine $AttemptStatus
        FailureReason = ConvertTo-ReviewLine $FailureReason
        Notes = ConvertTo-ReviewLine $Notes
    }) | Out-Null
}

function Get-ReviewState {
    param([object]$Record)

    $attemptStatus = [string]$Record.AttemptStatus
    switch ($attemptStatus) {
        { $_ -in @("Mapped", "MappedByOriginal", "TrialBatch", "AcceptedSmoke") } { return "Translated" }
        "Rejected" { return "Rejected" }
        "SkippedByPolicy" { return "Skipped" }
        "TrialCandidate" { return "NeedsTrial" }
        "NotAttempted" { return "NeedsTrial" }
    }

    if ([string]$Record.Status -eq "RejectedTrial") {
        return "Rejected"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Record.Translation)) {
        return "Translated"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Record.FailureReason)) {
        if ([string]$Record.FailureReason -match '^Trial candidate:') {
            return "NeedsTrial"
        }
        return "Skipped"
    }

    return "NeedsTrial"
}

function Get-ReviewReasonCode {
    param(
        [object]$Record,
        [string]$ReviewState
    )

    if ($ReviewState -in @("Translated", "NeedsTrial")) {
        return ""
    }

    $reason = [string]$Record.FailureReason
    $kind = [string]$Record.Kind
    $safety = [string]$Record.Safety
    $haystack = "$reason $kind $safety"

    if ($haystack -match '490295|offset fallback|verified UI offset|PatchConflict|conflicts with verified') {
        return "PatchConflict"
    }

    if ($haystack -match 'external login|challenge|forum|online-flow|brand|copyright|metadata|developer test-group|registered trademarks|Conifer Games') {
        return "OutOfScope"
    }

    if ($haystack -match 'grammar fragment|punctuation glue|semantic-free|formatter tag|legacy tag-conversion|match token|CodeOrAbbreviation|TextKeyReference') {
        return "FragmentOrToken"
    }

    if ($haystack -match 'UserSetting|Settings\.xml|serialized|XML-safe|logic-sensitive|ManualOnly|DoNotPatchHere|static candidate safety|date|season|month|faction|Faction|Common concept|config candidate') {
        return "LogicSensitive"
    }

    if ($haystack -match 'technical/internal|diagnostic|parser|resource ID|exception|debug|engine/helper|config-validation|raw IDs|paths?|control ID|internal misuse|ToString diagnostic|settings') {
        return "TechnicalInternal"
    }

    if ($ReviewState -eq "Rejected") {
        return "RejectedByTest"
    }

    return "TechnicalInternal"
}

function Get-StaticCandidateSkipReason {
    param([object]$Candidate)

    $sourceFile = [string]$Candidate.SourceFile
    $safety = [string]$Candidate.Safety

    if ([string]::IsNullOrWhiteSpace($safety) -or $safety -eq "SafeDisplay") {
        return ""
    }

    if ($sourceFile -eq "Factions.xml") {
        return "Skipped by policy: faction names/labels are logic-sensitive and are not bulk-patched without targeted regression coverage."
    }

    if ($sourceFile -eq "FactionTraits.xml") {
        return "Skipped by policy: faction-trait config candidates are marked $safety and require manual targeted review before patching."
    }

    if ($sourceFile -eq "Techs.xml") {
        return "Skipped by policy: this tech config candidate is marked $safety; only stable SafeDisplay nodes are auto-patched."
    }

    return "Skipped by policy: static candidate safety is $safety, not SafeDisplay."
}

function Test-AtGInternalOrTechnicalText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $true
    }

    $Text = $Text.Trim()

    return ($Text -match '[/\\]' -or
        $Text -match '\.(ogg|xnb|png|xml|txt|dll|exe|AtGSave)\b' -or
        $Text -match '^(Ntfn|Btn|Lbl|Pnl|Img|Screen|Popup|MAP_SIZE|ICON|UI|SFX)\.' -or
        $Text -match '^[A-Z0-9_.-]{3,}$' -or
        $Text -match '^\s*[-*^]{3,}\s*$' -or
        $Text -match '^\s*-\s*(Init\(\)|.*Loaded|.*Created|.*Initialized|.*Complete|.*Cleared|.*NOT Cleared|Quickload|Quickstart|Playing Title Music|Showing .*)$' -or
        $Text -match '^\([A-Z0-9_-]+\)$' -or
        $Text -match '^:(SINGULAR|PLURAL|SHORT_NAME|SHORT_PLURAL_NAME|ICON)\]?$|^\[ICON:|^\[DEPOSIT-|^\[[A-Z]+:ICON\]$' -or
        $Text -match '^\[[A-Z0-9-]+(:[A-Z_]+)?\]$' -or
        $Text -match '^\[[A-Z]+\]\s+.*\.\w+' -or
        $Text -match '^\[(FONT|COLOR):|^\[(DEFAULT|SEASONAL|CLIMATE|REVERSE|null)\]$' -or
        $Text -match '^(h tt|h:mm tt|\+#,#;-#,#;0|2020 July 1)$' -or
        $Text -match '^(Main Menu|World Screen|Conifer Games|BUILD|BUILD \[|World \[)$' -or
        $Text -match '^\s*\\n(FROM|New cost|Old cost):' -or
        $Text -match '^\]\s*(\\n\\nTurn|TIMESTAMP|\.{3}|-)' -or
        $Text -match '^(Button_|Text\.RichTextLabel\.|SelectionPanel\.|ClansScreen\.|Return to Map Button$)' -or
        $Text -match '^\.\.\. (OneItemPercent|PossibleCounts|CURRENT PROJECT|DISABLED|HIDDEN|MOUSED OVER|QUEUED)' -or
        $Text -match '^(Game|XML|Controller|World Screen|Game World|Game Map|Program|Main Menu|WS Cntrlr)\s+-' -or
        $Text -match 'Exception|StackTrace|Debug|ERROR|WARNING|not defined|not handled|Trying to|This collection is read-only|read back in as \[null\]|supposed to receive|shouldn''t|cannot be null' -or
        $Text -match 'Adding duplicate|duplicate|Unable to find|Was unable to find|Failed to find|FAILED TO FIND|Cannot cast|Calculated a \[null\]|Calling .* when|Referencing .* when|Please show Jon|Please show this to Jon|send Jon a screenshot' -or
        $Text -match 'GeneratedPlayerData\.|Pathfinding:|XML contains|not a valid|should always|must also be set|should only be done once|has never been defined|outside the allowed range|TextKey|invalid without|Invalid with|no tile to a container|The minimum number' -or
        $Text -match 'Found 0 valid nearby tiles|Free LeaderTrait has|Executing a Transaction|being given a hint|Building a comma separated list|Borders Spritesheet|Tip being added|Index into |out of bounds|play max|provided:|^max:$|^Text:$|^Counts =$' -or
        $Text -match 'Calculated a deficit|CCanSiege Object|Chose a \[null\]|Found a \[null\]|Percent for a .* should not be \[0\]|Testing CanUpgrade')
}

function Test-AtGBroadGrammarFragment {
    param([string]$Text)

    $trimmed = $Text.Trim()
    if ($trimmed.Length -le 3) {
        return $true
    }

    return ($trimmed -in @(
            "This", "all", "for", "next", "any", "Will", "Can", "as",
            "is", "'s", "has", "with", "from", "more", "each", "a [",
            "Text Key [", "No extra", "[DEAD]"
        ) -or
        $Text -match '^\s*(for|from|when|this|on|as|by|is|to|has|have|with|in|of|and|or)\s*$' -or
        $Text -match '^\s*(for|from|when|on|as|by|to|with|in|of|and|or)\s+[a-z\[]+\s*$' -or
        $Text -match '^\s*%?\s*(less|more|Range|needed|increased by|decreased by|available on its|within a radius of)\s*$')
}

function Test-AtGGameInternalOrLogText {
    param(
        [string]$TypeFullName,
        [string]$MethodName,
        [string]$Text
    )

    $trimmed = $Text.Trim()

    if ($TypeFullName -match '\.ns_StaticChecks\.' -and $MethodName -eq "PerformCheck") {
        return $false
    }

    if ($TypeFullName -eq "AtTheGatesGame.ns_UIControllers.ATGApplication" -and
        $MethodName -match '^(ShowLoadFailedPopup|ShowLoadFile)$') {
        return $false
    }

    if ($TypeFullName -eq "AtTheGatesGame.ns_UIControllers.ATGUI" -and
        $MethodName -match '^SeizedImp_Create') {
        return $false
    }

    if ($TypeFullName -match 'VictoryScreen' -and $MethodName -eq "AddButtons") {
        return $false
    }

    if ($trimmed -match '^(-{1,}|[-+*]{3,}|_+)\s' -or
        $trimmed -match '^(---|\+\+\+\+\+|--------|\*\*\*)' -or
        $trimmed -match 'RNG Seed|Init_|GameMap\(\)|Loaded|Created|Graphics|Settings\.|Giving Control to Human|TOGGLE DRAWING|PAUSED|Learned Tech|Popped Goody|Trained:|APPLY TO OBJECTS' -or
        $trimmed -match '^(A map object|A ship is|A tile that|Adding |AI object|An Army has|Assigning |ATG[A-Za-z]+\.|BaseObject\.|Calculated |Calculating |Calling |called |Changing |Chose |Completed Command with no execution defined|Could not load plugin type|Dead object|Deploying a Unit|DepositRevealMgr\.|Docking a unit|Ending the turn|Finished a Construct|Found |Giving player a Tech|Group Rings$|ImmobilizationCount|INITIALIZING -|Leader already has the Trait|MapObject lacks the required CCanAct component\.|Max Importance of a Desire for|Max Partner Importance of a Desire for|Min Importance of a Desire for|Min Partner Importance of a Desire for|Negative harvestable amount|NO NAME$|Object |Object''s |Pillaging an object|Player is |Plague on Turn|Plague Records$|Political Events -|Post Transform Pass$|Removing a BuildableStructure|Removing a Tech|Resource Appearance Manager looking|Second Pass$|Setting |Structure is being exhausted|TerrainNoLongerTrapsCount|Testing |The min num Clans until|The min turns until|Thinking about pillaging|Training a Unit for Magister Militum|Turns Left to Skip|Turns required not specified|Turns to pack are negative|Turns Until Force-Trigger|Turns Until Next Plague|Unable to|Unit that already has a Desire|Unit\.ChooseTraits|was never properly set for|Was unable|Wasn''t able to find a valid plague|Wasn''t able to find a valid tile within a range of|Zone has 0 tiles!|Please show Jon|Please show this to Jon)' -or
        $trimmed -match '^(i at \(|is being killed by its owner!|is less than or equal to zero\. \()' -or
        $trimmed -match '^(CCan[A-Za-z]+|CRequiresSupply|MapObject) component''s parent lacks the required CCanAct component\.$' -or
        $trimmed -match '^PlagueMgr\.') {
        return $true
    }

    if ($TypeFullName -match 'AtTheGatesGame\.ns_GameCode\.(LeaderMgr|PoliticalEventMgr|PlagueMgr|PlagueRecord)' -and
        $MethodName -eq "ToString") {
        return $true
    }

    if ($TypeFullName -match 'AtTheGatesGame\.ns_GameCode\.ResourcesMgr' -and
        $MethodName -eq "CalculateConversionAmounts") {
        return $true
    }

    if ($TypeFullName -eq "AtTheGatesGame.ns_Map.ATGZone" -and
        $MethodName -eq "AddTile") {
        return $true
    }

    if ($TypeFullName -match 'AtTheGatesGame\.ns_UIControllers\.DebugText\.') {
        return $true
    }

    if ($TypeFullName -match 'AtTheGatesGame\.(GameCore|ns_Map\.ATGMap|ns_GameCode\.WorldCore|ns_UIControllers\.ATGWorldScreen|ns_Map\.DepositRevealMgr)' -and
        $MethodName -match '^(\.ctor|Init|Init_|Load|LoadData|Create_|Create|NewGame_|Update_NewGame|AssignStartingVisibility|CreateShaders|CreateRenderTargets)') {
        return $true
    }

    if ($TypeFullName -match 'AtTheGatesGame\.ns_GameCode\.(ResourcesMgr|ATGUnit|ATGPlayer|ATGCity|TechMgr|DiploMgr)' -and
        $MethodName -match '^(Recalc|Apply|Calculate|Convert|Cover|Choose|EndTurn|ChangeResearch|ToString|GetTurnsToCreate)') {
        return ($trimmed -match '^[-*+]|RNG Seed|Shortage|stopped foraging|^\(|^\)|^\]|^\[ Command:|^\+\+\+\+\+|^-----|^Army \(x|^Base:')
    }

    return $false
}

function Get-DllSkipReason {
    param([object]$Row)

    $assembly = [string]$Row.Assembly
    if ([string]::IsNullOrWhiteSpace($assembly) -and $Row.PSObject.Properties["AssemblyName"]) {
        $assembly = [string]$Row.AssemblyName
    }
    $assembly = Get-AssemblyKeyFromSourceName $assembly
    $class = [string]$Row.Class
    $type = [string]$Row.TypeFullName
    $method = [string]$Row.MethodName
    $original = [string]$Row.Original
    if ([string]::IsNullOrWhiteSpace($original) -and
        $null -ne $Row.PSObject.Properties["Value"]) {
        $original = [string]$Row.Value
    }
    $trimmed = $original.Trim()

    if ($assembly -eq "Common" -and $type -match '^AtTheGatesCommon\.ns_GlobalSystems\.UserSetting_') {
        return "Skipped by policy: user setting descriptions are serialized into Settings.xml without XML-safe encoding; non-ASCII trial text polluted Settings.xml and caused 'Error Loading User Settings'."
    }

    if ($assembly -eq "ElfTools") {
        $isElfToolsDisplayCandidate = (
            ($type -eq "ElfTools.Interfaces.Layout.CollapsibleContainer" -and
                $method -eq "Init" -and
                ($trimmed -match '^Click to make this panel disappear completely\.' -or
                 $trimmed -eq "Click to expand this panel and see" -or
                 $trimmed -eq "Click to minimize this panel.")) -or
            ($type -eq "ElfTools.UI.Objects.Dropdown" -and
                $method -eq ".ctor" -and
                $trimmed -eq "Click to select...") -or
            ($type -eq "ElfTools.Dialogs.TwoButtonDialog" -and
                $method -eq "Initialize" -and
                ($trimmed -eq "Hotkey: [Y]" -or $trimmed -eq "Hotkey: [ESC]"))
        )

        if ($isElfToolsDisplayCandidate) {
            return "Trial candidate: ElfTools display tooltip candidate. Use small fast-fail batches; missing visual coverage alone is not a skip reason."
        }

        return "Skipped by policy: ElfTools engine/helper text, diagnostics, parser tokens, resource IDs, hotkey labels, or internal exception text; not a standalone localization target."
    }

    if ($type -match 'DebugConsole|ns_GlobalSystems\.Log|ns_GlobalSystems\.Settings|TextFormatter' -or
        $type -match 'ns_Plugins\.ns_Other\.GeneratedPlayerData|ns_Utilities\.Path|ns_Utilities\.ATGRandom|ns_Events\.WorldEvent' -or
        $type -match 'ns_Config\.(Config|TextKeys|Beach|Terrain|River|Road|AI|Map|Game|LeaderTrait|Deposit|Profession|WorldEvent)' -or
        $type -match 'ns_Config\.(StartingSituationData|ClanComment|FreeTrait|StopMoodDrop|Weight_|BonusRandWeightWithTrait|LeaderConfig|DialogueOptionConfig)' -or
        $type -match 'ns_Diplomacy\.Transaction|Utils\.BordersBuilder|ns_Enums\.(ScoringUtils|MapUtils)|ProgramCommon|HelpGuideTips\.HelpGuide' -or
        $type -match 'ns_InGame\.ns_Popups\.ProfessionButton' -or
        $method -match '^(LoadXML|LoadXML_Finished|Load.*Configs|Load.*Variants|Validate|ValidateEdges|CachePointers|ReadIDsFromXML|WriteIntroComment|BuildInvalidTagMessage|ProcessTag_|Parse_)') {
        return "Skipped by policy: technical/internal resource, log, diagnostic, settings, parser, or config-validation text; not user-facing display text."
    }

    if ($type -eq "AtTheGatesUI.ns_InGame.ClanCard" -and
        ($trimmed -match '^(Button_|Return to Map Button$)')) {
        return "Skipped by policy: ClanCard action button control ID, not player-facing text."
    }

    if ($type -eq "AtTheGatesUI.ns_InGame.TileTooltipMgr" -and
        $trimmed -match 'Cannot pass \[null\]') {
        return "Skipped by policy: TileTooltipMgr internal misuse diagnostic, not player-facing tile tooltip text."
    }

    if ($type -eq "AtTheGatesUI.ns_MainMenu.MainMenu" -and
        ($trimmed -match "registered trademarks|Conifer Games|^BUILD$|^Send your$|^Testing our$|TEST GROUP APPROVED|new tooltip system")) {
        return "Skipped by policy: brand/copyright/build metadata or developer test-group text; acceptable remaining English."
    }

    if ($type -eq "AtTheGatesGame.ns_Map.SeasonsMgr" -and $method -eq "ToString") {
        return "Skipped by policy: season manager ToString diagnostic tags, not player-facing date text."
    }

    if ($method -match '^(GetMonthFromName|GetMonthFromIndex|GetTimeLength)$') {
        return "Skipped by policy: date/month conversion is logic-sensitive and not a display localization target."
    }

    if ($type -eq "AtTheGatesCommon.ns_Text.Text" -and $method -eq "ConvertTags") {
        return "Skipped by policy: legacy tag-conversion match token; changing it can prevent existing English tags from being converted."
    }

    if (Test-AtGInternalOrTechnicalText $original) {
        return "Skipped by policy: technical/internal resource, log, diagnostic, or exception text; not user-facing display text."
    }

    if ($trimmed -match '^(Early|Late) (January|February|March|April|May|June|July|August|September|October|November|December)$' -or
        $trimmed -match 'dddd, MMMM dd|January 2018|Winter|Spring|Summer|Autumn|Fall') {
        return "Skipped by policy: date/season formatting is logic-sensitive and must not be bulk-patched."
    }

    if (Test-AtGBroadGrammarFragment $original) {
        return "Skipped by policy: broad grammar fragment, punctuation glue, or semantic-free token; not useful as a standalone localization target."
    }

    if ($type -match 'LoginScreen|GroupGame|Challenge|PatchNotes|AppendGroupGameLocation' -or
        $original -match 'email|contact@|forum|Challenge|Group Game|official entries|playable \[Faction\|FACTION\]') {
        return "Skipped by policy: external login/challenge/forum or optional online-flow text is outside the current automated localization scope."
    }

    if ($assembly -eq "Common") {
        return "Trial candidate: Common DLL display candidate. Use small method-scoped fast-fail batches; do not skip only because targeted UI evidence is missing."
    }

    if ($assembly -eq "Game") {
        if (Test-AtGGameInternalOrLogText -TypeFullName $type -MethodName $method -Text $original) {
            return "Skipped by policy: gameplay EXE log, diagnostic, initialization marker, or automation-dependent program marker; not player-facing display text."
        }

        return "Trial candidate: gameplay EXE display candidate. Use small method-scoped fast-fail batches; do not skip only because targeted regression evidence is missing."
    }

    if ($class -eq "TooltipFragment" -or $type -match 'SelectionPanel|ClanCard|WorldScreen|Notification') {
        return "Trial candidate: UI display fragment. Use trial fast-fail; missing visual coverage alone is not a skip reason."
    }

    return "Trial candidate: discovered DLL text not yet selected for trial localization. Missing UI evidence alone is not a skip reason."
}

function Get-SourceFromAssemblyName {
    param([string]$Assembly)

    switch -Regex ($Assembly) {
        "^UI$|AtTheGatesUI" { return "source\AtTheGatesUI.original.dll" }
        "^Common$|AtTheGatesCommon" { return "source\AtTheGatesCommon.original.dll" }
        "^Game$|AtTheGatesGame" { return "source\AtTheGatesGame.original.exe" }
        "^ElfTools$" { return "source\ElfTools.original.dll" }
        default { return $Assembly }
    }
}

function Get-AssemblyKeyFromSourceName {
    param([string]$Name)

    switch -Regex ($Name) {
        "^UI$|AtTheGatesUI" { return "UI" }
        "^Common$|AtTheGatesCommon" { return "Common" }
        "^Game$|AtTheGatesGame" { return "Game" }
        "^ElfTools$|ElfTools" { return "ElfTools" }
        default { return $Name }
    }
}

function Add-IlRewriteMap {
    param(
        [string]$Path,
        [string]$FallbackSource,
        [string]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $data = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($data -is [array]) {
        $items = $data
    }
    else {
        $items = @($data)
    }

    foreach ($item in $items) {
        if ($null -eq $item -or $null -eq $item.Original) {
            continue
        }

        $source = $FallbackSource
        if ($item.PSObject.Properties["Assembly"]) {
            $source = Get-SourceFromAssemblyName ([string]$item.Assembly)
        }

        if ($item.PSObject.Properties["MethodToken"] -and $item.PSObject.Properties["ILOffset"]) {
            $mappedAssembly = Get-AssemblyKeyFromSourceName $FallbackSource
            if ($item.PSObject.Properties["Assembly"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Assembly)) {
                $mappedAssembly = Get-AssemblyKeyFromSourceName ([string]$item.Assembly)
            }
            $mappedKey = Get-ReviewKey -Assembly $mappedAssembly -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            if (-not [string]::IsNullOrWhiteSpace($mappedKey)) {
                [void]$script:mappedDllEntryKeys.Add($mappedKey)
                $script:mappedDllTranslationsByEntryKey[$mappedKey] = [pscustomobject]@{
                    Translation = [string]$item.Translation
                    Safety = [string]$item.Safety
                    Notes = if ($item.PSObject.Properties["EvidenceScenario"] -and -not [string]::IsNullOrWhiteSpace([string]$item.EvidenceScenario)) {
                        "Trial evidence: $($item.EvidenceScenario)"
                    }
                    else {
                        ""
                    }
                }
            }
        }

        $assemblyForOriginal = Get-AssemblyKeyFromSourceName $FallbackSource
        if ($item.PSObject.Properties["Assembly"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Assembly)) {
            $assemblyForOriginal = Get-AssemblyKeyFromSourceName ([string]$item.Assembly)
        }
        Add-MappedOriginalTranslation -Assembly $assemblyForOriginal -Original ([string]$item.Original) -Translation ([string]$item.Translation)

        $locatorParts = @()
        foreach ($name in @("TypeFullName", "MethodName", "MethodToken", "ILOffset", "StringToken", "Offset")) {
            $prop = $item.PSObject.Properties[$name]
            if ($null -ne $prop -and $null -ne $prop.Value -and [string]$prop.Value -ne "") {
                $locatorParts += "$name=$($prop.Value)"
            }
        }

        $attempt = $null
        if ($item.PSObject.Properties["MethodToken"] -and $item.PSObject.Properties["ILOffset"]) {
            $attemptAssembly = [System.IO.Path]::GetFileNameWithoutExtension($FallbackSource)
            if ($item.PSObject.Properties["Assembly"] -and -not [string]::IsNullOrWhiteSpace([string]$item.Assembly)) {
                $attemptAssembly = [string]$item.Assembly
            }
            $attempt = Get-TrialAttempt -Assembly $attemptAssembly -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            if ($null -eq $attempt -and $FallbackSource -match "AtTheGatesUI") {
                $attempt = Get-TrialAttempt -Assembly "UI" -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            }
            if ($null -eq $attempt -and $FallbackSource -match "AtTheGatesCommon") {
                $attempt = Get-TrialAttempt -Assembly "Common" -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            }
            if ($null -eq $attempt -and $FallbackSource -match "AtTheGatesGame") {
                $attempt = Get-TrialAttempt -Assembly "Game" -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            }
            if ($null -eq $attempt -and $FallbackSource -match "ElfTools") {
                $attempt = Get-TrialAttempt -Assembly "ElfTools" -MethodToken ([string]$item.MethodToken) -ILOffset $item.ILOffset
            }
        }

        $attempted = "Yes"
        $attemptStatus = "Mapped"
        $failureReason = ""
        $notes = ""
        if ($null -ne $attempt) {
            $attemptStatus = $attempt.AttemptStatus
            $failureReason = $attempt.FailureReason
            $notes = "Trial evidence: $($attempt.Evidence)"
        }
        elseif ($item.PSObject.Properties["EvidenceScenario"] -and -not [string]::IsNullOrWhiteSpace([string]$item.EvidenceScenario)) {
            $attemptStatus = "AcceptedSmoke"
            $notes = "Trial evidence: $($item.EvidenceScenario)"
        }

        $status = "Translated"
        if ($Kind -like "Trial batch:*") {
            if ($attemptStatus -eq "Rejected") {
                $status = "RejectedTrial"
            }
            elseif ($attemptStatus -eq "AcceptedSmoke") {
                $status = "Translated"
            }
            else {
                $status = "TrialBatchCandidate"
            }
        }

        Add-KnownText `
            -SourceFile $source `
            -Original ([string]$item.Original) `
            -Translation ([string]$item.Translation) `
            -Kind $Kind `
            -Status $status `
            -Locator ($locatorParts -join "; ") `
            -Safety ([string]$item.Safety) `
            -LocalizationAttempted $attempted `
            -AttemptStatus $attemptStatus `
            -FailureReason $failureReason `
            -Notes $notes
    }
}

function Add-DictionaryMap {
    param(
        [string]$Path,
        [string]$SourceFile,
        [string]$Kind
    )

    $map = Get-JsonFile $Path
    if ($null -eq $map) {
        return
    }

    foreach ($prop in $map.PSObject.Properties) {
        Add-MappedOriginalTranslation -Assembly $SourceFile -Original ([string]$prop.Name) -Translation ([string]$prop.Value)
        Add-KnownText `
            -SourceFile $SourceFile `
            -Original $prop.Name `
            -Translation ([string]$prop.Value) `
            -Kind $Kind `
            -Status "Translated" `
            -Locator (Split-Path -Leaf $Path) `
            -LocalizationAttempted "Yes" `
            -AttemptStatus "Mapped"
    }
}

function Get-ConfigTranslationMap {
    $result = @{}
    foreach ($path in @(".\translations\config-node-strings.json", ".\translations\config-node-extra-strings.json")) {
        $root = Get-JsonFile $path
        if ($null -eq $root) {
            continue
        }

        foreach ($fileProp in $root.PSObject.Properties) {
            $sourceFile = $fileProp.Name
            $items = @($fileProp.Value.Items)
            foreach ($item in $items) {
                $id = [string]$item.ID
                if ([string]::IsNullOrWhiteSpace($id)) {
                    continue
                }

                if ($item.PSObject.Properties["Name"]) {
                    $result["$sourceFile|$id|name|"] = [string]$item.Name
                }
                if ($item.PSObject.Properties["Description"]) {
                    $result["$sourceFile|$id|description|"] = [string]$item.Description
                }
                foreach ($node in @($item.Nodes)) {
                    if ($null -eq $node) {
                        continue
                    }
                    $xpath = [string]$node.XPath
                    $index = ""
                    if ($node.PSObject.Properties["Index"] -and $null -ne $node.Index) {
                        $index = [string]$node.Index
                    }
                    $result["$sourceFile|$id|$xpath|$index"] = [string]$node.Value
                }
            }
        }
    }
    return $result
}

# Primary English.xml text.
Initialize-KnownTextDiscoveryInputs

$zh = Get-JsonFile ".\translations\zh-CN.json"
if (Test-Path -LiteralPath ".\translations\entries.csv") {
    foreach ($entry in Import-Csv -LiteralPath ".\translations\entries.csv" -Encoding UTF8) {
        $translation = $null
        if ($null -ne $zh -and $zh.PSObject.Properties[$entry.Key]) {
            $translation = [string]$zh.PSObject.Properties[$entry.Key].Value
        }
        Add-KnownText `
            -SourceFile "source\English.original.xml" `
            -Original $entry.Text `
            -Translation $translation `
            -Kind "English.xml" `
            -Status ($(if ($translation) { "Translated" } else { "Untranslated" })) `
            -Locator $entry.Key `
            -LocalizationAttempted ($(if ($translation) { "Yes" } else { "No" })) `
            -AttemptStatus ($(if ($translation) { "Mapped" } else { "NotAttempted" }))
    }
}

# Config XML candidates, using static discovery rows for original text and config maps for translations.
$configTranslations = Get-ConfigTranslationMap
if (Test-Path -LiteralPath $StaticCandidatesCsv) {
    foreach ($candidate in Import-Csv -LiteralPath $StaticCandidatesCsv -Encoding UTF8) {
        $sourceFile = [string]$candidate.SourceFile
        $xpath = [string]$candidate.XPath
        if ([string]::IsNullOrWhiteSpace($xpath) -and [string]$candidate.Class -match "Name$") {
            $xpath = "name"
        }
        $index = [string]$candidate.Index
        $key = "$sourceFile|$($candidate.ID)|$xpath|$index"
        $translation = $null
        if ($configTranslations.ContainsKey($key)) {
            $translation = $configTranslations[$key]
        }

        $status = if ($translation) {
            "Translated"
        }
        elseif ([string]$candidate.AlreadyPatched -eq "True") {
            "PatchedTranslationNotResolved"
        }
        else {
            "UntranslatedCandidate"
        }

        $candidateSource = [string]$candidate.SourceFile
            $sourcePath = "source\" + ($candidateSource -replace "\.xml$", ".original.xml")
        $skipReason = ""
        $attemptStatus = if ($translation) { "Mapped" } else { "NotAttempted" }
        if (-not $translation) {
            $skipReason = Get-StaticCandidateSkipReason -Candidate $candidate
            if (-not [string]::IsNullOrWhiteSpace($skipReason)) {
                $attemptStatus = "SkippedByPolicy"
            }
        }

        Add-KnownText `
            -SourceFile $sourcePath `
            -Original ([string]$candidate.Value) `
            -Translation $translation `
            -Kind ([string]$candidate.Class) `
            -Status $status `
            -Locator ("ID=$($candidate.ID); XPath=$($candidate.XPath); Index=$($candidate.Index)") `
            -Safety ([string]$candidate.Safety) `
            -LocalizationAttempted ($(if ($translation) { "Yes" } else { "No" })) `
            -AttemptStatus $attemptStatus `
            -FailureReason $skipReason
    }
}

# DLL/EXE translated maps.
Add-DictionaryMap -Path ".\translations\hardcoded-strings.json" -SourceFile "source\AtTheGatesUI.original.dll" -Kind "UI byte/string map"
Add-DictionaryMap -Path ".\translations\hardcoded-common-strings.json" -SourceFile "source\AtTheGatesCommon.original.dll" -Kind "Common byte/string map"
Add-IlRewriteMap -Path ".\translations\hardcoded-ui-il-rewrite.json" -FallbackSource "source\AtTheGatesUI.original.dll" -Kind "UI IL rewrite"
Add-IlRewriteMap -Path ".\translations\hardcoded-ui-il-strings.json" -FallbackSource "source\AtTheGatesUI.original.dll" -Kind "UI in-place IL string"
Add-IlRewriteMap -Path ".\translations\hardcoded-ui-offsets.json" -FallbackSource "source\AtTheGatesUI.original.dll" -Kind "UI verified offset"
Add-IlRewriteMap -Path ".\translations\hardcoded-common-il-rewrite.json" -FallbackSource "source\AtTheGatesCommon.original.dll" -Kind "Common IL rewrite"
Add-IlRewriteMap -Path ".\translations\hardcoded-common-offsets.json" -FallbackSource "source\AtTheGatesCommon.original.dll" -Kind "Common verified offset"
Add-IlRewriteMap -Path ".\translations\hardcoded-game-il-rewrite.json" -FallbackSource "source\AtTheGatesGame.original.exe" -Kind "Game EXE IL rewrite"
Add-IlRewriteMap -Path ".\translations\hardcoded-elftools-il-rewrite.json" -FallbackSource "source\ElfTools.original.dll" -Kind "ElfTools IL rewrite"

# Trial batch files are used above only as attempt-status evidence. Do not emit
# them as separate source rows; normal maps and unmapped candidates provide the
# actual source-file rows without duplicating review entries.

# Known unmapped DLL display candidates after the most recent trial export.
if (-not [string]::IsNullOrWhiteSpace($UnmappedDllCsv) -and -not (Test-Path -LiteralPath $UnmappedDllCsv)) {
    $fallbackUnmapped = ".\.tmp\trial-current-unmapped-dll.csv"
    if (Test-Path -LiteralPath $fallbackUnmapped) {
        $UnmappedDllCsv = $fallbackUnmapped
    }
}

function Add-UnmappedDllRowsFromCsv {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    foreach ($row in Import-Csv -LiteralPath $Path -Encoding UTF8) {
        $assembly = [string]$row.Assembly
        if ([string]::IsNullOrWhiteSpace($assembly) -and $row.PSObject.Properties["AssemblyName"]) {
            $assembly = [string]$row.AssemblyName
        }
        $assemblyKey = Get-AssemblyKeyFromSourceName $assembly
        $entryKey = Get-ReviewKey -Assembly $assemblyKey -MethodToken ([string]$row.MethodToken) -ILOffset $row.ILOffset

        $original = [string]$row.Original
        if ([string]::IsNullOrWhiteSpace($original) -and $row.PSObject.Properties["Value"]) {
            $original = [string]$row.Value
        }
        if ([string]::IsNullOrWhiteSpace($original)) {
            continue
        }

        $attempt = Get-TrialAttempt -Assembly $assemblyKey -MethodToken ([string]$row.MethodToken) -ILOffset $row.ILOffset
        $translation = ""
        $attempted = "No"
        $attemptStatus = "NotAttempted"
        $failureReason = ""
        $notes = ""
        $status = "UntranslatedDiscovered"

        if ($null -ne $attempt -and [string]$attempt.AttemptStatus -eq "Rejected") {
            $translation = [string]$attempt.Translation
            $attempted = "Yes"
            $attemptStatus = [string]$attempt.AttemptStatus
            $failureReason = [string]$attempt.FailureReason
            $notes = "Trial evidence: $($attempt.Evidence)"
            $status = "RejectedTrial"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($entryKey) -and $script:mappedDllTranslationsByEntryKey.ContainsKey($entryKey)) {
            $mapped = $script:mappedDllTranslationsByEntryKey[$entryKey]
            $translation = [string]$mapped.Translation
            $attempted = "Yes"
            $attemptStatus = "Mapped"
            $status = "Translated"
            $notes = [string]$mapped.Notes
        }
        else {
            $originalMapKey = "$assemblyKey$([char]31)$original"
            if ($script:mappedDllTranslationsByAssemblyOriginal.ContainsKey($originalMapKey)) {
                $mappedByOriginal = $script:mappedDllTranslationsByAssemblyOriginal[$originalMapKey]
                if (-not [bool]$mappedByOriginal.Ambiguous) {
                    $translation = [string]$mappedByOriginal.Translation
                    $attempted = "Yes"
                    $attemptStatus = "MappedByOriginal"
                    $status = "Translated"
                    $notes = "Translation matched by assembly and original text; inspect locator before using as an IL patch source."
                }
            }

            if ($null -eq $attempt -and [string]::IsNullOrWhiteSpace($translation)) {
                $reviewReason = Get-DllSkipReason -Row $row
                if ($reviewReason -match '^Trial candidate:') {
                    $attemptStatus = "TrialCandidate"
                    $failureReason = $reviewReason
                }
                elseif (-not [string]::IsNullOrWhiteSpace($reviewReason)) {
                    $attemptStatus = "SkippedByPolicy"
                    $failureReason = $reviewReason
                }
            }
            elseif ($null -ne $attempt -and [string]::IsNullOrWhiteSpace($translation)) {
                $translation = [string]$attempt.Translation
                $attempted = "Yes"
                $attemptStatus = [string]$attempt.AttemptStatus
                $failureReason = [string]$attempt.FailureReason
                $notes = "Trial evidence: $($attempt.Evidence)"
                if ($attemptStatus -eq "Rejected") {
                    $status = "RejectedTrial"
                }
            }
        }

        Add-KnownText `
            -SourceFile (Get-SourceFromAssemblyName $assemblyKey) `
            -Original $original `
            -Translation $translation `
            -Kind ([string]$row.Class) `
            -Status $status `
            -Locator ("TypeFullName=$($row.TypeFullName); MethodName=$($row.MethodName); MethodToken=$($row.MethodToken); ILOffset=$($row.ILOffset)") `
            -LocalizationAttempted $attempted `
            -AttemptStatus $attemptStatus `
            -FailureReason $failureReason `
            -Notes $notes
    }
}

Add-UnmappedDllRowsFromCsv -Path $UnmappedDllCsv
foreach ($catalogPath in @($AdditionalDllCatalogCsv)) {
    Add-UnmappedDllRowsFromCsv -Path $catalogPath
}

$trialStateForRows = Get-JsonFile ".\docs\agent\trial-localization-state.json"
if ($null -ne $trialStateForRows) {
    foreach ($entry in ConvertTo-ReviewArray $trialStateForRows.knownRejectedSingles) {
        Add-KnownText `
            -SourceFile (Get-SourceFromAssemblyName ([string]$entry.assembly)) `
            -Original ([string]$entry.original) `
            -Translation "" `
            -Kind "Known rejected trial" `
            -Status "RejectedTrial" `
            -Locator ("MethodToken=$($entry.methodToken); ILOffset=$($entry.ilOffset)") `
            -LocalizationAttempted "Yes" `
            -AttemptStatus "Rejected" `
            -FailureReason ([string]$entry.reason) `
            -Notes ("Trial state batch: $($entry.batchId)")
    }
}

foreach ($record in $records) {
    if ([string]::IsNullOrWhiteSpace($record.LocalizationAttempted)) {
        if (-not [string]::IsNullOrWhiteSpace($record.Translation)) {
            $record.LocalizationAttempted = "Yes"
            if ([string]::IsNullOrWhiteSpace($record.AttemptStatus)) {
                $record.AttemptStatus = "Mapped"
            }
        }
        else {
            $record.LocalizationAttempted = "No"
            if ([string]::IsNullOrWhiteSpace($record.AttemptStatus)) {
                $record.AttemptStatus = "NotAttempted"
            }
        }
    }

    $reviewState = Get-ReviewState -Record $record
    $reasonCode = Get-ReviewReasonCode -Record $record -ReviewState $reviewState
    $record | Add-Member -Force -MemberType NoteProperty -Name ReviewState -Value $reviewState
    $record | Add-Member -Force -MemberType NoteProperty -Name ReasonCode -Value $reasonCode
}

if ($AggregateDuplicates) {
    $separator = [char]31
    $groups = @{}
    foreach ($record in $records) {
        $key = @($record.SourceFile, $record.Original, $record.Translation, $record.Kind, $record.Status, $record.Safety, $record.ReviewState, $record.ReasonCode, $record.Notes) -join $separator
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                SourceFile = $record.SourceFile
                Original = $record.Original
                Translation = $record.Translation
                Kind = $record.Kind
                Status = $record.Status
                Safety = $record.Safety
                ReviewState = $record.ReviewState
                ReasonCode = $record.ReasonCode
                Notes = $record.Notes
                Locator = ""
                Locators = New-Object System.Collections.Generic.List[string]
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($record.Locator)) {
            $groups[$key].Locators.Add($record.Locator) | Out-Null
        }
    }

    $items = @($groups.GetEnumerator() | ForEach-Object {
        $_.Value.Locator = (@($_.Value.Locators) -join " | ")
        $_.Value
    } | Sort-Object SourceFile, Status, Kind, Original, Locator)
}
else {
    $items = @($records | Sort-Object SourceFile, Status, Kind, Original, Locator)
}

$translatedCount = @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Translation) }).Count
$untranslatedCount = $items.Count - $translatedCount
$translatedStateCount = @($items | Where-Object { $_.ReviewState -eq "Translated" }).Count
$needsTrialCount = @($items | Where-Object { $_.ReviewState -eq "NeedsTrial" }).Count
$skippedCount = @($items | Where-Object { $_.ReviewState -eq "Skipped" }).Count
$recheckedSkippedCount = @($items | Where-Object { $_.ReviewState -eq "RecheckedSkipped" }).Count
$rejectedCount = @($items | Where-Object { $_.ReviewState -eq "Rejected" }).Count

$csvOutputDirectory = Split-Path -Parent $CsvOutputPath
if (-not [string]::IsNullOrWhiteSpace($csvOutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $csvOutputDirectory | Out-Null
}

$csvRows = foreach ($item in $items) {
    [pscustomobject][ordered]@{
        SourceFile = $item.SourceFile
        Kind = $item.Kind
        Original = $item.Original
        Translation = $item.Translation
        Status = $item.Status
        ReviewState = $item.ReviewState
        ReasonCode = $item.ReasonCode
        Safety = $item.Safety
        Notes = $item.Notes
        Locators = $item.Locator
    }
}

$csvRows | Export-Csv -LiteralPath $CsvOutputPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    CsvOutputPath = (Resolve-Path -LiteralPath $CsvOutputPath).Path
    Rows = $items.Count
    UniqueRows = $items.Count
    TranslatedRows = $translatedCount
    UntranslatedRows = $untranslatedCount
    TranslatedStateRows = $translatedStateCount
    NeedsTrialRows = $needsTrialCount
    SkippedRows = $skippedCount
    RecheckedSkippedRows = $recheckedSkippedCount
    RejectedRows = $rejectedCount
    SourceFileCount = @($items | Select-Object -ExpandProperty SourceFile -Unique).Count
}

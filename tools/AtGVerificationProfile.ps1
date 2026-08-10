function Get-AtGVerificationProjectRoot {
    param([string]$ProjectRoot)

    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
    }

    return (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Get-AtGVerificationSuiteManifest {
    param([string]$ProjectRoot)

    $root = Get-AtGVerificationProjectRoot -ProjectRoot $ProjectRoot
    $path = Join-Path $root 'tools\power-shell-test-suite.json'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Verification suite manifest is missing: $path"
    }

    try {
        $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Verification suite manifest is not valid JSON: $path. $($_.Exception.Message)"
    }

    if ($null -eq $manifest -or [int]$manifest.SchemaVersion -ne 2) {
        throw "Unsupported verification suite manifest schema: '$($manifest.SchemaVersion)'."
    }
    if ($null -eq $manifest.PathCategories -or $null -eq $manifest.Tests -or
        $null -eq $manifest.DotNetTestGroups) {
        throw 'Verification suite manifest is missing PathCategories, Tests, or DotNetTestGroups.'
    }

    return $manifest
}

function ConvertTo-AtGVerificationRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $value = $Path.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@('\', '/'))
    $candidate = if ([IO.Path]::IsPathRooted($value)) {
        [IO.Path]::GetFullPath($value)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $root $value))
    }

    if (!$candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
        !$candidate.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }

    return $candidate.Substring($root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

function Test-AtGVerificationPathPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $normalizedPattern = $Pattern.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalizedPattern)) {
        return $false
    }

    $regex = [regex]::Escape($normalizedPattern)
    $regex = $regex.Replace('\*\*', '.*').Replace('\*', '[^/]*')
    return $Path -match ('(?i)^' + $regex + '$')
}

function Get-AtGChangedPathCategories {
    param(
        [string[]]$ChangedPath = @(),
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $normalizedPaths = New-Object System.Collections.Generic.List[string]
    $categories = New-Object System.Collections.Generic.List[string]
    $unmappedPaths = New-Object System.Collections.Generic.List[string]

    foreach ($changed in @($ChangedPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$changed)) {
            continue
        }

        $relative = ConvertTo-AtGVerificationRelativePath -Path ([string]$changed) -ProjectRoot $ProjectRoot
        if ($null -eq $relative) {
            $unmappedPaths.Add([string]$changed)
            continue
        }

        $normalizedPaths.Add($relative)
        $matched = $false
        foreach ($category in @($Manifest.PathCategories)) {
            $categoryId = [string]$category.Id
            $patterns = @($category.Patterns | ForEach-Object { [string]$_ })
            if ([string]::IsNullOrWhiteSpace($categoryId) -or $patterns.Count -eq 0) {
                throw 'Verification suite manifest contains an incomplete path category.'
            }

            if (@($patterns | Where-Object {
                    Test-AtGVerificationPathPattern -Path $relative -Pattern $_
                }).Count -gt 0) {
                $categories.Add($categoryId)
                $matched = $true
            }
        }

        if (!$matched) {
            $unmappedPaths.Add($relative)
        }
    }

    if ($normalizedPaths.Count -eq 0 -and $unmappedPaths.Count -eq 0) {
        $unmappedPaths.Add('<no ChangedPath supplied>')
    }

    [pscustomobject]@{
        ChangedPaths = @($normalizedPaths | Select-Object -Unique)
        Categories = @($categories | Select-Object -Unique)
        UnmappedChangedPaths = @($unmappedPaths | Select-Object -Unique)
    }
}

function Test-AtGVerificationItemSelected {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][string]$Profile,
        [string[]]$Categories = @(),
        [switch]$DocumentationOnly
    )

    $profiles = @($Item.Profiles | ForEach-Object { [string]$_ })
    if ($profiles -notcontains $Profile) {
        return $false
    }

    $triggers = @($Item.Triggers | ForEach-Object { [string]$_ })
    if ($DocumentationOnly) {
        return $triggers -contains 'documentation'
    }

    if ($Profile -eq 'Release') {
        return $true
    }

    $alwaysForLocalization = $Item.PSObject.Properties['AlwaysForLocalization']
    if ($null -ne $alwaysForLocalization -and [bool]$alwaysForLocalization.Value) {
        return $true
    }

    return @($triggers | Where-Object { $Categories -contains $_ }).Count -gt 0
}

function Resolve-AtGVerificationSelection {
    param(
        [ValidateSet('Localization', 'Release')]
        [string]$Profile = 'Localization',

        [string[]]$ChangedPath = @(),

        [string]$ProjectRoot
    )

    $root = Get-AtGVerificationProjectRoot -ProjectRoot $ProjectRoot
    $manifest = Get-AtGVerificationSuiteManifest -ProjectRoot $root
    $pathSelection = Get-AtGChangedPathCategories -ChangedPath $ChangedPath -Manifest $manifest -ProjectRoot $root
    $tests = @($manifest.Tests)
    $dotNetTests = @($manifest.DotNetTestGroups)
    $isDocumentationOnly = $Profile -eq 'Localization' -and
        @($pathSelection.ChangedPaths).Count -gt 0 -and
        @($pathSelection.UnmappedChangedPaths).Count -eq 0 -and
        @($pathSelection.Categories).Count -gt 0 -and
        @($pathSelection.Categories | Where-Object { $_ -ne 'documentation' }).Count -eq 0

    foreach ($item in @($tests + $dotNetTests)) {
        $id = [string]$item.Id
        $profiles = @($item.Profiles | ForEach-Object { [string]$_ })
        $triggers = @($item.Triggers | ForEach-Object { [string]$_ })
        if ([string]::IsNullOrWhiteSpace($id) -or $profiles.Count -eq 0 -or $triggers.Count -eq 0) {
            throw 'Verification suite manifest contains an item without Id, Profiles, or Triggers.'
        }
    }

    $selectedTests = @($tests | Where-Object {
            Test-AtGVerificationItemSelected -Item $_ -Profile $Profile -Categories $pathSelection.Categories `
                -DocumentationOnly:$isDocumentationOnly
        })
    $selectedDotNetTests = @($dotNetTests | Where-Object {
            Test-AtGVerificationItemSelected -Item $_ -Profile $Profile -Categories $pathSelection.Categories `
                -DocumentationOnly:$isDocumentationOnly
        })
    $staticTests = @($selectedTests | Where-Object { [string]$_.Kind -eq 'Static' })
    $smokeTests = @($selectedTests | Where-Object { [string]$_.Kind -eq 'Smoke' })

    if ($staticTests.Count -eq 0) {
        throw "Verification profile '$Profile' selected no static PowerShell checks."
    }
    if ($selectedDotNetTests.Count -eq 0) {
        throw "Verification profile '$Profile' selected no .NET test groups."
    }
    if ($isDocumentationOnly -and $smokeTests.Count -ne 0) {
        throw "Documentation-only verification must not select a game smoke assertion; selected $($smokeTests.Count)."
    }
    if (!$isDocumentationOnly -and $smokeTests.Count -ne 1) {
        throw "Verification profile '$Profile' must select exactly one smoke assertion; selected $($smokeTests.Count)."
    }

    $prerequisites = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($selectedTests + $selectedDotNetTests)) {
        foreach ($prerequisite in @($item.EnvironmentPrerequisites | ForEach-Object { [string]$_ })) {
            if (![string]::IsNullOrWhiteSpace($prerequisite)) {
                $prerequisites.Add($prerequisite)
            }
        }
    }

    [pscustomobject]@{
        SchemaVersion = [int]$manifest.SchemaVersion
        Profile = $Profile
        IsDocumentationOnly = [bool]$isDocumentationOnly
        RequiresGameTransaction = !$isDocumentationOnly
        ChangedPaths = @($pathSelection.ChangedPaths)
        ChangedPathCategories = @($pathSelection.Categories)
        UnmappedChangedPaths = @($pathSelection.UnmappedChangedPaths)
        StaticTests = @($staticTests)
        SmokeTests = @($smokeTests)
        DotNetTestGroups = @($selectedDotNetTests)
        EnvironmentPrerequisites = @($prerequisites | Select-Object -Unique)
        OmittedStaticTests = @($tests | Where-Object {
                [string]$_.Kind -eq 'Static' -and $selectedTests.Id -notcontains [string]$_.Id
            })
    }
}

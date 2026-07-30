function Get-AtGInstallationNotice {
    $message = @(
        "This is a free, strictly non-commercial, unofficial fan-made patch.",
        "",
        "It does not include or redistribute any original At the Gates game files. You must own a legitimate copy of the game.",
        "",
        "Conifer Games cannot provide technical support for modified installations. Please send crash reports and technical issues from patched games to this project, not to Conifer Games:",
        "https://github.com/TsuTa-hl/At-the-Gates-Chinese-Patch/issues",
        "",
        "Permission to release and promote this patch is granted in good faith and may be revoked."
    ) -join [Environment]::NewLine

    return [pscustomobject]@{
        Title   = "At the Gates Simplified Chinese Patch Notice"
        Message = $message
    }
}

function Show-AtGInstallationNotice {
    $notice = Get-AtGInstallationNotice

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            $notice.Message,
            $notice.Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        Write-Warning ($notice.Title + [Environment]::NewLine + $notice.Message)
    }
}

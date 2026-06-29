param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [Parameter(Mandatory = $true)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [int]$Height
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Source image not found: $SourcePath"
}
if ($Width -le 0 -or $Height -le 0) {
    throw "Crop width and height must be positive."
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $SourcePath).Path)
try {
    if ($X -lt 0 -or $Y -lt 0 -or $X + $Width -gt $source.Width -or $Y + $Height -gt $source.Height) {
        throw "Crop rectangle ($X,$Y,$Width,$Height) is outside source image $($source.Width)x$($source.Height)."
    }

    $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.DrawImage(
            $source,
            [System.Drawing.Rectangle]::new(0, 0, $Width, $Height),
            [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height),
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
finally {
    $source.Dispose()
}

[pscustomobject]@{
    Source = (Resolve-Path -LiteralPath $SourcePath).Path
    Output = (Resolve-Path -LiteralPath $OutputPath).Path
    X = $X
    Y = $Y
    Width = $Width
    Height = $Height
}

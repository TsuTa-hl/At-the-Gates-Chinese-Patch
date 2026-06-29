param(
    [Parameter(Mandatory = $true)]
    [string[]]$ImagePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$Columns = 3,
    [int]$CellWidth = 640,
    [int]$CellHeight = 360,
    [int]$Padding = 0
)

$ErrorActionPreference = "Stop"

if ($Columns -le 0) {
    throw "Columns must be positive."
}
if ($CellWidth -le 0 -or $CellHeight -le 0) {
    throw "Cell dimensions must be positive."
}
if ($ImagePath.Count -eq 0) {
    throw "At least one image is required."
}

foreach ($path in @($ImagePath)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Image not found: $path"
    }
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Add-Type -AssemblyName System.Drawing
$rows = [int][Math]::Ceiling([double]$ImagePath.Count / [double]$Columns)
$sheetWidth = ($Columns * $CellWidth) + ([Math]::Max(0, $Columns - 1) * $Padding)
$sheetHeight = ($rows * $CellHeight) + ([Math]::Max(0, $rows - 1) * $Padding)

$sheet = New-Object System.Drawing.Bitmap $sheetWidth, $sheetHeight
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
try {
    $graphics.Clear([System.Drawing.Color]::Black)
    for ($i = 0; $i -lt $ImagePath.Count; $i++) {
        $image = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $ImagePath[$i]).Path)
        try {
            $column = $i % $Columns
            $row = [int][Math]::Floor([double]$i / [double]$Columns)
            $cellX = $column * ($CellWidth + $Padding)
            $cellY = $row * ($CellHeight + $Padding)

            $scale = [Math]::Min([double]$CellWidth / [double]$image.Width, [double]$CellHeight / [double]$image.Height)
            $drawWidth = [int][Math]::Round($image.Width * $scale)
            $drawHeight = [int][Math]::Round($image.Height * $scale)
            $drawX = $cellX + [int][Math]::Floor(($CellWidth - $drawWidth) / 2)
            $drawY = $cellY + [int][Math]::Floor(($CellHeight - $drawHeight) / 2)

            $graphics.DrawImage($image, $drawX, $drawY, $drawWidth, $drawHeight)
        }
        finally {
            $image.Dispose()
        }
    }

    $sheet.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $sheet.Dispose()
}

[pscustomobject]@{
    Output = (Resolve-Path -LiteralPath $OutputPath).Path
    Images = $ImagePath.Count
    Columns = $Columns
    Rows = $rows
    Width = $sheetWidth
    Height = $sheetHeight
}

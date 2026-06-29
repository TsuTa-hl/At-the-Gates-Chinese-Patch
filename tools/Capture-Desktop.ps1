param(
    [string]$OutputPath = "$PSScriptRoot\..\.tmp\desktop.png"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$outDir = Split-Path -Parent $OutputPath
if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen(
    [System.Drawing.Point]::new($bounds.Left, $bounds.Top),
    [System.Drawing.Point]::Empty,
    [System.Drawing.Size]::new($bounds.Width, $bounds.Height)
)
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

[pscustomobject]@{
    Screenshot = (Resolve-Path -LiteralPath $OutputPath).Path
    Left = $bounds.Left
    Top = $bounds.Top
    Width = $bounds.Width
    Height = $bounds.Height
    Screens = @(
        [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
            [pscustomobject]@{
                Device = $_.DeviceName
                Left = $_.Bounds.X
                Top = $_.Bounds.Y
                Width = $_.Bounds.Width
                Height = $_.Bounds.Height
                Primary = $_.Primary
            }
        }
    )
}

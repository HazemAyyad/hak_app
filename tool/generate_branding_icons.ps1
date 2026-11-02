# Run from the project root. Composite iOS artwork before the icon generator:
# flutter_launcher_icons 0.14.4 incorrectly blends partially transparent pixels.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = [Drawing.Bitmap]::new((Join-Path $projectRoot 'assets/branding/haq_app_icon.png'))
$opaque = [Drawing.Bitmap]::new($source.Width, $source.Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
$graphics = [Drawing.Graphics]::FromImage($opaque)
try {
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#102A43'))
    $graphics.DrawImage($source,
        [Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height),
        0, 0, $source.Width, $source.Height, [Drawing.GraphicsUnit]::Pixel)
    $opaque.Save((Join-Path $projectRoot 'assets/branding/haq_app_icon_ios.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $opaque.Dispose()
    $source.Dispose()
}
Push-Location $projectRoot
try {
    dart run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw 'Icon generation failed.' }
} finally { Pop-Location }

# Draws the 1024x1024 App Store icon (no transparency, as Apple requires).
# Windows only (uses System.Drawing). Run from the project root:
#   powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1

Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'ios/Rerun/Assets.xcassets/AppIcon.appiconset/icon-1024.png'

$S = 1024
$bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
function Col($hex, $a = 255) { [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($hex.Substring(0,2),16), [Convert]::ToInt32($hex.Substring(2,2),16), [Convert]::ToInt32($hex.Substring(4,2),16)) }

# Background: deep navy with a soft centre glow
$g.Clear((Col '070918'))
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddEllipse(-200, -200, $S + 400, $S + 400)
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
$glow.CenterColor = (Col '16205a'); $glow.SurroundColors = @((Col '070918'))
$g.FillRectangle($glow, 0, 0, $S, $S)

$cx = 512; $cy = 512; $R = 330; $band = 150
# Track band
$pen = New-Object System.Drawing.Pen((Col '1a2558'), $band)
$g.DrawEllipse($pen, $cx - $R, $cy - $R, 2 * $R, 2 * $R)
# Lane guides: dotted yellow
foreach ($lr in @(($R - 34), ($R + 34))) {
  $p = New-Object System.Drawing.Pen((Col 'ffd84d' 60), 6)
  $p.DashPattern = @(1.2, 3.2)
  $g.DrawEllipse($p, $cx - $lr, $cy - $lr, 2 * $lr, 2 * $lr)
}
# Chequered start strip at the top
$sq = 26; $y0 = $cy - $R - 75
for ($row = 0; $row -lt 6; $row++) { for ($col = 0; $col -lt 2; $col++) { if ((($row + $col) % 2) -eq 0) {
  $g.FillRectangle((New-Object System.Drawing.SolidBrush((Col 'ffd84d'))), $cx - $sq + $col * $sq, $y0 + $row * $sq, $sq, $sq) } } }

function Pt($ang, $rad) { $a = ($ang - 90) * [Math]::PI / 180; return @(($cx + $rad * [Math]::Cos($a)), ($cy + $rad * [Math]::Sin($a))) }

# Ghost (past you) on the inner lane, lower left
$gp = Pt 225 ($R - 34); $gr = 58
$g.FillEllipse((New-Object System.Drawing.SolidBrush((Col 'ff9a4d' 70))), $gp[0] - $gr, $gp[1] - $gr, 2 * $gr, 2 * $gr)
$g.DrawEllipse((New-Object System.Drawing.Pen((Col 'ffb070'), 10)), $gp[0] - $gr, $gp[1] - $gr, 2 * $gr, 2 * $gr)

# Player on the outer lane, right side, with a fading trail
for ($k = 7; $k -ge 1; $k--) {
  $tp = Pt (100 - $k * 5) ($R + 34); $tr = 70 - $k * 5
  $g.FillEllipse((New-Object System.Drawing.SolidBrush((Col 'ff6a4d' ([int](70 - $k * 8))))), $tp[0] - $tr, $tp[1] - $tr, 2 * $tr, 2 * $tr)
}
$pp = Pt 100 ($R + 34); $pr = 78
for ($k = 4; $k -ge 1; $k--) { $hr = $pr + $k * 14; $g.FillEllipse((New-Object System.Drawing.SolidBrush((Col 'ff6a4d' 18))), $pp[0] - $hr, $pp[1] - $hr, 2 * $hr, 2 * $hr) }
$g.FillEllipse((New-Object System.Drawing.SolidBrush((Col 'ff6a4d'))), $pp[0] - $pr, $pp[1] - $pr, 2 * $pr, 2 * $pr)
# Eyes, looking ahead (clockwise = downward on the right side)
foreach ($s in @(-1, 1)) {
  $ex = $pp[0] + $s * 30; $ey = $pp[1] + 6; $er = 22
  $g.FillEllipse([System.Drawing.Brushes]::White, $ex - $er, $ey - $er, 2 * $er, 2 * $er)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush((Col '070918'))), $ex - 9, $ey + 2, 20, 20)
}
# Star pickup on the inner lane, top left
$sp = Pt 315 ($R - 34); $sr = 40
$pts = @(); for ($i = 0; $i -lt 10; $i++) { $a = (-90 + $i * 36) * [Math]::PI / 180; $rr = if ($i % 2) { $sr * 0.45 } else { $sr }; $pts += New-Object System.Drawing.PointF(($sp[0] + $rr * [Math]::Cos($a)), ($sp[1] + $rr * [Math]::Sin($a))) }
$g.FillPolygon((New-Object System.Drawing.SolidBrush((Col 'ffd84d'))), [System.Drawing.PointF[]]$pts)

$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Saved $out"

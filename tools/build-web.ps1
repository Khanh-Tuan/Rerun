# Builds web/index.html (the standalone page the iOS app loads) from src/afterlap.html.
# Run from the project root after editing src/afterlap.html:
#   powershell -ExecutionPolicy Bypass -File tools\build-web.ps1
# Works in Windows PowerShell 5.1 and in PowerShell 7 (pwsh) on macOS.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src/afterlap.html'
$out  = Join-Path $root 'web/index.html'

$game = [System.IO.File]::ReadAllText($src)

$head = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="theme-color" content="#070918">
<meta name="format-detection" content="telephone=no">
<style>html{-webkit-text-size-adjust:100%}body{-webkit-touch-callout:none}</style>
</head>
<body>
'@

$tail = @'

</body>
</html>
'@

New-Item -ItemType Directory -Force (Split-Path -Parent $out) | Out-Null
[System.IO.File]::WriteAllText($out, $head + $game + $tail, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Built $out"

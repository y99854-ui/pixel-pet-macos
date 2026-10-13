param([string]$Source, [string]$Output)
$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Source -Raw
$palette = @{}
$colors = @{}
$paletteSection = $text.Substring($text.IndexOf('$palette = @{'), $text.IndexOf('# A separate overlay') - $text.IndexOf('$palette = @{'))
foreach ($match in [regex]::Matches($paletteSection, '(\w+)\s*= New-Object System.Windows.Media.SolidColorBrush \(\[System.Windows.Media.Color\]::From(Rgb|Argb)\(([^)]+)\)\)')) {
    $palette[$match.Groups[1].Value] = $match.Groups[1].Value
    $argb = @($match.Groups[3].Value.Split(',') | ForEach-Object { [int]$_.Trim() })
    if ($match.Groups[2].Value -eq 'Rgb') { $argb = @(255) + $argb }
    $colors[$match.Groups[1].Value] = $argb
}
$canvas = @{ Children = [System.Collections.Generic.List[object]]::new() }
function Add-PixelRect {
    param([double]$X, [double]$Y, [double]$W, [double]$H, [string]$Brush, [double]$YOffset = 0)
    $canvas.Children.Add(@{ x = $X * 6; y = $Y * 6 + $YOffset; width = $W * 6; height = $H * 6; color = $Brush })
}
$start = $text.IndexOf('function Draw-Heart {')
$end = $text.IndexOf('function Clamp-ToWorkArea {')
# Trusted repository drawing code only; the WPF startup and native calls are excluded.
. ([scriptblock]::Create($text.Substring($start, $end - $start)))
$frames = @{}
foreach ($style in @('GrayCat', 'Corgi', 'Hamster', 'TuxCorgi', 'BlackCat', 'FlowerBloom')) {
    $script:petStyle = $style
    $variants = @{}
    foreach ($tail in @(0,1)) { foreach ($blink in @($false,$true)) {
        Draw-Pet $tail $blink 0 $false
        $key = "$tail-$(if ($blink) { 1 } else { 0 })"
        $variants[$key] = @($canvas.Children.ToArray())
    } }
    $frames[$style] = $variants
}
$mats = @{}
$matStart = $text.IndexOf('$matColors = @{')
$matEnd = $text.IndexOf('$matPalettes = @{}')
foreach ($match in [regex]::Matches($text.Substring($matStart, $matEnd - $matStart), '(\w+) = @\(([^)]+)\)')) {
    $mats[$match.Groups[1].Value] = @([regex]::Matches($match.Groups[2].Value, '#([A-F0-9]+)') | ForEach-Object { $_.Groups[1].Value })
}
@{ palette = $colors; frames = $frames; mats = $mats } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $Output -Encoding utf8

# LMPM 단일 앱 아이콘 생성기 (컬러 배경 + 흰 미터바 — 스토어/런처에서 또렷)
# System.Drawing 으로 1024x1024 PNG 한 장(app_icon.png)을 만든다.
Add-Type -AssemblyName System.Drawing

$S = 1024

# 막대 높이 프로파일(아치형) — 기존 아이콘과 동일한 라우드니스 미터 실루엣
$profile = @(0.42, 0.66, 1.00, 0.78, 0.52)

function RoundRect($path, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $d = $r * 2
    $path.Reset()
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
}

$g = $null
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::Transparent)

# ---- 배경: 코발트 → 딥블루 대각선 그라데이션, 라운드 사각 ----
$bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
RoundRect $bgPath 0 0 $S $S ($S * 0.22)
$rect = New-Object System.Drawing.Rectangle 0, 0, $S, $S
$top    = [System.Drawing.Color]::FromArgb(255, 79, 163, 255)  # #4FA3FF (앱 primary)
$bottom = [System.Drawing.Color]::FromArgb(255, 30, 64, 175)   # #1E40AF (딥블루)
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 55.0
$g.FillPath($bgBrush, $bgPath)
$bgBrush.Dispose(); $bgPath.Dispose()

# ---- 미터바: 흰색(레벨) + 반투명 흰색(트랙) ----
$WHITE = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
$TRACK = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 255, 255, 255))

$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$n = $profile.Count
$areaW = $S * 0.60
$areaH = $S * 0.52
$areaX = ($S - $areaW) / 2
$areaY = ($S - $areaH) / 2
$gap = $areaW * 0.07
$barW = ($areaW - $gap * ($n - 1)) / $n
$radius = $barW * 0.42

for ($i = 0; $i -lt $n; $i++) {
    $frac = [double]$profile[$i]
    $bh = $areaH * $frac
    $bx = $areaX + $i * ($barW + $gap)
    $by = $areaY + ($areaH - $bh)

    RoundRect $path $bx $areaY $barW $areaH $radius   # 트랙
    $g.FillPath($TRACK, $path)
    RoundRect $path $bx $by $barW $bh $radius          # 레벨
    $g.FillPath($WHITE, $path)
}

$WHITE.Dispose(); $TRACK.Dispose(); $path.Dispose()
$g.Dispose()

$out = Join-Path $PSScriptRoot "app_icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"Saved: $out (1024x1024)"

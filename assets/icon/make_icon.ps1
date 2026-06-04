# LUFS Monitor 앱 아이콘 생성기 (Stream Watcher 스타일: 화이트 배경 + 플랫 블루 아이콘)
# System.Drawing 으로 1024x1024 PNG 두 장을 만든다:
#   icon.png     — 레거시/iOS 용 (화이트 라운드 배경 + 플랫 블루 미터 바)
#   icon_fg.png  — 안드로이드 적응형 전경 (투명 배경, 플랫 블루 미터 바)
Add-Type -AssemblyName System.Drawing

$S = 1024

# 막대 높이 프로파일(아치형)
$profile = @(0.42, 0.66, 1.00, 0.78, 0.52)

# 메인 블루(코발트) / 연한 블루 트랙
$BLUE  = [System.Drawing.Color]::FromArgb(255, 37, 99, 235)    # #2563EB
$TRACK = [System.Drawing.Color]::FromArgb(255, 219, 233, 252)  # 연한 블루

function RoundRect($path, [single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $d = $r * 2
    $path.Reset()
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
}

# 플랫 미터 바를 중앙 정사각 영역(box)에 그린다 (텍스트/그라데이션/하이라이트 없음)
function DrawMeter($g, [single]$boxX, [single]$boxY, [single]$boxSize) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath

    $n = $profile.Count
    $areaW = $boxSize * 0.62
    $areaH = $boxSize * 0.56
    $areaX = $boxX + ($boxSize - $areaW) / 2
    $areaY = $boxY + ($boxSize - $areaH) / 2

    $gap = $areaW * 0.07
    $barW = ($areaW - $gap * ($n - 1)) / $n
    $radius = $barW * 0.40

    $trackBrush = New-Object System.Drawing.SolidBrush $TRACK
    $barBrush   = New-Object System.Drawing.SolidBrush $BLUE

    for ($i = 0; $i -lt $n; $i++) {
        $frac = [double]$profile[$i]
        $bh = $areaH * $frac
        $bx = $areaX + $i * ($barW + $gap)
        $by = $areaY + ($areaH - $bh)

        # 트랙(연한 블루 배경 막대)
        RoundRect $path $bx $areaY $barW $areaH $radius
        $g.FillPath($trackBrush, $path)

        # 실제 레벨 막대 (플랫 블루)
        RoundRect $path $bx $by $barW $bh $radius
        $g.FillPath($barBrush, $path)
    }

    $trackBrush.Dispose()
    $barBrush.Dispose()
    $path.Dispose()
}

function NewGraphics($bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g
}

$outDir = $PSScriptRoot

# ---- 1) 레거시 아이콘 (화이트 라운드 배경) ----
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = NewGraphics $bmp
$g.Clear([System.Drawing.Color]::Transparent)

$bg = New-Object System.Drawing.Drawing2D.GraphicsPath
RoundRect $bg 0 0 $S $S ($S * 0.22)
$bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 248, 251, 255))
$g.FillPath($bgBrush, $bg)
$bgBrush.Dispose(); $bg.Dispose()

DrawMeter $g 0 0 $S
$g.Dispose()
$bmp.Save((Join-Path $outDir "icon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

# ---- 2) 적응형 전경 (투명, 안전영역 안에) ----
$bmp2 = New-Object System.Drawing.Bitmap $S, $S
$g2 = NewGraphics $bmp2
$g2.Clear([System.Drawing.Color]::Transparent)
# 안전영역: 중앙 ~66% 안에 배치
$inset = $S * 0.18
DrawMeter $g2 $inset $inset ($S - 2*$inset)
$g2.Dispose()
$bmp2.Save((Join-Path $outDir "icon_fg.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp2.Dispose()

"Saved: icon.png, icon_fg.png in $outDir"

# ============================================================
# Powershell Fish Tank
# N: New Tank | F: Drop Food | S: Spawn Fish | K: Kill Fish | P: Pause | W: Water
# PgUp/PgDn: Speed | Q/Esc: Quit
# ============================================================

$ESC = [char]27   # 5.1 has no `e escape
$DEG = [char]176   # degree sign, kept out of the source so file encoding can't mangle it

$script:ScreenWidth = 0
$script:ScreenHeight = 0
$script:TankGrid = $null
$script:CurrentFrame = 0
$script:FishIdCounter = 0
$script:RandomGenerator = [System.Random]::new()
$script:BubbleList = [System.Collections.Generic.List[object]]::new()
$script:AnemoneList = [System.Collections.Generic.List[object]]::new()
$script:JellyfishList = [System.Collections.Generic.List[object]]::new()
$script:SeahorseList = [System.Collections.Generic.List[object]]::new()
$script:FishList = [System.Collections.Generic.List[object]]::new()
$script:FoodList = [System.Collections.Generic.List[object]]::new()
$script:TankSnail = @{ XCoordinate = 2; YCoordinate = 2; SnailDirection = 1 }
$script:TickDelay = 16
$script:ShouldQuit = $false
$script:IsPaused = $false

# ---------- render state ----------
# all flat arrays, index = y * width + x
$script:LastRenderBuffer = $null                                   # what's on screen right now
$script:StaticLayer      = $null                                   # glass, sand, castle, anemones
$script:OverlayLayer     = $null                                   # snail, jellyfish, seahorses
$script:BubbleLayer      = $null                                   # bubbles
$script:OverlayTouched   = [System.Collections.Generic.List[int]]::new()
$script:BubbleTouched    = [System.Collections.Generic.List[int]]::new()
$script:ChangedSet       = [System.Collections.Generic.HashSet[int]]::new()
$script:FishStringCache  = @{}
$script:WaterStrings     = $null
$script:SwayIndex        = $null
$script:SwayFrame        = -1
$script:PlantColumnsByRow = $null
$script:LastLegendKey    = $null
$script:RenderBuilder    = [System.Text.StringBuilder]::new(65536)
$script:WaveOffset       = -1
$script:WaveShift        = 0
$script:ResizeTimer      = [System.Diagnostics.Stopwatch]::StartNew()
$script:PendingSize      = $null

# Colors
$script:FishColors = @(
    "${ESC}[38;5;202m", "${ESC}[38;5;208m", "${ESC}[38;5;214m",
    "${ESC}[38;5;215m", "${ESC}[38;5;209m"
)
$script:TetraColors = @(
    "${ESC}[38;5;39m", "${ESC}[38;5;45m", "${ESC}[38;5;81m",
    "${ESC}[38;5;33m", "${ESC}[38;5;75m"
)
$script:GreenColors = @(
    "${ESC}[38;5;40m", "${ESC}[38;5;46m", "${ESC}[38;5;82m", "${ESC}[38;5;118m", "${ESC}[38;5;154m"
)
$script:PinkColors = @(
    "${ESC}[38;5;198m", "${ESC}[38;5;205m", "${ESC}[38;5;211m", "${ESC}[38;5;213m", "${ESC}[38;5;218m"
)
# flavor picks the palette: 0 orange, 1 blue, 2 green, 3 pink
$script:FishPalettes = @($script:FishColors, $script:TetraColors, $script:GreenColors, $script:PinkColors)
$script:JellyfishColors = @(
    "${ESC}[38;5;39m", "${ESC}[38;5;135m", "${ESC}[38;5;213m", "${ESC}[38;5;51m", "${ESC}[38;5;141m", "${ESC}[38;5;207m"
)
$script:SeahorseColors = @(
    "${ESC}[38;5;224m", "${ESC}[38;5;223m", "${ESC}[38;5;217m", "${ESC}[38;5;222m"
)
$script:PlantColors = @(
    "${ESC}[38;5;34m", "${ESC}[38;5;28m", "${ESC}[38;5;30m", "${ESC}[38;5;118m",
    "${ESC}[38;5;46m", "${ESC}[38;5;82m", "${ESC}[38;5;40m", "${ESC}[38;5;36m"
)
$script:AnemoneColors = @(
    "${ESC}[38;5;53m", "${ESC}[38;5;54m", "${ESC}[38;5;91m", "${ESC}[38;5;92m",
    "${ESC}[38;5;55m", "${ESC}[38;5;97m", "${ESC}[38;5;134m", "${ESC}[38;5;135m"
)

$script:WaterColors1 = @(
    "${ESC}[38;5;17m", "${ESC}[38;5;18m", "${ESC}[38;5;19m", "${ESC}[38;5;20m"
)
$script:WaterColors2 = @(
    "${ESC}[38;5;24m", "${ESC}[38;5;25m", "${ESC}[38;5;26m", "${ESC}[38;5;27m"
)
$script:WaterColors3 = @(
    "${ESC}[38;5;30m", "${ESC}[38;5;31m", "${ESC}[38;5;32m", "${ESC}[38;5;33m"
)
$script:WaterColors4 = @(
    "", "", "", ""
)
$script:CurrentWaterGradient = 0

# prebuilt strings so we're not rebuilding them every frame
$script:GlassString  = "${ESC}[38;5;25m|${ESC}[0m"
$script:SandString   = "${ESC}[1;38;5;136m=${ESC}[0m"
$script:FoodString   = "${ESC}[38;5;172m*${ESC}[0m"
$script:SnailString  = "${ESC}[1;38;5;255m@${ESC}[0m"
$script:BubbleStringO   = "${ESC}[1;38;5;123mo${ESC}[0m"
$script:BubbleStringDeg = "${ESC}[1;38;5;123m${DEG}${ESC}[0m"
# wave pattern, 0 = low, 2 = crest
$script:WavePattern = @(0, 1, 2, 2, 2, 1, 0, 0)
$script:WaveStrings = @("${ESC}[38;5;32m_${ESC}[0m", "${ESC}[38;5;38m-${ESC}[0m", "${ESC}[1;38;5;123m~${ESC}[0m")
# colorIndex * 3 + sway (0 '/', 1 '\', 2 '|')
$script:PlantStrings = @(foreach ($pc in $script:PlantColors) { "$pc/${ESC}[0m"; "$pc\${ESC}[0m"; "$pc|${ESC}[0m" })

# tall anemone top rows, columns -1 0 +1
$script:TallPatterns = @('\|/', ' |/', '\| ', ' | ', '\ /', '/|\')

# Fish sprites
$script:FishSpritesRight = @('><>', '>*(*>', '>*((*>', '>*(((*>', ('>' + $DEG + '(}}-}'))
$script:FishSpritesLeft  = @('<><', '<*)*<', '<*))*<', '<*)))*<', ('<' + $DEG + '){{-{'))
$script:SeahorseSpriteRight = '&'
$script:SeahorseSpriteLeft  = '&'

function Initialize-Cell([string]$cellType = "air") {
    return @{
        Type     = $cellType
        Density  = 0
        Dir      = 1
        FishType = 0
        Segment  = 0
        Updated  = $false
        PlantDir = 0
    }
}

# anything that changes the grid goes through here, so mark it changed here
function Set-GridCell([int]$x, [int]$y, [string]$cellType) {
    if ($x -lt 0 -or $x -ge $script:ScreenWidth -or $y -lt 0 -or $y -ge $script:ScreenHeight) { return }
    $currentCell = $script:TankGrid[$x, $y]
    $currentCell.Type = $cellType
    $currentCell.Density = switch ($cellType) {
        "air"   { 0 }
        "water" { 1 }
        "food"  { 2 }
        "fish"  { 3 }
        "plant" { 4 }
        "sand"  { 5 }
        "glass" { 100 }
        default { 0 }
    }
    [void]$script:ChangedSet.Add(($y * $script:ScreenWidth) + $x)
}

function Set-StaticCell([int]$x, [int]$y, [string]$char, [string]$color) {
    if ($x -le 0 -or $x -ge ($script:ScreenWidth - 1) -or $y -lt 1 -or $y -ge $script:ScreenHeight) { return }
    $script:StaticLayer[($y * $script:ScreenWidth) + $x] = "$color$char${ESC}[0m"
}

function Set-OverlayCell([int]$x, [int]$y, [string]$text) {
    if ($x -lt 0 -or $x -ge $script:ScreenWidth -or $y -lt 0 -or $y -ge $script:ScreenHeight) { return }
    $idx = ($y * $script:ScreenWidth) + $x
    $script:OverlayLayer[$idx] = $text
    $script:OverlayTouched.Add($idx)
    [void]$script:ChangedSet.Add($idx)
}

function Set-AllCellsChanged {
    $total = $script:ScreenWidth * $script:ScreenHeight
    for ($i = $script:ScreenWidth; $i -lt $total; $i++) { [void]$script:ChangedSet.Add($i) }
}

function Get-FishLength([int]$fishSize) {
    return $script:FishSpritesRight[[Math]::Max(0, [Math]::Min(4, $fishSize))].Length
}

function New-FishType {
    $script:FishIdCounter++
    $fishSize   = $script:RandomGenerator.Next($script:FishSpritesRight.Count)
    $fishColor  = $script:RandomGenerator.Next($script:FishColors.Count)
    $fishFlavor = $script:RandomGenerator.Next($script:FishPalettes.Count)
    return ($script:FishIdCounter % 1000) * 1000 + $fishFlavor * 100 + $fishColor * 10 + $fishSize
}

function Get-FishSize([int]$fishType)   { return $fishType % 10 }
function Get-FishColor([int]$fishType)  { return [Math]::Floor(($fishType % 100) / 10) }
function Get-FishFlavor([int]$fishType) { return [Math]::Floor(($fishType % 1000) / 100) }

function Test-CanSpawnFish([int]$x, [int]$y, [int]$fishType, [int]$fishDirection) {
    $fishLength = Get-FishLength (Get-FishSize $fishType)
    $maxX = $script:ScreenWidth - 1
    for ($i = 0; $i -lt $fishLength; $i++) {
        $checkX = $x - ($i * $fishDirection)
        if ($checkX -lt 1 -or $checkX -ge $maxX) { return $false }
        $targetType = $script:TankGrid[$checkX, $y].Type
        if ($targetType -ne "water" -and $targetType -ne "plant") { return $false }
    }
    return $true
}

function Clear-FishFromGrid([int]$x, [int]$y, [int]$fishType, [int]$fishDirection) {
    $fishLength = Get-FishLength (Get-FishSize $fishType)
    for ($i = 0; $i -lt $fishLength; $i++) {
        $checkX = $x - ($i * $fishDirection)
        if ($checkX -lt 0 -or $checkX -ge $script:ScreenWidth) { continue }
        $currentCell = $script:TankGrid[$checkX, $y]
        if ($currentCell.Type -eq "fish" -and $currentCell.FishType -eq $fishType -and $currentCell.Segment -eq $i) {
            if ($currentCell.Density -ge 1000) {
                $savedPlantDirection = $currentCell.Density - 1000
                Set-GridCell $checkX $y "plant"
                $script:TankGrid[$checkX, $y].PlantDir = $savedPlantDirection
            }
            else {
                Set-GridCell $checkX $y "water"
            }
        }
    }
}

function Spawn-Fish([int]$x, [int]$y, [int]$fishType, [int]$fishDirection) {
    if (-not (Test-CanSpawnFish $x $y $fishType $fishDirection)) { return $false }
    $fishLength = Get-FishLength (Get-FishSize $fishType)
    for ($i = 0; $i -lt $fishLength; $i++) {
        $checkX = $x - ($i * $fishDirection)
        $existingCell = $script:TankGrid[$checkX, $y]
        $savedPlantDirection = -1
        if ($existingCell.Type -eq "plant") {
            $savedPlantDirection = $existingCell.PlantDir
        }
        elseif ($existingCell.Type -eq "fish" -and $existingCell.Density -ge 1000) {
            $savedPlantDirection = $existingCell.Density - 1000
        }
        Set-GridCell $checkX $y "fish"
        $currentCell = $script:TankGrid[$checkX, $y]
        $currentCell.Dir = $fishDirection
        $currentCell.FishType = $fishType
        $currentCell.Segment = $i
        $currentCell.Updated = $true
        if ($savedPlantDirection -ne -1) {
            $currentCell.Density = 1000 + $savedPlantDirection
        }
    }
    return $true
}

function Update-WaterCache {
    $height = $script:ScreenHeight
    $script:WaterStrings = New-Object 'string[]' $height
    for ($y = 1; $y -lt $height; $y++) {
        if ($script:CurrentWaterGradient -eq 3) {
            $script:WaterStrings[$y] = " "
        } else {
            $script:WaterStrings[$y] = (Get-WaterColor $y) + ".${ESC}[0m"
        }
    }
}

function Initialize-World([int]$width, [int]$height) {
    [Console]::CursorVisible = $false
    [Console]::Clear()
    $script:ScreenWidth = $width
    $script:ScreenHeight = $height
    $script:TankGrid = New-Object 'object[,]' $width, $height
    $total = $width * $height

    # render state
    $script:LastRenderBuffer = New-Object 'string[]' $total
    $script:StaticLayer      = New-Object 'string[]' $total
    $script:OverlayLayer     = New-Object 'string[]' $total
    $script:BubbleLayer      = New-Object 'string[]' $total
    $script:OverlayTouched.Clear()
    $script:BubbleTouched.Clear()
    $script:ChangedSet = [System.Collections.Generic.HashSet[int]]::new()
    $script:FishStringCache = @{}
    $script:SwayIndex = New-Object 'int[]' $height
    for ($i = 0; $i -lt $height; $i++) { $script:SwayIndex[$i] = -1 }
    $script:SwayFrame = -1
    $script:LastLegendKey = $null
    $script:PlantColumnsByRow = New-Object 'object[]' $height
    for ($i = 0; $i -lt $height; $i++) {
        $script:PlantColumnsByRow[$i] = [System.Collections.Generic.List[int]]::new()
    }

    $script:FishList.Clear()
    $script:FoodList.Clear()
    $script:BubbleList.Clear()

    for ($x = 0; $x -lt $width; $x++) {
        for ($y = 0; $y -lt $height; $y++) {
            $script:TankGrid[$x, $y] = Initialize-Cell
            if ($x -eq 0 -or $x -eq ($width-1) -or $y -eq 0) {
                Set-GridCell $x $y "glass"
                $script:StaticLayer[($y * $width) + $x] = $script:GlassString
            }
            elseif ($y -eq 1) {
                Set-GridCell $x $y "sand"
                $script:StaticLayer[($y * $width) + $x] = $script:SandString
            }
            elseif ($y -eq ($height - 1)) {
                Set-GridCell $x $y "wave"
            }
            else {
                Set-GridCell $x $y "water"
            }
        }
    }

    $script:WaveOffset = -1
    Update-WaterCache

    # Jellyfish
    $script:JellyfishList = [System.Collections.Generic.List[object]]::new()
    $jellyfishCount = $script:RandomGenerator.Next(1, 4)
    for ($j = 0; $j -lt $jellyfishCount; $j++) {
        $script:JellyfishList.Add([pscustomobject]@{
            XCoordinate = $script:RandomGenerator.Next(3, [Math]::Max(4, $width - 7))
            YCoordinate = $script:RandomGenerator.Next(3, [Math]::Max(4, $height - 6))
            PulseState  = ($script:RandomGenerator.Next(2) -eq 0)
            ColorIndex  = $script:RandomGenerator.Next($script:JellyfishColors.Count)
        })
    }

    # Seahorses
    $script:SeahorseList = [System.Collections.Generic.List[object]]::new()
    $seahorseCount = [Math]::Max(1, [Math]::Floor($width / 35))
    for ($i = 0; $i -lt $seahorseCount; $i++) {
        $seahorseDirection = if ($script:RandomGenerator.Next(2) -eq 0) { 1 } else { -1 }
        $script:SeahorseList.Add([pscustomobject]@{
            XCoordinate = $script:RandomGenerator.Next(6, $width - 8)
            YCoordinate = $script:RandomGenerator.Next(3, $height - 5)
            Dir         = $seahorseDirection
            ColorIndex  = $script:RandomGenerator.Next($script:SeahorseColors.Count)
        })
    }

    # Seaweed
    $plantClumps = [Math]::Max(2, [Math]::Floor($width / 18))
    for ($c = 0; $c -lt $plantClumps; $c++) {
        $clumpX = $script:RandomGenerator.Next(6, $width - 6)
        $stalkCount = $script:RandomGenerator.Next(3, 7)
        for ($s = 0; $s -lt $stalkCount; $s++) {
            $plantX = $clumpX + $script:RandomGenerator.Next(-3, 4)
            if ($plantX -lt 2 -or $plantX -ge ($width-2)) { continue }
            $plantHeight = $script:RandomGenerator.Next(4, [Math]::Max(5, $height - 5))
            $plantColorIndex = $script:RandomGenerator.Next($script:PlantColors.Count)
            for ($plantY = 2; $plantY -lt (2 + $plantHeight) -and $plantY -lt ($height-1); $plantY++) {
                Set-GridCell $plantX $plantY "plant"
                $script:TankGrid[$plantX, $plantY].PlantDir = $plantColorIndex
                $script:PlantColumnsByRow[$plantY].Add($plantX)
            }
        }
    }

    # Starting fish
    $startingFishCount = $script:RandomGenerator.Next(5, 9)
    for ($f = 0; $f -lt $startingFishCount; $f++) {
        $fishType = New-FishType
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $fishX = $script:RandomGenerator.Next(6, $width - 6)
            $fishY = $script:RandomGenerator.Next(4, $height - 4)
            $fishDirection = if ($script:RandomGenerator.Next(2) -eq 0) { 1 } else { -1 }
            if (Spawn-Fish $fishX $fishY $fishType $fishDirection) {
                $script:FishList.Add([pscustomobject]@{
                    XCoordinate = $fishX
                    YCoordinate = $fishY
                    FishType    = $fishType
                    Dir         = $fishDirection
                })
                break
            }
        }
    }

    # ---------- Castle (random X along the bottom) ----------
    $castleColor = "${ESC}[1;38;5;250m"
    $castleSprite = @(
        "          /\          ",
        "         /..\         ",
        "   /\    |[]|    /\   ",
        "  |--|   |--|   |--|  ",
        "  |[]|   |[]|   |[]|  ",
        "  |--|___|--|___|--|  ",
        "  |-[]-[]-[]-[]-[]-|  ",
        "  |[]||[]/  \[]||[]|  ",
        "  |[]||[]|  |[]||[]|  "
    )

    $castleWidth = $castleSprite[0].Length
    $maxCastleX  = [Math]::Max(3, $width - $castleWidth - 3)
    $castleX     = $script:RandomGenerator.Next(3, $maxCastleX)
    $castleY     = 2   # sits on the sand

    $lineCount = $castleSprite.Count
    for ($i = 0; $i -lt $lineCount; $i++) {
        $line     = $castleSprite[$i]
        $targetY  = $castleY + ($lineCount - 1 - $i)

        if ($targetY -ge ($height - 1)) { continue }

        for ($col = 0; $col -lt $line.Length; $col++) {
            $char = $line[$col]
            if ($char -ne ' ') {
                Set-StaticCell ($castleX + $col) $targetY ([string]$char) $castleColor
            }
        }
    }

    # Anemones
    $script:AnemoneList = [System.Collections.Generic.List[object]]::new()
    $usableStart = 3
    $usableEnd   = $width - 4
    $usableWidth = $usableEnd - $usableStart + 1
    $targetAnemoneCount = [Math]::Max(3, [Math]::Floor($usableWidth * 0.12))
    $occupiedColumns = [System.Collections.Generic.HashSet[int]]::new()
    $safetyCounter = 0

    while ($script:AnemoneList.Count -lt $targetAnemoneCount -and $safetyCounter -lt 1000) {
        $safetyCounter++
        $anemoneX = $script:RandomGenerator.Next($usableStart, $usableEnd + 1)
        $hasConflict = $false
        for ($checkX = $anemoneX - 2; $checkX -le $anemoneX + 2; $checkX++) {
            if ($occupiedColumns.Contains($checkX)) {
                $hasConflict = $true
                break
            }
        }
        if (-not $hasConflict) {
            for ($checkX = $anemoneX - 2; $checkX -le $anemoneX + 2; $checkX++) {
                [void]$occupiedColumns.Add($checkX)
            }
            $anemoneColor = $script:AnemoneColors[$script:RandomGenerator.Next($script:AnemoneColors.Count)]
            $isTall = ($script:RandomGenerator.Next(100) -lt 30)
            $isWide = ($script:RandomGenerator.Next(100) -lt 30)

            $script:AnemoneList.Add([pscustomobject]@{
                CenterX = $anemoneX
                Y       = 2
                Color   = $anemoneColor
                IsTall  = $isTall
                IsWide  = $isWide
            })
        }
    }

    foreach ($anemone in $script:AnemoneList) {
        $anemoneColor = $anemone.Color
        $variant = $script:RandomGenerator.Next(6)

        # base row
        if ($anemone.IsWide) { $baseRow = '\\|//'; $baseStart = $anemone.CenterX - 2 }
        else                 { $baseRow = '\|/';   $baseStart = $anemone.CenterX - 1 }
        for ($i = 0; $i -lt $baseRow.Length; $i++) {
            Set-StaticCell ($baseStart + $i) $anemone.Y ([string]$baseRow[$i]) $anemoneColor
        }

        # second row if tall
        if ($anemone.IsTall) {
            $pattern = $script:TallPatterns[$variant]
            for ($i = 0; $i -lt 3; $i++) {
                if ($pattern[$i] -ne ' ') {
                    Set-StaticCell ($anemone.CenterX - 1 + $i) ($anemone.Y + 1) ([string]$pattern[$i]) $anemoneColor
                }
            }
        }
    }

    $script:TankSnail.XCoordinate = 2
    $script:TankSnail.YCoordinate = 2
    $script:TankSnail.SnailDirection = 1
}

function Get-Input {
    while ([Console]::KeyAvailable) {
        $keyInfo = [Console]::ReadKey($true)
        switch ($keyInfo.Key) {
            'PageUp'     { $script:TickDelay = [Math]::Max(0, $script:TickDelay - 2) }
            'PageDown'   { $script:TickDelay = [Math]::Min(5000, $script:TickDelay + 2) }
            'N' { Initialize-World ([Console]::WindowWidth) ([Console]::WindowHeight - 1) }
            'P' { $script:IsPaused = -not $script:IsPaused }
            'F' {
                $foodX = $script:RandomGenerator.Next(1, $script:ScreenWidth - 1)
                $foodY = $script:ScreenHeight - 2
                Set-GridCell $foodX $foodY "food"
                $script:FoodList.Add([pscustomobject]@{ XCoordinate = $foodX; YCoordinate = $foodY })
            }
            'S' {
                $spawnX = [Math]::Floor($script:ScreenWidth / 2)
                $spawnY = [Math]::Floor($script:ScreenHeight / 2)
                $spawnDirection = if ($script:RandomGenerator.Next(2) -eq 0) { 1 } else { -1 }
                $spawnType = New-FishType
                if (Spawn-Fish $spawnX $spawnY $spawnType $spawnDirection) {
                    $script:FishList.Add([pscustomobject]@{
                        XCoordinate = $spawnX
                        YCoordinate = $spawnY
                        FishType    = $spawnType
                        Dir         = $spawnDirection
                    })
                }
            }
            'K' {
                if ($script:FishList.Count -gt 0) {
                    $fishIndex = $script:RandomGenerator.Next($script:FishList.Count)
                    $targetFish = $script:FishList[$fishIndex]
                    Clear-FishFromGrid $targetFish.XCoordinate $targetFish.YCoordinate $targetFish.FishType $targetFish.Dir
                    $script:FishList.RemoveAt($fishIndex)
                }
            }
            'W' {   # Cycle water gradients
                $script:CurrentWaterGradient = ($script:CurrentWaterGradient + 1) % 4
                Update-WaterCache
                Set-AllCellsChanged
            }
            'Q'      { $script:ShouldQuit = $true }
            'Escape' { $script:ShouldQuit = $true }
            default {}
        }
    }
}

function Update-FishHead($fishObject) {
    $x = $fishObject.XCoordinate
    $y = $fishObject.YCoordinate
    $fishType = $fishObject.FishType
    $currentCell = $script:TankGrid[$x, $y]
    $fishDirection = if ($fishObject.Dir -ne 0) { $fishObject.Dir } else { 1 }
    $fishLength = Get-FishLength (Get-FishSize $fishType)

    $foodFound = $false
    $targetDeltaX = 0; $targetDeltaY = 0
    # no point scanning if there's no food
    if ($script:FoodList.Count -gt 0) {
        foreach ($deltaX in -4..4) {
            foreach ($deltaY in -2..2) {
                $checkX = $x + $deltaX; $checkY = $y + $deltaY
                if ($checkX -ge 1 -and $checkX -lt ($script:ScreenWidth-1) -and $checkY -ge 1 -and $checkY -lt ($script:ScreenHeight-1)) {
                    if ($script:TankGrid[$checkX, $checkY].Type -eq "food") {
                        if ([Math]::Abs($deltaX) -le 1 -and [Math]::Abs($deltaY) -le 1) {
                            Set-GridCell $checkX $checkY "water"
                            $foodIndex = $script:FoodList.FindIndex({ param($item) $item.XCoordinate -eq $checkX -and $item.YCoordinate -eq $checkY })
                            if ($foodIndex -ge 0) { $script:FoodList.RemoveAt($foodIndex) }
                        } else {
                            $foodFound = $true
                            $targetDeltaX = [Math]::Sign($deltaX)
                            $targetDeltaY = [Math]::Sign($deltaY)
                        }
                    }
                }
            }
        }
    }

    $newDirection = $fishDirection
    $movementDeltaY = 0
    if ($foodFound) {
        if ($targetDeltaX -ne 0) { $newDirection = $targetDeltaX }
        $movementDeltaY = $targetDeltaY
    } else {
        if ($script:RandomGenerator.Next(25) -eq 0) { $newDirection = -$fishDirection }
        if ($script:RandomGenerator.Next(8) -eq 0) { $movementDeltaY = if ($script:RandomGenerator.Next(2) -eq 0) { -1 } else { 1 } }
    }

    $newX = $x + $newDirection
    $newY = $y + $movementDeltaY

    if ($newDirection -gt 0 -and ($x + 1) -ge ($script:ScreenWidth - 1)) {
        $newDirection = -1
        $newX = [Math]::Min($x - 1, $script:ScreenWidth - 1 - $fishLength)
    }
    elseif ($newDirection -lt 0 -and ($x - 1) -le 0) {
        $newDirection = 1
        $newX = [Math]::Max($x + 1, $fishLength)
    }

    if ($newY -le 1) { $newY = 2 }
    if ($newY -ge $script:ScreenHeight - 1) { $newY = $script:ScreenHeight - 2 }

    if ($script:RandomGenerator.Next(18) -eq 0) {
        $script:BubbleList.Add([pscustomobject]@{
            XCoordinate = $newX
            YCoordinate = $newY + 1
            Char = if ($script:RandomGenerator.Next(2) -eq 0) { "o" } else { "$DEG" }
        })
    }

    Clear-FishFromGrid $x $y $fishType $fishDirection

    if (Test-CanSpawnFish $newX $newY $fishType $newDirection) {
        Spawn-Fish $newX $newY $fishType $newDirection | Out-Null
        $fishObject.XCoordinate = $newX
        $fishObject.YCoordinate = $newY
        $fishObject.Dir = $newDirection
    }
    elseif (Test-CanSpawnFish $newX $newY $fishType $fishDirection) {
        Spawn-Fish $newX $newY $fishType $fishDirection | Out-Null
        $fishObject.XCoordinate = $newX
        $fishObject.YCoordinate = $newY
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish ($x+$fishDirection) $y $fishType $fishDirection) {
        Spawn-Fish ($x+$fishDirection) $y $fishType $fishDirection | Out-Null
        $fishObject.XCoordinate = $x + $fishDirection
        $fishObject.YCoordinate = $y
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish $x $y $fishType $fishDirection) {
        Spawn-Fish $x $y $fishType $fishDirection | Out-Null
        $fishObject.XCoordinate = $x
        $fishObject.YCoordinate = $y
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish $x $y $fishType (-$fishDirection)) {
        Spawn-Fish $x $y $fishType (-$fishDirection) | Out-Null
        $fishObject.XCoordinate = $x
        $fishObject.YCoordinate = $y
        $fishObject.Dir = -$fishDirection
    }
    else {
        Set-GridCell $x $y "fish"
        $currentCell.FishType = $fishType
        $currentCell.Segment = 0
        $currentCell.Dir = $fishDirection
        $currentCell.Updated = $true
        $fishObject.XCoordinate = $x
        $fishObject.YCoordinate = $y
        $fishObject.Dir = $fishDirection
    }
}

function Update-Jellyfish {
    foreach ($jellyfish in $script:JellyfishList) {
        if ($script:CurrentFrame % 18 -eq 0) {
            $deltaY = $script:RandomGenerator.Next(3) - 1
            $newY = $jellyfish.YCoordinate + $deltaY
            if ($newY -ge 3 -and $newY -le ($script:ScreenHeight - 3)) { $jellyfish.YCoordinate = $newY }
        }
        if ($script:CurrentFrame % 30 -eq 0) {
            $deltaX = $script:RandomGenerator.Next(3) - 1
            $newX = $jellyfish.XCoordinate + $deltaX
            if ($newX -ge 2 -and $newX -le ($script:ScreenWidth - 6)) { $jellyfish.XCoordinate = $newX }
        }
        if ($script:CurrentFrame % 15 -eq 0) { $jellyfish.PulseState = -not $jellyfish.PulseState }
    }
}

function Update-Seahorses {
    foreach ($seahorse in $script:SeahorseList) {
        if ($script:CurrentFrame % 22 -eq 0) {
            $deltaY = $script:RandomGenerator.Next(3) - 1
            $newY = $seahorse.YCoordinate + $deltaY
            if ($newY -ge 2 -and $newY -le ($script:ScreenHeight - 4)) { $seahorse.YCoordinate = $newY }
        }
        if ($script:CurrentFrame % 40 -eq 0) {
            $deltaX = $script:RandomGenerator.Next(3) - 1
            $newX = $seahorse.XCoordinate + $deltaX
            if ($newX -ge 2 -and $newX -le ($script:ScreenWidth - 7)) {
                if ($newX -gt $seahorse.XCoordinate) { $seahorse.Dir = 1 }
                elseif ($newX -lt $seahorse.XCoordinate) { $seahorse.Dir = -1 }
                $seahorse.XCoordinate = $newX
            }
        }
        if ($script:RandomGenerator.Next(75) -eq 0) {
            $seahorse.Dir = -$seahorse.Dir
        }
    }
}

function Update-World {
    $script:CurrentFrame++

    for ($i = $script:FoodList.Count - 1; $i -ge 0; $i--) {
        $foodItem = $script:FoodList[$i]
        $x = $foodItem.XCoordinate
        $y = $foodItem.YCoordinate
        if ($script:TankGrid[$x, $y].Type -ne "food") {
            $script:FoodList.RemoveAt($i)
            continue
        }
        if ($y -gt 1) {
            $belowType = $script:TankGrid[$x, ($y-1)].Type
            if ($belowType -eq "water" -or $belowType -eq "air") {
                Set-GridCell $x $y "water"
                $newFoodY = $y - 1
                Set-GridCell $x $newFoodY "food"
                $foodItem.YCoordinate = $newFoodY
            }
        }
    }

    if ($script:CurrentFrame % 3 -eq 0 -and $script:FishList.Count -gt 0) {
        for ($i = $script:FishList.Count - 1; $i -ge 0; $i--) {
            $fishObject = $script:FishList[$i]
            $currentCell = $script:TankGrid[$fishObject.XCoordinate, $fishObject.YCoordinate]
            if ($currentCell.Type -eq "fish" -and $currentCell.Segment -eq 0 -and $currentCell.FishType -eq $fishObject.FishType) {
                Update-FishHead $fishObject
            } else {
                $script:FishList.RemoveAt($i)
            }
        }
    }

    if ($script:RandomGenerator.Next(16) -eq 0) {
        $script:BubbleList.Add([pscustomobject]@{
            XCoordinate = $script:RandomGenerator.Next(2, $script:ScreenWidth-2)
            YCoordinate = 2
            Char = if ($script:RandomGenerator.Next(2) -eq 0) { "o" } else { "$DEG" }
        })
    }

    if ($script:CurrentFrame % 4 -eq 0) {
        for ($i = $script:BubbleList.Count - 1; $i -ge 0; $i--) {
            $bubble = $script:BubbleList[$i]
            $bubble.YCoordinate++
            if ($script:RandomGenerator.Next(4) -eq 0) {
                $newBubbleX = $bubble.XCoordinate + ($script:RandomGenerator.Next(3) - 1)
                if ($newBubbleX -ge 1 -and $newBubbleX -lt ($script:ScreenWidth-1)) { $bubble.XCoordinate = $newBubbleX }
            }
            if ($bubble.YCoordinate -ge ($script:ScreenHeight-1)) { $script:BubbleList.RemoveAt($i) }
        }
    }

    if ($script:CurrentFrame % 24 -eq 0) {
        $script:TankSnail.YCoordinate = 2
        $script:TankSnail.XCoordinate += $script:TankSnail.SnailDirection
        if ($script:TankSnail.XCoordinate -ge ($script:ScreenWidth - 2)) {
            $script:TankSnail.XCoordinate = $script:ScreenWidth - 2
            $script:TankSnail.SnailDirection = -1
        }
        elseif ($script:TankSnail.XCoordinate -le 1) {
            $script:TankSnail.XCoordinate = 1
            $script:TankSnail.SnailDirection = 1
        }
    }

    Update-Jellyfish
    Update-Seahorses
}

function Get-WaterColor([int]$y) {
    $ratio = ($y - 2) / [Math]::Max(1, $script:ScreenHeight - 3)

    $waterColors = switch ($script:CurrentWaterGradient) {
        0 { $script:WaterColors1 }
        1 { $script:WaterColors2 }
        2 { $script:WaterColors3 }
        3 { $script:WaterColors4 }
        default { $script:WaterColors1 }
    }

    if ($ratio -lt 0.45) { return $waterColors[0] }
    if ($ratio -lt 0.75) { return $waterColors[1] }
    if ($ratio -lt 0.90) { return $waterColors[2] }
    return $waterColors[3]
}

# only redraw seaweed rows whose sway changed
function Update-SwayCache {
    if ($script:SwayFrame -eq $script:CurrentFrame) { return }
    $script:SwayFrame = $script:CurrentFrame
    $width = $script:ScreenWidth
    $phase = $script:CurrentFrame * 0.05
    for ($y = 2; $y -lt ($script:ScreenHeight - 1); $y++) {
        $sway = [Math]::Round([Math]::Sin($phase + (($y - 2) * 0.3)) * 1.2)
        $swayIdx = if ($sway -gt 0) { 0 } elseif ($sway -lt 0) { 1 } else { 2 }
        if ($script:SwayIndex[$y] -ne $swayIdx) {
            $script:SwayIndex[$y] = $swayIdx
            foreach ($plantX in $script:PlantColumnsByRow[$y]) {
                [void]$script:ChangedSet.Add(($y * $width) + $plantX)
            }
        }
    }
}

# redo the moving stuff every frame, clear last frame's cells and mark them changed
function Update-Overlays {
    $width = $script:ScreenWidth
    $height = $script:ScreenHeight
    $overlay = $script:OverlayLayer
    $bubbleLayer = $script:BubbleLayer
    $changed = $script:ChangedSet

    foreach ($i in $script:OverlayTouched) { $overlay[$i] = ''; [void]$changed.Add($i) }
    $script:OverlayTouched.Clear()
    foreach ($i in $script:BubbleTouched) { $bubbleLayer[$i] = ''; [void]$changed.Add($i) }
    $script:BubbleTouched.Clear()

    # Bubbles
    foreach ($bubble in $script:BubbleList) {
        $bx = $bubble.XCoordinate; $by = $bubble.YCoordinate
        if ($bx -ge 0 -and $bx -lt $width -and $by -ge 0 -and $by -lt $height) {
            $idx = ($by * $width) + $bx
            $bubbleLayer[$idx] = if ($bubble.Char -eq "o") { $script:BubbleStringO } else { $script:BubbleStringDeg }
            $script:BubbleTouched.Add($idx)
            [void]$changed.Add($idx)
        }
    }

    # Seahorses
    foreach ($seahorse in $script:SeahorseList) {
        $seahorseColor = $script:SeahorseColors[$seahorse.ColorIndex % $script:SeahorseColors.Count]
        $seahorseSprite = if ($seahorse.Dir -eq 1) { $script:SeahorseSpriteRight } else { $script:SeahorseSpriteLeft }
        for ($k = 0; $k -lt $seahorseSprite.Length; $k++) {
            Set-OverlayCell ($seahorse.XCoordinate + $k) $seahorse.YCoordinate "$seahorseColor$($seahorseSprite[$k])${ESC}[0m"
        }
    }

    # Jellyfish
    foreach ($jellyfish in $script:JellyfishList) {
        $jellyColor = $script:JellyfishColors[$jellyfish.ColorIndex % $script:JellyfishColors.Count]
        $capSprite = "(())"
        $tentacleSprite = if ($jellyfish.PulseState) { "\||/" } else { "/||\" }
        for ($k = 0; $k -lt 4; $k++) {
            $jx = $jellyfish.XCoordinate + $k
            Set-OverlayCell $jx ($jellyfish.YCoordinate + 1) "$jellyColor$($capSprite[$k])${ESC}[0m"
            Set-OverlayCell $jx $jellyfish.YCoordinate "$jellyColor$($tentacleSprite[$k])${ESC}[0m"
        }
    }

    # Snail
    Set-OverlayCell $script:TankSnail.XCoordinate $script:TankSnail.YCoordinate $script:SnailString
}

# waves move one step every 6 frames
function Update-Waves {
    $offset = [int][Math]::Floor($script:CurrentFrame / 6)
    if ($offset -eq $script:WaveOffset) { return }
    $script:WaveOffset = $offset
    $script:WaveShift = $offset % $script:WavePattern.Count
    $topRowStart = ($script:ScreenHeight - 1) * $script:ScreenWidth
    for ($x = 1; $x -lt ($script:ScreenWidth - 1); $x++) {
        [void]$script:ChangedSet.Add($topRowStart + $x)
    }
}

# rebuild the tank when the window changes size. wait for the size to settle
# first so dragging the edge doesn't rebuild it a hundred times
function Update-Resize {
    if ($script:ResizeTimer.ElapsedMilliseconds -lt 250) { return }
    $script:ResizeTimer.Restart()
    $windowWidth = [Console]::WindowWidth
    $windowHeight = [Console]::WindowHeight - 1
    if ($windowWidth -ne $script:ScreenWidth -or $windowHeight -ne $script:ScreenHeight) {
        $newSize = "$windowWidth,$windowHeight"
        if ($newSize -eq $script:PendingSize) {
            $script:PendingSize = $null
            if ($windowWidth -ge 30 -and $windowHeight -ge 14) {
                Initialize-World $windowWidth $windowHeight
            }
        } else {
            $script:PendingSize = $newSize
        }
    } else {
        $script:PendingSize = $null
    }
}

function Draw-World {
    $width  = $script:ScreenWidth
    $height = $script:ScreenHeight

    Update-SwayCache
    Update-Waves
    Update-Overlays

    $sb = $script:RenderBuilder
    [void]$sb.Clear()

    # legend + clock
    $timeString = [DateTime]::Now.ToString("hh:mm:ss tt")
    $legendKey = "$timeString|$($script:TickDelay)|$($script:IsPaused)"
    if ($legendKey -ne $script:LastLegendKey) {
        $script:LastLegendKey = $legendKey
        $pausedTag = if ($script:IsPaused) { "[PAUSED] " } else { "" }
        $legend = " ${pausedTag}N: New | F: Food | S: Spawn | K: Kill | P: Pause | W: Water | PgUp/PgDn: Speed ($($script:TickDelay)ms) | Q/Esc: Quit "
        if ($legend.Length -ge $width) {
            $legend = $legend.Substring(0, $width)
        } else {
            $remainingSpace = $width - $legend.Length - $timeString.Length
            if ($remainingSpace -lt 0) { $remainingSpace = 0 }
            $legend = $legend + (" " * $remainingSpace) + $timeString
        }
        [void]$sb.Append("${ESC}[").Append($height).Append(';1H').Append("${ESC}[38;5;244m").Append($legend).Append("${ESC}[0m")
    }

    # only the changed cells
    $changed = $script:ChangedSet
    if ($changed.Count -gt 0) {
        $indices = New-Object 'int[]' $changed.Count
        $changed.CopyTo($indices)
        $changed.Clear()
        [Array]::Sort($indices)

        $grid        = $script:TankGrid
        $buffer      = $script:LastRenderBuffer
        $overlay     = $script:OverlayLayer
        $static      = $script:StaticLayer
        $bubbleLayer = $script:BubbleLayer
        $waterStrs   = $script:WaterStrings
        $plantStrs   = $script:PlantStrings
        $swayIndex   = $script:SwayIndex
        $fishCache   = $script:FishStringCache
        $plantCount  = $script:PlantColors.Count
        $waveStrs    = $script:WaveStrings
        $wavePattern = $script:WavePattern
        $waveLen     = $wavePattern.Count
        $waveShift   = $script:WaveShift
        $prevWritten = -2

        foreach ($idx in $indices) {
            if ($idx -lt $width) { continue }     # row 0 is the legend
            $x = $idx % $width
            $y = [int](($idx - $x) / $width)

            $s = $overlay[$idx]
            if (-not $s) { $s = $static[$idx] }
            if (-not $s) {
                $cell = $grid[$x, $y]
                $type = $cell.Type
                if ($type -eq "water") {
                    $s = $bubbleLayer[$idx]
                    if (-not $s) { $s = $waterStrs[$y] }
                }
                elseif ($type -eq "fish") {
                    $fishType = $cell.FishType
                    $segment = $cell.Segment
                    $fishDir = $cell.Dir
                    $cacheKey = ($fishType * 16) + $(if ($fishDir -eq 1) { 8 } else { 0 }) + $segment
                    $s = $fishCache[$cacheKey]
                    if (-not $s) {
                        $fishSize = Get-FishSize $fishType
                        $fishColor = Get-FishColor $fishType
                        $fishFlavor = Get-FishFlavor $fishType
                        $fishSprite = if ($fishDir -eq 1) { $script:FishSpritesRight[$fishSize] } else { $script:FishSpritesLeft[$fishSize] }
                        $fishChar = if ($segment -lt $fishSprite.Length) { $fishSprite[$segment] } else { ">" }
                        $fishPalette = $script:FishPalettes[[int]$fishFlavor]
                        $segmentColor = $fishPalette[($fishColor + $segment) % $fishPalette.Count]
                        $s = "${segmentColor}${fishChar}${ESC}[0m"
                        $fishCache[$cacheKey] = $s
                    }
                }
                elseif ($type -eq "plant") {
                    $s = $plantStrs[(($cell.PlantDir % $plantCount) * 3) + $swayIndex[$y]]
                }
                elseif ($type -eq "food") {
                    $s = $script:FoodString
                }
                elseif ($type -eq "wave") {
                    $s = $waveStrs[$wavePattern[($x + $waveLen - $waveShift) % $waveLen]]
                }
                else {
                    $s = " "
                }
            }

            if ($buffer[$idx] -ne $s) {
                $buffer[$idx] = $s
                # only move the cursor if we skipped some cells
                if ($idx -ne ($prevWritten + 1) -or $x -eq 0) {
                    [void]$sb.Append("${ESC}[").Append($height - $y).Append(';').Append($x + 1).Append('H')
                }
                [void]$sb.Append($s)
                $prevWritten = $idx
            }
        }
    }

    # one write per frame
    if ($sb.Length -gt 0) {
        [void]$sb.Insert(0, "${ESC}[?2026h")
        [void]$sb.Append("${ESC}[?2026l")
        [Console]::Out.Write($sb.ToString())
    }
}

# ---------- Start ----------
$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

Initialize-World ([Console]::WindowWidth) ([Console]::WindowHeight - 1)

$frameTimer = [System.Diagnostics.Stopwatch]::new()
while (-not $script:ShouldQuit) {
    $frameTimer.Restart()
    Get-Input
    if ($script:ShouldQuit) { break }
    Update-Resize
    if (-not $script:IsPaused) { Update-World }
    Draw-World

    # TickDelay is the frame time, time spent working counts toward it
    $remaining = $script:TickDelay - $frameTimer.ElapsedMilliseconds
    if ($script:IsPaused) { $remaining = [Math]::Max($remaining, 33) }   # don't spin while paused
    if ($remaining -gt 0) {
        [System.Threading.Thread]::Sleep([int]$remaining)
    }
}

[Console]::OutputEncoding = $originalEncoding
[Console]::CursorVisible = $true
[Console]::Clear()
# ============================================================
#   Powershell Fish Tank
#   N: New Tank | F: Drop Food | S: Spawn Fish | K: Kill Fish | PgUp/PgDn: Speed | Q/Esc: Quit
# ============================================================
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
$script:CursorX = 0
$script:CursorY = 0
$script:TickDelay = 16
$script:ShouldQuit = $false

$script:AnemoneMap = @{}
$script:BubbleMap = @{}
$script:JellyfishMap = @{}
$script:SeahorseMap = @{}
$script:LastRenderBuffer = $null

#Colors
$script:FishColors = @(
    "`e[38;5;202m", "`e[38;5;208m", "`e[38;5;214m",
    "`e[38;5;215m", "`e[38;5;209m"
)
$script:TetraColors = @(
    "`e[38;5;39m",   # bright blue
    "`e[38;5;45m",   # cyan
    "`e[38;5;81m",   # light blue
    "`e[38;5;33m",   # deep sky
    "`e[38;5;75m"    # soft blue
)

$script:JellyfishColors = @(
    "`e[38;5;39m"    # dark purple
)
$script:SeahorseColors = @(
    "`e[38;5;223m", "`e[38;5;223m", "`e[38;5;225m", "`e[38;5;223m"
)
$script:PlantColors = @(
    "`e[38;5;34m", "`e[38;5;28m", "`e[38;5;30m", "`e[38;5;118m",
    "`e[38;5;46m", "`e[38;5;82m", "`e[38;5;40m", "`e[38;5;36m"
)
$script:AnemoneColors = @(
    "`e[38;5;53m",   # dark purple
    "`e[38;5;54m",   # dark purple-blue
    "`e[38;5;91m",   # purple
    "`e[38;5;92m",   # medium purple
    "`e[38;5;55m",   # deep purple
    "`e[38;5;97m",   # purple/violet
    "`e[38;5;134m",  # medium orchid
    "`e[38;5;135m"   # purple
)

# Fish "sprites"
$script:FishSpritesRight = @('><>', '>*(*>', '>*((*>', '>*(((*>', '>°(}}-}')
$script:FishSpritesLeft = @('<><', '<*)*<', '<*))*<', '<*)))*<', '<°){{-{')
$script:SeahorseSpriteRight = '@='
$script:SeahorseSpriteLeft = '=@'

function Initialize-Cell([string]$cellType = "air") {
    return @{
        Type      = $cellType
        Density   = 0
        Dir       = 1
        FishType  = 0
        Segment   = 0
        Updated   = $false
        PlantDir  = 0
    }
}

function Set-GridCell([int]$x, [int]$y, [string]$cellType) {
    if ($x -lt 0 -or $x -ge $script:ScreenWidth -or $y -lt 0 -or $y -ge $script:ScreenHeight) { return }
    $currentCell = $script:TankGrid[$x, $y]
    $currentCell.Type = $cellType
    $currentCell.Density = switch ($cellType) {
        "air"     { 0 }
        "water"   { 1 }
        "food"    { 2 }
        "fish"    { 3 }
        "plant"   { 4 }
        "sand"    { 5 }
        "glass"   { 100 }
        default   { 0 }
    }
}

function Get-FishLength([int]$fishSize) {
    return $script:FishSpritesRight[[Math]::Max(0, [Math]::Min(3, $fishSize))].Length
}

function New-FishType {
    $script:FishIdCounter++
    $fishSize  = $script:RandomGenerator.Next($script:FishSpritesRight.Count)
    $fishColor = $script:RandomGenerator.Next($script:FishColors.Count)

    # 25% chance of Tetra (flavor 1), otherwise Orange (flavor 0)
    $fishFlavor = if ($script:RandomGenerator.Next(4) -eq 0) { 1 } else { 0 }

    # pack: id*1000 + flavor*100 + color*10 + size
    return ($script:FishIdCounter % 1000) * 1000 + $fishFlavor * 100 + $fishColor * 10 + $fishSize
}

function Get-FishSize([int]$fishType)   { return $fishType % 10 }
function Get-FishColor([int]$fishType)  { return [Math]::Floor(($fishType % 100) / 10) }
function Get-FishFlavor([int]$fishType) { return [Math]::Floor(($fishType % 1000) / 100) }

function Test-CanSpawnFish([int]$x, [int]$y, [int]$fishType, [int]$fishDirection) {
    $fishLength = Get-FishLength (Get-FishSize $fishType)
    for ($i = 0; $i -lt $fishLength; $i++) {
        $checkX = $x - ($i * $fishDirection)
        if ($checkX -lt 1 -or $checkX -ge ($script:ScreenWidth - 1)) { return $false }
        $targetType = $script:TankGrid[$checkX, $y].Type
        if ($targetType -notin @("water", "plant")) { return $false }
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

            # Restore plant if one was underneath
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
        $currentCell.Dir      = $fishDirection
        $currentCell.FishType = $fishType
        $currentCell.Segment  = $i
        $currentCell.Updated  = $true
        if ($savedPlantDirection -ne -1) {
            $currentCell.Density = 1000 + $savedPlantDirection
        }
    }
    return $true
}

#World Start
function Initialize-World([int]$width, [int]$height) {
    [Console]::CursorVisible = $false
    [Console]::Clear()
    $script:ScreenWidth = $width
    $script:ScreenHeight = $height
    $script:TankGrid = New-Object 'object[,]' $width, $height
    $script:LastRenderBuffer = New-Object 'string[,]' $width, $height
    $script:FishList.Clear()
    $script:FoodList.Clear()
    for ($x = 0; $x -lt $width; $x++) {
        for ($y = 0; $y -lt $height; $y++) {
            $script:TankGrid[$x, $y] = Initialize-Cell
            if ($x -eq 0 -or $x -eq ($width-1) -or $y -eq 0) {
                Set-GridCell $x $y "glass"
            }
            elseif ($y -eq 1) {
                Set-GridCell $x $y "sand"
            }
            else {
                Set-GridCell $x $y "water"
            }
        }
    }
    $script:JellyfishList = [System.Collections.Generic.List[object]]::new()#Jellyfish
    $jellyX = $script:RandomGenerator.Next(3, [Math]::Max(4, $width - 7))
    $jellyY = $script:RandomGenerator.Next(3, [Math]::Max(4, $height - 6))
    $script:JellyfishList.Add([pscustomobject]@{
        XCoordinate = $jellyX
        YCoordinate = $jellyY
        PulseState  = $false
        ColorIndex  = 0
    })
    $script:SeahorseList = [System.Collections.Generic.List[object]]::new()#Seahorse
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
    $plantClumps = [Math]::Max(2, [Math]::Floor($width / 18))#Seaweed
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
            }
        }
    }
    $startingFishCount = $script:RandomGenerator.Next(5, 9)
    for ($f = 0; $f -lt $startingFishCount; $f++) {
        $fishX = $script:RandomGenerator.Next(6, $width - 6)
        $fishY = $script:RandomGenerator.Next(4, $height - 4)
        $fishDirection = if ($script:RandomGenerator.Next(2) -eq 0) { 1 } else { -1 }
        $fishType = New-FishType
        if (Spawn-Fish $fishX $fishY $fishType $fishDirection) {
            $script:FishList.Add([pscustomobject]@{ XCoordinate = $fishX; YCoordinate = $fishY; FishType = $fishType; Dir = $fishDirection })
        }
    }
    $script:AnemoneList = [System.Collections.Generic.List[object]]::new()
    $usableStart = 3
    $usableEnd = $width - 4
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
            $isTall = ($script:RandomGenerator.Next(100) -lt 15)
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

    # Cache static anemones and corals into integer-keyed lookup map once. Thanks Gemini
    $script:AnemoneMap.Clear()
    foreach ($anemone in $script:AnemoneList) {
        $anemoneColor = $anemone.Color
        
        if ($anemone.IsWide) {
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX - 2)] = @{ Char = '\'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX - 1)] = @{ Char = '\'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + $anemone.CenterX]     = @{ Char = '|'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX + 1)] = @{ Char = '/'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX + 2)] = @{ Char = '/'; Col = $anemoneColor }
        } else {
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX - 1)] = @{ Char = '\'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + $anemone.CenterX]     = @{ Char = '|'; Col = $anemoneColor }
            $script:AnemoneMap[($anemone.Y * $width) + ($anemone.CenterX + 1)] = @{ Char = '/'; Col = $anemoneColor }

            if ($anemone.IsTall) {
                $script:AnemoneMap[(($anemone.Y + 1) * $width) + ($anemone.CenterX - 1)] = @{ Char = '/'; Col = $anemoneColor }
                $script:AnemoneMap[(($anemone.Y + 1) * $width) + $anemone.CenterX]     = @{ Char = '|'; Col = $anemoneColor }
                $script:AnemoneMap[(($anemone.Y + 1) * $width) + ($anemone.CenterX + 1)] = @{ Char = '\'; Col = $anemoneColor }
            }
        }
    }
    $script:CursorX = [int]($width / 2)
    $script:CursorY = [int]($height / 2)
    $script:TankSnail.XCoordinate = 2
    $script:TankSnail.YCoordinate = 2
    $script:TankSnail.SnailDirection = 1
}

#Controls
function Get-Input {
    while ([Console]::KeyAvailable) {
        $keyInfo = [Console]::ReadKey($true)
        switch ($keyInfo.Key) {
            'LeftArrow'  { $script:CursorX = [Math]::Max(1, $script:CursorX - 1) }
            'RightArrow' { $script:CursorX = [Math]::Min($script:ScreenWidth - 2, $script:CursorX + 1) }
            'UpArrow'    { $script:CursorY = [Math]::Min($script:ScreenHeight - 2, $script:CursorY + 1) }
            'DownArrow'  { $script:CursorY = [Math]::Max(1, $script:CursorY - 1) }
            'PageUp'     { $script:TickDelay = [Math]::Max(0, $script:TickDelay - 2) }
            'PageDown'   { $script:TickDelay = [Math]::Min(5000, $script:TickDelay + 2) }
            'N'          { Initialize-World ([Console]::WindowWidth) ([Console]::WindowHeight - 1) }
            'F'          { 
                $foodX = $script:RandomGenerator.Next(1, $script:ScreenWidth - 1)
                $foodY = $script:ScreenHeight - 2
                Set-GridCell $foodX $foodY "food"
                $script:FoodList.Add([pscustomobject]@{ XCoordinate = $foodX; YCoordinate = $foodY })
            }
            'S'          { 
                $spawnX = [Math]::Floor($script:ScreenWidth / 2)
                $spawnY = [Math]::Floor($script:ScreenHeight / 2)
                $spawnDirection = if ($script:RandomGenerator.Next(2) -eq 0) { 1 } else { -1 }
                $spawnType = New-FishType
                if (Spawn-Fish $spawnX $spawnY $spawnType $spawnDirection) {
                    $script:FishList.Add([pscustomobject]@{ XCoordinate = $spawnX; YCoordinate = $spawnY; FishType = $spawnType; Dir = $spawnDirection })
                }
            }
            'K'          {
                if ($script:FishList.Count -gt 0) {
                    $fishIndex = $script:RandomGenerator.Next($script:FishList.Count)
                    $targetFish = $script:FishList[$fishIndex]
                    Clear-FishFromGrid $targetFish.XCoordinate $targetFish.YCoordinate $targetFish.FishType $targetFish.Dir
                    $script:FishList.RemoveAt($fishIndex)
                }
            }
            'Q'          { $script:ShouldQuit = $true }
            'Escape'     { $script:ShouldQuit = $true }
            default      {}
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

    #Find Food
    $foodFound = $false
    $targetDeltaX = 0; $targetDeltaY = 0
    foreach ($deltaX in -4..4) {
        foreach ($deltaY in -2..2) {
            $checkX = $x + $deltaX; $checkY = $y + $deltaY
            if ($checkX -ge 1 -and $checkX -lt ($script:ScreenWidth-1) -and $checkY -ge 1 -and $checkY -lt ($script:ScreenHeight-1)) {
                if ($script:TankGrid[$checkX, $checkY].Type -eq "food") {
                    if ([Math]::Abs($deltaX) -le 1 -and [Math]::Abs($deltaY) -le 1) {
                        Set-GridCell $checkX $checkY "water"   # eat
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

    $newDirection = $fishDirection
    $movementDeltaY = 0
    if ($foodFound) {
        if ($targetDeltaX -ne 0) { $newDirection = $targetDeltaX }
        $movementDeltaY = $targetDeltaY
    } else {
        if ($script:RandomGenerator.Next(25) -eq 0) { $newDirection = -$fishDirection }
        if ($script:RandomGenerator.Next(8)  -eq 0) { $movementDeltaY = if ($script:RandomGenerator.Next(2) -eq 0) { -1 } else { 1 } }
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

    #Bubbles
    if ($script:RandomGenerator.Next(18) -eq 0) {
        $script:BubbleList.Add([pscustomobject]@{
            XCoordinate = $newX
            YCoordinate = $newY + 1
            Char        = if ($script:RandomGenerator.Next(2) -eq 0) { "o" } else { "°" }
        })
    }

    Clear-FishFromGrid $x $y $fishType $fishDirection
    if     (Test-CanSpawnFish $newX $newY $fishType $newDirection) { 
        Spawn-Fish $newX $newY $fishType $newDirection | Out-Null
        $fishObject.XCoordinate = $newX
        $fishObject.YCoordinate = $newY
        $fishObject.Dir = $newDirection
    }
    elseif (Test-CanSpawnFish $newX $newY $fishType $fishDirection)    { 
        Spawn-Fish $newX $newY $fishType $fishDirection    | Out-Null 
        $fishObject.XCoordinate = $newX
        $fishObject.YCoordinate = $newY
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish ($x+$fishDirection) $y $fishType $fishDirection){ 
        Spawn-Fish ($x+$fishDirection) $y $fishType $fishDirection | Out-Null 
        $fishObject.XCoordinate = $x + $fishDirection
        $fishObject.YCoordinate = $y
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish $x $y $fishType $fishDirection)      { 
        Spawn-Fish $x $y $fishType $fishDirection      | Out-Null 
        $fishObject.XCoordinate = $x
        $fishObject.YCoordinate = $y
        $fishObject.Dir = $fishDirection
    }
    elseif (Test-CanSpawnFish $x $y $fishType (-$fishDirection))   { 
        Spawn-Fish $x $y $fishType (-$fishDirection)   | Out-Null 
        $fishObject.XCoordinate = $x
        $fishObject.YCoordinate = $y
        $fishObject.Dir = -$fishDirection
    }
    else {
        Set-GridCell $x $y "fish"
        $currentCell.FishType = $fishType
        $currentCell.Segment  = 0
        $currentCell.Dir      = $fishDirection
        $currentCell.Updated  = $true
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

        if ($y -gt 1 -and $script:TankGrid[$x, ($y-1)].Type -in @("water", "air")) {
            Set-GridCell $x $y "water"
            $newFoodY = $y - 1
            Set-GridCell $x $newFoodY "food"
            $foodItem.YCoordinate = $newFoodY
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
            Char        = if ($script:RandomGenerator.Next(2) -eq 0) { "o" } else { "°" }
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

    #Snail
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
    if ($ratio -lt 0.45) { return "`e[38;5;17m" }
    if ($ratio -lt 0.75) { return "`e[38;5;18m" }
    if ($ratio -lt 0.90) { return "`e[38;5;19m" }
    return "`e[38;5;20m"
}

function Draw-World {
    # Repopulate maps using flat integer coordinates....Gemini optimization vs original full screen string
    $script:BubbleMap.Clear()
    foreach ($bubble in $script:BubbleList) {
        if ($bubble.XCoordinate -ge 0 -and $bubble.XCoordinate -lt $script:ScreenWidth -and $bubble.YCoordinate -ge 0 -and $bubble.YCoordinate -lt $script:ScreenHeight) {
            $script:BubbleMap[($bubble.YCoordinate * $script:ScreenWidth) + $bubble.XCoordinate] = $bubble.Char
        }
    }

    $script:JellyfishMap.Clear()
    foreach ($jellyfish in $script:JellyfishList) {
        $jellyColor = $script:JellyfishColors[$jellyfish.ColorIndex % $script:JellyfishColors.Count]
        $capSprite  = "(())"
        $tentacleSprite = if ($jellyfish.PulseState) { "\||/" } else { "/||\" }
        for ($k = 0; $k -lt 4; $k++) {
            $jellyXCoord = $jellyfish.XCoordinate + $k
            if ($jellyXCoord -ge 0 -and $jellyXCoord -lt $script:ScreenWidth) {
                $jellyY1 = $jellyfish.YCoordinate + 1
                $jellyY0 = $jellyfish.YCoordinate
                if ($jellyY1 -ge 0 -and $jellyY1 -lt $script:ScreenHeight) {
                    $script:JellyfishMap[($jellyY1 * $script:ScreenWidth) + $jellyXCoord] = @{ Char = $capSprite[$k];  Col = $jellyColor }
                }
                if ($jellyY0 -ge 0 -and $jellyY0 -lt $script:ScreenHeight) {
                    $script:JellyfishMap[($jellyY0 * $script:ScreenWidth) + $jellyXCoord] = @{ Char = $tentacleSprite[$k]; Col = $jellyColor }
                }
            }
        }
    }

    $script:SeahorseMap.Clear()
    foreach ($seahorse in $script:SeahorseList) {
        $seahorseColor = $script:SeahorseColors[$seahorse.ColorIndex % $script:SeahorseColors.Count]
        $seahorseSprite = if ($seahorse.Dir -eq 1) { $script:SeahorseSpriteRight } else { $script:SeahorseSpriteLeft }
        for ($k = 0; $k -lt $seahorseSprite.Length; $k++) {
            $seahorseXCoord = $seahorse.XCoordinate + $k
            if ($seahorseXCoord -ge 0 -and $seahorseXCoord -lt $script:ScreenWidth -and $seahorse.YCoordinate -ge 0 -and $seahorse.YCoordinate -lt $script:ScreenHeight) {
                $script:SeahorseMap[($seahorse.YCoordinate * $script:ScreenWidth) + $seahorseXCoord] = @{ Char = $seahorseSprite[$k]; Col = $seahorseColor }
            }
        }
    }

    for ($y = $script:ScreenHeight - 1; $y -ge 0; $y--) {
        $consoleRow = $script:ScreenHeight - 1 - $y

        if ($y -eq 0) {
            $currentTimeString = (Get-Date).ToString("hh:mm:ss tt")
            $legend = " N: New Tank | F: Food | S: Spawn | K: Kill | PgUp/PgDn: Speed ($($script:TickDelay)ms) | Q/Esc: Quit "
            
            if ($legend.Length -ge $script:ScreenWidth) {
                $legend = $legend.Substring(0, $script:ScreenWidth)
            } else {
                $remainingSpace = $script:ScreenWidth - $legend.Length - $currentTimeString.Length
                if ($remainingSpace -lt 0) { $remainingSpace = 0 }
                $legend = $legend + (" " * $remainingSpace) + $currentTimeString
            }

            $legendString = "`e[38;5;244m$legend`e[0m"
            if ($script:LastRenderBuffer[0, $y] -ne $legendString) {
                [Console]::SetCursorPosition(0, $consoleRow)
                [Console]::Write($legendString)
                $script:LastRenderBuffer[0, $y] = $legendString
            }
            continue
        }

        $waterColor = Get-WaterColor $y
        for ($x = 0; $x -lt $script:ScreenWidth; $x++) {
            $cellIndex = ($y * $script:ScreenWidth) + $x
            $cellString = ""
            # Snail
            if ($x -eq $script:TankSnail.XCoordinate -and $y -eq $script:TankSnail.YCoordinate) {
                $cellString = "`e[1;38;5;255m@`e[0m"
            }
            elseif ($script:JellyfishMap.ContainsKey($cellIndex)) {
                $jellyInfo = $script:JellyfishMap[$cellIndex]
                $cellString = "$($jellyInfo.Col)$($jellyInfo.Char)`e[0m"
            }
            elseif ($script:SeahorseMap.ContainsKey($cellIndex)) {
                $seahorseInfo = $script:SeahorseMap[$cellIndex]
                $cellString = "$($seahorseInfo.Col)$($seahorseInfo.Char)`e[0m"
            }
            elseif ($script:AnemoneMap.ContainsKey($cellIndex)) {
                $anemoneInfo = $script:AnemoneMap[$cellIndex]
                $cellString = "$($anemoneInfo.Col)$($anemoneInfo.Char)`e[0m"
            }
            else {
                $currentCell = $script:TankGrid[$x, $y]
                $inner = switch ($currentCell.Type) {
                    "air"   { " " }
                    "sand"  { "`e[38;5;222m=`e[0m" }
                    "glass" { "`e[38;5;244m|`e[0m" }
                    "food"  { "`e[38;5;172m*`e[0m" }
                    "plant" {
                        $swayAmount = [Math]::Round([Math]::Sin(($script:CurrentFrame * 0.05) + (($y-2) * 0.3)) * 1.2)
                        $plantChar = if ($swayAmount -gt 0) { "/" } elseif ($swayAmount -lt 0) { "\" } else { "|" }
                        $plantColor = $script:PlantColors[$currentCell.PlantDir % $script:PlantColors.Count]
                        "${plantColor}${plantChar}`e[0m"
                    }
                    "fish" {
                        $fishSize    = Get-FishSize   $currentCell.FishType
                        $fishColor   = Get-FishColor  $currentCell.FishType
                        $fishFlavor  = Get-FishFlavor $currentCell.FishType

                        $fishSprite = if ($currentCell.Dir -eq 1) { $script:FishSpritesRight[$fishSize] } else { $script:FishSpritesLeft[$fishSize] }
                        $fishChar = if ($currentCell.Segment -lt $fishSprite.Length) { $fishSprite[$currentCell.Segment] } else { ">" }

                        $fishPalette = if ($fishFlavor -eq 1) { $script:TetraColors } else { $script:FishColors }
                        $segmentColorIndex = ($fishColor + $currentCell.Segment) % $fishPalette.Count
                        $segmentColor = $fishPalette[$segmentColorIndex]

                        "${segmentColor}${fishChar}`e[0m"
                    }
                    "water" {
                        if ($script:BubbleMap.ContainsKey($cellIndex)) {
                            "`e[1;38;5;123m$($script:BubbleMap[$cellIndex])`e[0m"
                        } else {
                            "${waterColor}.`e[0m"
                        }
                    }
                    default { " " }
                }
                $cellString = $inner
            }

            # Differential check: only write if cell output changed
            if ($script:LastRenderBuffer[$x, $y] -ne $cellString) {
                [Console]::SetCursorPosition($x, $consoleRow)
                [Console]::Write($cellString)
                $script:LastRenderBuffer[$x, $y] = $cellString
            }
        }
    }
}

#Start
Initialize-World ([Console]::WindowWidth) ([Console]::WindowHeight - 1)
while (-not $script:ShouldQuit) {
    Get-Input
    if ($script:ShouldQuit) { break }

    Update-World
    Draw-World
    if ($script:TickDelay -gt 0) {
        [System.Threading.Thread]::Sleep($script:TickDelay)
    }
}

[Console]::CursorVisible = $true
[Console]::Clear()
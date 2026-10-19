# ============================================================
# ВЫЧИСЛЕНИЕ ХЭШЕЙ
# ============================================================

function Get-PartialFileHash {
    <#
    .SYNOPSIS
        Вычисляет хэш только для нескольких блоков файла.
    .DESCRIPTION
        Читает начало, середину и конец файла. В разы быстрее полного
        хэширования, но с вероятностью коллизии близкой к нулю.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Algorithm = "MD5",
        [int]$BlockSize = 1MB,
        [int]$BlockCount = 3
    )

    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $length = $fs.Length

        # Маленький файл — читаем целиком
        if ($length -le $BlockSize * $BlockCount) {
            $fs.Close()
            return (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
        }

        # Создаём хэш-алгоритм
        $hashAlgo = switch ($Algorithm) {
            "MD5"    { [System.Security.Cryptography.MD5]::Create() }
            "SHA1"   { [System.Security.Cryptography.SHA1]::Create() }
            "SHA256" { [System.Security.Cryptography.SHA256]::Create() }
            default  { [System.Security.Cryptography.MD5]::Create() }
        }

        $buffer = New-Object byte[] $BlockSize

        # 1. Начало файла
        $fs.Position = 0
        $fs.Read($buffer, 0, $BlockSize) | Out-Null
        $hashAlgo.TransformBlock($buffer, 0, $BlockSize, $null, 0) | Out-Null

        # 2. Середина файла
        $fs.Position = [math]::Floor($length / 2) - [math]::Floor($BlockSize / 2)
        $fs.Read($buffer, 0, $BlockSize) | Out-Null
        $hashAlgo.TransformBlock($buffer, 0, $BlockSize, $null, 0) | Out-Null

        # 3. Конец файла
        $fs.Position = $length - $BlockSize
        $fs.Read($buffer, 0, $BlockSize) | Out-Null
        $hashAlgo.TransformBlock($buffer, 0, $BlockSize, $null, 0) | Out-Null

        $hashAlgo.TransformFinalBlock([byte[]]@(), 0, 0) | Out-Null
        $fs.Close()

        $hashBytes = $hashAlgo.Hash
        $hashAlgo.Dispose()

        return ($hashBytes | ForEach-Object { $_.ToString("X2") }) -join ""

    } catch {
        Write-Host "  [PARTIAL-ERROR] $Path : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Add-FileHash {
    <#
    .SYNOPSIS
        Вычисляет хэши для файлов, у которых совпадает размер.
    .DESCRIPTION
        Сначала группирует по размеру, затем хэширует только группы
        с более чем одним файлом. Показывает прогресс.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$FileList,

        [hashtable]$Config
    )

    Write-Host "[3/4] Grouping by size and comparing hashes..." -ForegroundColor Yellow

    # ===== DEBUG =====
    Write-Host "DEBUG: FileList count = $($FileList.Count)" -ForegroundColor Magenta
    Write-Host "DEBUG: Sizes = $(($FileList | ForEach-Object { $_.Size }) -join ', ')" -ForegroundColor Magenta
    Write-Host "DEBUG: Size types = $(($FileList | ForEach-Object { $_.Size.GetType().Name }) -join ', ')" -ForegroundColor Magenta
    Write-Host "DEBUG: IsHardlink values = $(($FileList | ForEach-Object { $_.IsHardlink }) -join ', ')" -ForegroundColor Magenta
    # =================

    # ===== DEBUG =====
    $FileList | ForEach-Object {
        $s = $_.Size
        $type = if ($s -ne $null) { $s.GetType().FullName } else { "NULL" }
        $hash = if ($s -ne $null) { $s.GetHashCode() } else { "N/A" }
        Write-Host "DEBUG: Size='$s' | Type=$type | HashCode=$hash" -ForegroundColor Magenta
    }
    # =================
    Write-Host "DEBUG: FileList type = $($FileList.GetType().FullName)" -ForegroundColor Magenta
    Write-Host "DEBUG: FileList is array = $($FileList -is [array])" -ForegroundColor Magenta
    Write-Host "DEBUG: FileList count = $($FileList.Count)" -ForegroundColor Magenta
    Write-Host "DEBUG: First element type = $($FileList[0].GetType().FullName)" -ForegroundColor Magenta

    # Ручная группировка по размеру (обходим баг PS 5.1)
    $sizeGroupsMap = @{}
    foreach ($file in $FileList) {
        $key = [string]$file.Size
        if (-not $sizeGroupsMap.ContainsKey($key)) {
            $sizeGroupsMap[$key] = @()
        }
        $sizeGroupsMap[$key] += $file
    }

    $sizeGroups = @()
    foreach ($key in $sizeGroupsMap.Keys) {
        if ($sizeGroupsMap[$key].Count -gt 1) {
            $sizeGroups += [PSCustomObject]@{
                Name  = $key
                Group = $sizeGroupsMap[$key]
                Count = $sizeGroupsMap[$key].Count
            }
        }
    }

    if ($sizeGroups.Count -eq 0) {
        Write-Host "  No files with matching sizes found." -ForegroundColor Green
        return $FileList
    }

    Write-Host "  Groups with same size: $($sizeGroups.Count)" -ForegroundColor Gray

    $totalGroups = $sizeGroups.Count
    $processed = 0
    $hashedCount = 0
    $errorCount = 0

    foreach ($sizeGroup in $sizeGroups) {
        $processed++
        $files = $sizeGroup.Group

        # Прогресс по группам
        if ($Config.ShowProgress) {
            $percent = [math]::Round(($processed / $totalGroups) * 100)
            Write-Host "`r  Progress: $processed/$totalGroups ($percent%)" -NoNewline -ForegroundColor DarkGray
        }

        foreach ($file in $files) {
            try {
                # Выбираем метод хэширования
                if ($Config.PartialHash -and $file.Size -gt $Config.FullHashMaxSize) {
                    $hash = Get-PartialFileHash -Path $file.FullPath `
                                                -Algorithm $Config.HashAlgorithm `
                                                -BlockSize $Config.PartialBlockSize `
                                                -BlockCount $Config.PartialBlockCount
                } else {
                    $hash = (Get-FileHash -LiteralPath $file.FullPath `
                                          -Algorithm $Config.HashAlgorithm).Hash
                }

                if ($hash) {
                    $file.Hash = $hash
                    $hashedCount++
                } else {
                    $errorCount++
                }
            } catch {
                Write-Host "  [ERROR] $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
            }
        }
    }

    if ($Config.ShowProgress) {
        Write-Host ""  # Переход на новую строку
    }

    Write-Host "  Hashed files: $hashedCount" -ForegroundColor Gray
    if ($errorCount -gt 0) {
        Write-Host "  Errors: $errorCount" -ForegroundColor DarkYellow
    }

    return $FileList
}
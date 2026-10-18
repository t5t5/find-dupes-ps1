# ============================================================
# СБОР ФАЙЛОВ
# ============================================================

function Get-FileList {
    <#
    .SYNOPSIS
        Рекурсивно собирает список файлов для анализа.
    .DESCRIPTION
        Обходит директории, фильтрует по размеру и маскам.
        Использует -LiteralPath, чтобы не интерпретировать [ ] как wildcard.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$ExcludePatterns = @(),
        [string[]]$ExcludeDirs = @(),
        [uint64]$MinSize = 0,
        [uint64]$MaxSize = [uint64]::MaxValue
    )

    Write-Host "[1/4] Collecting file info..." -ForegroundColor Yellow

    # Проверяем, что путь существует
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  [ERROR] Path not found: $Path" -ForegroundColor Red
        return @()
    }

    # Собираем все файлы рекурсивно (LiteralPath — критично для [ ] в именах!)
    $allFiles = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue

    $result = @()
    $skipped = 0

    foreach ($file in $allFiles) {
        # Пропускаем исключённые директории
        $skip = $false
        foreach ($dir in $ExcludeDirs) {
            if ($file.FullName -like "*\$dir\*") {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        # Пропускаем по маске
        foreach ($pattern in $ExcludePatterns) {
            if ($file.Name -like $pattern) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }

        # Фильтр по размеру
        if ($file.Length -lt $MinSize -or $file.Length -gt $MaxSize) {
            $skipped++
            continue
        }

        # Формируем объект
        $result += [PSCustomObject]@{
            FullPath    = $file.FullName
            Name        = $file.Name
            Extension   = $file.Extension
            Size        = $file.Length
            LastWrite   = $file.LastWriteTime
            Hash        = $null
            IsHardlink  = $false
            HardlinkTargets = @()
            HardlinkGroupId = $null
        }
    }

    Write-Host "  Files found: $($result.Count)" -ForegroundColor Gray
    if ($skipped -gt 0) {
        Write-Host "  Skipped by size: $skipped" -ForegroundColor DarkGray
    }

    return $result
}
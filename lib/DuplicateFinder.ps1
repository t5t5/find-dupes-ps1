# ============================================================
# ПОИСК ДУБЛИКАТОВ
# ============================================================

function Find-DuplicateGroups {
    <#
    .SYNOPSIS
        Формирует группы дубликатов на основе хэшей.
    .DESCRIPTION
        Группирует файлы по хэшу. Внутри каждой группы разделяет
        на подгруппы хардлинков и обычные файлы.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$FileList
    )

    Write-Host "[4/4] Building duplicate groups..." -ForegroundColor Yellow

    # Фильтруем файлы с хэшем
    $hashedFiles = $FileList | Where-Object { $_.Hash -ne $null }

    if ($hashedFiles.Count -eq 0) {
        Write-Host "  No hashed files to compare." -ForegroundColor Green
        return @()
    }

    # Группируем по хэшу
    $hashGroups = $hashedFiles | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 }

    $result = @()

    foreach ($hashGroup in $hashGroups) {
        $files = $hashGroup.Group

        # Разделяем на хардлинк-подгруппы и обычные файлы
        $hardlinkSubgroups = @{}
        $regularFiles = @()

        foreach ($file in $files) {
            if ($file.IsHardlink -and $file.HardlinkGroupId) {
                $gid = $file.HardlinkGroupId
                if (-not $hardlinkSubgroups.ContainsKey($gid)) {
                    $hardlinkSubgroups[$gid] = @()
                }
                $hardlinkSubgroups[$gid] += $file
            } else {
                $regularFiles += $file
            }
        }

        $result += [PSCustomObject]@{
            Hash             = $hashGroup.Name
            Size             = $files[0].Size
            AllFiles         = $files
            HardlinkGroups   = $hardlinkSubgroups
            RegularFiles     = $regularFiles
            TotalCount       = $files.Count
        }
    }

    Write-Host "  Duplicate groups: $($result.Count)" -ForegroundColor Gray

    return $result
}
# ============================================================
# ВЫВОД РЕЗУЛЬТАТОВ
# ============================================================

function Show-DuplicateGroups {
    <#
    .SYNOPSIS
        Выводит группы дубликатов в консоль.
    .DESCRIPTION
        Показывает хардлинк-группы и обычные файлы отдельно,
        считает потенциальную экономию места.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$DuplicateGroups
    )

    Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan

    if ($DuplicateGroups.Count -eq 0) {
        Write-Host "No duplicate groups found." -ForegroundColor Green
        return
    }

    $totalDuplicates = 0
    $wastedSpace = 0

    foreach ($group in $DuplicateGroups) {
        Write-Host "`n[Hash: $($group.Hash)]" -ForegroundColor Yellow

        # Считаем реальное количество: уникальные пути из HardlinkGroups + RegularFiles + HardlinkTargets
        $allPaths = @{}
        foreach ($gid in $group.HardlinkGroups.Keys) {
            foreach ($f in $group.HardlinkGroups[$gid]) {
                $allPaths[$f.FullPath] = $true
                if ($f.HardlinkTargets) {
                    foreach ($t in $f.HardlinkTargets) {
                        $allPaths[$t] = $true
                    }
                }
            }
        }
        foreach ($f in $group.RegularFiles) {
            $allPaths[$f.FullPath] = $true
        }
        $realTotal = $allPaths.Count

        Write-Host "  Size: $([math]::Round($group.Size/1KB, 2)) KB | Total files: $realTotal" -ForegroundColor Cyan

        # Хардлинк-группы
        if ($group.HardlinkGroups.Count -gt 0) {
            foreach ($gid in $group.HardlinkGroups.Keys) {
                $hlFiles = $group.HardlinkGroups[$gid]
                # Собираем ВСЕ уникальные пути: файлы группы + их цели
                $allPaths = @{}
                foreach ($f in $hlFiles) {
                    $allPaths[$f.FullPath] = $true
                    if ($f.HardlinkTargets) {
                        foreach ($t in $f.HardlinkTargets) {
                            $allPaths[$t] = $true
                        }
                    }
                }
                $totalCount = $allPaths.Count

                Write-Host "  [HARDLINK GROUP] $totalCount files pointing to same data:" -ForegroundColor Green
        
                # Первый файл — «корень», остальные — его цели
                $first = $hlFiles[0]
                Write-Host "      $($first.FullPath)" -ForegroundColor DarkGreen

                # Все цели из HardlinkTargets (включая внешние)
                if ($first.HardlinkTargets -and $first.HardlinkTargets.Count -gt 0) {
                    foreach ($target in $first.HardlinkTargets) {
                        Write-Host "        --> $target" -ForegroundColor DarkGray
                    }
                }
            }
        }

        # Обычные файлы
        if ($group.RegularFiles.Count -gt 0) {
            Write-Host "  [REGULAR FILES] $($group.RegularFiles.Count) files (separate space):" -ForegroundColor Red
            foreach ($f in $group.RegularFiles) {
                Write-Host "      $($f.FullPath)" -ForegroundColor Gray
            }

            # Экономия: (RegularFiles - 1) * Size
            $dupeCount = $group.RegularFiles.Count - 1
            if ($dupeCount -gt 0) {
                $wastedSpace += $group.Size * $dupeCount
                $totalDuplicates += $dupeCount
            }
        }
    }

    # Сводка
    Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Duplicate groups: $($DuplicateGroups.Count)" -ForegroundColor Yellow
    Write-Host "Duplicate files count: $totalDuplicates" -ForegroundColor Yellow

    if ($wastedSpace -gt 1TB) {
        Write-Host "Wasted space: $([math]::Round($wastedSpace/1TB, 2)) TB" -ForegroundColor Red
    } elseif ($wastedSpace -gt 1GB) {
        Write-Host "Wasted space: $([math]::Round($wastedSpace/1GB, 2)) GB" -ForegroundColor Red
    } elseif ($wastedSpace -gt 1MB) {
        Write-Host "Wasted space: $([math]::Round($wastedSpace/1MB, 2)) MB" -ForegroundColor Red
    } else {
        Write-Host "Wasted space: $([math]::Round($wastedSpace/1KB, 2)) KB" -ForegroundColor Red
    }
}

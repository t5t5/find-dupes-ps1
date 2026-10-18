# ============================================================
# ОБНАРУЖЕНИЕ ХАРДЛИНКОВ
# ============================================================

function Add-HardlinkInfo {
    <#
    .SYNOPSIS
        Проверяет каждый файл на наличие жёстких ссылок.
    .DESCRIPTION
        Использует fsutil hardlink list. Если файл уже входит в найденную
        группу, повторно не проверяется. Восстанавливает полные пути
        из относительных, которые возвращает fsutil.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$FileList,

        [string]$DriveRoot = $null
    )

    Write-Host "[2/4] Detecting active hardlinks..." -ForegroundColor Yellow

    # Определяем корень диска, если не передан
    if (-not $DriveRoot) {
        if ($FileList.Count -gt 0) {
            $DriveRoot = (Get-Item -LiteralPath $FileList[0].FullPath).Root.FullName
        } else {
            Write-Host "  No files to check." -ForegroundColor DarkGray
            return $FileList
        }
    }

    $processedPaths = @{}   # Уже обработанные пути
    $groupCounter = 0

    for ($i = 0; $i -lt $FileList.Count; $i++) {
        $file = $FileList[$i]

        # Пропускаем, если уже в группе
        if ($processedPaths.ContainsKey($file.FullPath)) { continue }

        try {
            $output = & fsutil hardlink list $file.FullPath 2>$null

            if ($output -and $output.Count -ge 2) {
                # Собираем полные пути
                $fullPaths = @()
                foreach ($line in $output) {
                    $relativePath = $line.Trim()
                    if ($relativePath -and $relativePath -ne "") {
                        $fullPath = $DriveRoot + $relativePath.TrimStart('\')
                        $fullPaths += $fullPath
                    }
                }

                if ($fullPaths.Count -ge 2) {
                    $groupCounter++
                    $groupId = "HL_$groupCounter"

                    # Помечаем все файлы в группе
                    foreach ($path in $fullPaths) {
                        $processedPaths[$path] = $true

                        # Ищем файл в списке и обновляем
                        $target = $FileList | Where-Object { $_.FullPath -eq $path } | Select-Object -First 1
                        if ($target) {
                            $target.IsHardlink = $true
                            $target.HardlinkGroupId = $groupId
                            $target.HardlinkTargets = $fullPaths | Where-Object { $_ -ne $path }
                        }
                    }

                    Write-Host "  [Found] Hardlink group $groupId : $($fullPaths.Count) files" -ForegroundColor Green
                }
            }
        } catch {
            # Игнорируем ошибки (сетевые диски, права)
        }
    }

    # Считаем итог
    $hardlinkCount = ($FileList | Where-Object { $_.IsHardlink }).Count
    Write-Host "  Files in hardlink groups: $hardlinkCount" -ForegroundColor Gray

    return $FileList
}
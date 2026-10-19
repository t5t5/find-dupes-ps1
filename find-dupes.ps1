# ============================================================
# FIND DUPLICATES
# ============================================================
# Главный скрипт. Подключает библиотеки и запускает основной поток.

# ----- Подключение библиотек -----
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib\FileScanner.ps1"
. "$PSScriptRoot\lib\HardlinkDetector.ps1"
. "$PSScriptRoot\lib\HashCalculator.ps1"
. "$PSScriptRoot\lib\DuplicateFinder.ps1"
. "$PSScriptRoot\lib\Reporter.ps1"
. "$PSScriptRoot\lib\CleanupExporter.ps1"

# ----- Основной поток -----
Write-Host "=== Find Duplicates ===" -ForegroundColor Cyan
Write-Host "Path: $($Config.SearchPath)" -ForegroundColor Gray
Write-Host "Algorithm: $($Config.HashAlgorithm) | Partial: $($Config.PartialHash)" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date

# Шаг 1: Сбор файлов
$files = Get-FileList -Path $Config.SearchPath `
                      -ExcludePatterns $Config.ExcludePatterns `
                      -ExcludeDirs $Config.ExcludeDirs `
                      -MinSize $Config.MinFileSize `
                      -MaxSize $Config.MaxFileSize

if ($files.Count -eq 0) {
    Write-Host "`nNo files to process. Exiting." -ForegroundColor Yellow
    return
}

# Шаг 2: Обнаружение хардлинков
$files = Add-HardlinkInfo -FileList $files

# Шаг 3: Вычисление хэшей
$files = Add-FileHash -FileList $files -Config $Config

# Шаг 4: Поиск дубликатов
$duplicates = Find-DuplicateGroups -FileList $files

# Шаг 5: Вывод
Show-DuplicateGroups -DuplicateGroups $duplicates

# Шаг 6: Экспорт скрипта очистки (всегда, если включено)
if ($Config.ExportCleanup) {
    Export-CleanupScript -DuplicateGroups $duplicates `
                         -OutputPath $Config.CleanupScriptPath `
                         -Action $Config.CleanupAction
}

# (Опционально) Запуск — только если явно включено
if ($Config.RunCleanup -and $Config.ExportCleanup) {
    Write-Host "`n[!] Running cleanup script (RunCleanup = `$true)..." -ForegroundColor Red
    & $Config.CleanupScriptPath
}

# ----- Итог -----
$elapsed = (Get-Date) - $startTime
Write-Host "`n=== DONE in $([math]::Round($elapsed.TotalSeconds, 1)) sec ===" -ForegroundColor Cyan
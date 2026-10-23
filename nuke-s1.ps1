$scriptContent = @'
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "1. Terminating any remaining SentinelOne processes..." -ForegroundColor Cyan
Stop-Process -Name "SentinelAgent", "SentinelServiceHost", "SentinelUI", "SentinelHelperService" -Force
& fltmc.exe unload SentinelMonitor *>$null

Write-Host "2. Removing SentinelOne services and driver registrations..." -ForegroundColor Cyan
$services = @(
    'SentinelAgent',
    'SentinelHelperService',
    'LogProcessorService',
    'SentinelStaticEngine',
    'SentinelMonitor',
    'SentinelDeviceControl',
    'SentinelNetworkMonitor',
    'SentinelELAM'
)
foreach ($svc in $services) {
    & sc.exe stop $svc *>$null
    & sc.exe delete $svc *>$null
    Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Recurse -Force
}

Write-Host "3. Purging SentinelOne and MSI registry remnants..." -ForegroundColor Cyan
$regPaths = @(
    'HKLM:\SOFTWARE\SentinelOne',
    'HKLM:\SOFTWARE\Sentinel Labs',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Sentinel Agent',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{7EF19502-697A-4014-B6F4-25B7EA86F6C2}',
    'HKLM:\SOFTWARE\Classes\Installer\Products\20591FE7A79641046B4F527BAE686F2C',
    'HKLM:\SOFTWARE\Classes\Installer\Features\20591FE7A79641046B4F527BAE686F2C',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\20591FE7A79641046B4F527BAE686F2C',
    'HKLM:\SOFTWARE\Classes\Installer\UpgradeCodes\06BA9B59DEB374C4FA0C5E78A65715A2'
)
foreach ($path in $regPaths) {
    Remove-Item -Path $path -Recurse -Force
}

Write-Host "4. Clearing filesystem remnants (moving any mapped DLLs to Temp)..." -ForegroundColor Cyan
Set-Location C:\Windows\Temp

$folders = @(
    'C:\Program Files\SentinelOne',
    'C:\ProgramData\Sentinel',
    'C:\Windows\System32\drivers\SentinelOne',
    'C:\Windows\Temp\S1'
)

foreach ($folder in $folders) {
    if (Test-Path $folder) {
        & takeown.exe /f $folder /r /d y *>$null
        & icacls.exe $folder /grant Administrators:F /t /c /q *>$null

        Get-ChildItem -Path $folder -Recurse -Force -File | ForEach-Object {
            Remove-Item $_.FullName -Force
            if (Test-Path $_.FullName) {
                $tempTarget = "C:\Windows\Temp\s1_locked_$([guid]::NewGuid().ToString('N')).tmp"
                Move-Item -Path $_.FullName -Destination $tempTarget -Force
            }
        }
        cmd.exe /c "rd /s /q `"$folder`"" *>$null
    }
}

Remove-Item -Path 'C:\Windows\ELAMBKUP\SentinelELAM.sys' -Force

Write-Host "5. Verifying clean state after cleanup..." -ForegroundColor Cyan
$remnantsFound = $false
foreach ($checkPath in @(
    'C:\Program Files\SentinelOne',
    'C:\ProgramData\Sentinel',
    'C:\Windows\System32\drivers\SentinelOne',
    'HKLM:\SOFTWARE\SentinelOne'
)) {
    if (Test-Path $checkPath) {
        Write-Host "   [WARNING] Remnant still exists: $checkPath" -ForegroundColor Yellow
        $remnantsFound = $true
    } else {
        Write-Host "   [OK] Cleared: $checkPath" -ForegroundColor Green
    }
}

if ($remnantsFound) {
    Write-Host "Some remnants remain. A locked handle may require a reboot to fully remove them. Run: shutdown.exe /r /f /t 0" -ForegroundColor Red
    exit 1
}

Write-Host "Cleanup completed successfully. No MSI reinstall was performed." -ForegroundColor Green
'@

$scriptPath = Join-Path $env:WINDIR 'Temp\Fix-S1.ps1'
Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8 -Force

Write-Host "Wrote cleanup script to: $scriptPath" -ForegroundColor Green
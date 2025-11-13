# Script para verificar y solucionar problemas de detección de dispositivos Android

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verificación de Dispositivo Android" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Reiniciar ADB
Write-Host "[1/3] Reiniciando servidor ADB..." -ForegroundColor Yellow
adb kill-server 2>&1 | Out-Null
Start-Sleep -Seconds 2
adb start-server 2>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Host "✅ ADB reiniciado" -ForegroundColor Green
Write-Host ""

# Verificar dispositivos ADB
Write-Host "[2/3] Dispositivos detectados por ADB:" -ForegroundColor Yellow
$adbDevices = adb devices
Write-Host $adbDevices
Write-Host ""

# Verificar dispositivos Flutter
Write-Host "[3/3] Dispositivos detectados por Flutter:" -ForegroundColor Yellow
flutter devices
Write-Host ""

# Diagnóstico
if ($adbDevices -match "device$") {
    Write-Host "✅ Dispositivo detectado correctamente!" -ForegroundColor Green
} elseif ($adbDevices -match "unauthorized") {
    Write-Host "⚠️ Dispositivo detectado pero NO AUTORIZADO" -ForegroundColor Yellow
    Write-Host "   → En tu Android, autoriza la depuración USB cuando aparezca el diálogo" -ForegroundColor White
} elseif ($adbDevices -match "offline") {
    Write-Host "⚠️ Dispositivo OFFLINE" -ForegroundColor Yellow
    Write-Host "   → Desconecta y vuelve a conectar el cable USB" -ForegroundColor White
} else {
    Write-Host "❌ No se detectó ningún dispositivo" -ForegroundColor Red
    Write-Host ""
    Write-Host "Pasos a seguir:" -ForegroundColor Yellow
    Write-Host "1. Verifica que la depuración USB esté activada en tu Android" -ForegroundColor White
    Write-Host "2. Conecta el cable USB (debe ser un cable de datos, no solo carga)" -ForegroundColor White
    Write-Host "3. Autoriza la depuración cuando aparezca el diálogo en el dispositivo" -ForegroundColor White
    Write-Host "4. Verifica los drivers USB en el Administrador de dispositivos" -ForegroundColor White
    Write-Host ""
    Write-Host "Para más detalles, consulta: SOLUCION_DISPOSITIVO_ANDROID.md" -ForegroundColor Cyan
}


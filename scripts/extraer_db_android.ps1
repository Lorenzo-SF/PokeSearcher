# ============================================================================
# Script para Extraer Base de Datos SQLite desde Android a Windows 11
# ============================================================================
# Este script extrae la base de datos de la app Flutter desde un móvil Android
# físico conectado por USB y la copia al escritorio de Windows 11
# ============================================================================

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\poke_search.db"
)

# Configuración
$PACKAGE_NAME = "com.merendandum.poke_searcher"
$DB_NAME = "poke_search.db"
$DEVICE_DB_PATH = "/data/data/$PACKAGE_NAME/app_flutter/$DB_NAME"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Extracción de Base de Datos SQLite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que adb está instalado y en el PATH
Write-Host "[1/5] Verificando ADB..." -ForegroundColor Yellow
$adbPath = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adbPath) {
    Write-Host "ERROR: ADB no encontrado en el PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor, instala Android Platform Tools:" -ForegroundColor Yellow
    Write-Host "1. Descarga desde: https://developer.android.com/studio/releases/platform-tools" -ForegroundColor White
    Write-Host "2. Extrae el archivo ZIP" -ForegroundColor White
    Write-Host "3. Añade la carpeta 'platform-tools' al PATH de Windows" -ForegroundColor White
    Write-Host "4. O ejecuta este script desde la carpeta platform-tools" -ForegroundColor White
    exit 1
}
Write-Host "✓ ADB encontrado: $($adbPath.Source)" -ForegroundColor Green
Write-Host ""

# Verificar que hay un dispositivo conectado
Write-Host "[2/5] Verificando dispositivo Android..." -ForegroundColor Yellow
$devices = adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" }
if (-not $devices) {
    Write-Host "ERROR: No se encontró ningún dispositivo Android conectado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor, verifica:" -ForegroundColor Yellow
    Write-Host "1. El móvil está conectado por USB" -ForegroundColor White
    Write-Host "2. La depuración USB está activada en el móvil" -ForegroundColor White
    Write-Host "3. Has autorizado la conexión en el móvil (aparece un diálogo)" -ForegroundColor White
    Write-Host "4. Ejecuta: adb devices" -ForegroundColor White
    exit 1
}

$deviceCount = ($devices | Measure-Object).Count
if ($deviceCount -gt 1) {
    Write-Host "ADVERTENCIA: Se encontraron $deviceCount dispositivos. Usando el primero." -ForegroundColor Yellow
}

$deviceId = ($devices | Select-Object -First 1) -split '\s+' | Select-Object -First 1
Write-Host "✓ Dispositivo encontrado: $deviceId" -ForegroundColor Green
Write-Host ""

# Verificar que la app está instalada
Write-Host "[3/5] Verificando que la app está instalada..." -ForegroundColor Yellow
$appInstalled = adb shell pm list packages | Select-String -Pattern $PACKAGE_NAME
if (-not $appInstalled) {
    Write-Host "ERROR: La app no está instalada en el dispositivo" -ForegroundColor Red
    Write-Host "Package esperado: $PACKAGE_NAME" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ App instalada: $PACKAGE_NAME" -ForegroundColor Green
Write-Host ""

# Verificar que la base de datos existe
Write-Host "[4/5] Verificando que la base de datos existe..." -ForegroundColor Yellow
$dbExists = adb shell "test -f $DEVICE_DB_PATH && echo 'exists' || echo 'not found'"
if ($dbExists -notmatch "exists") {
    Write-Host "ADVERTENCIA: La base de datos no existe aún en el dispositivo" -ForegroundColor Yellow
    Write-Host "Esto es normal si la app no se ha ejecutado aún o no se ha descargado ningún backup." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opciones:" -ForegroundColor Cyan
    Write-Host "1. Ejecuta la app al menos una vez" -ForegroundColor White
    Write-Host "2. Descarga un backup desde la app" -ForegroundColor White
    Write-Host "3. El script continuará pero puede fallar al extraer" -ForegroundColor White
    Write-Host ""
    $continue = Read-Host "¿Continuar de todas formas? (S/N)"
    if ($continue -ne "S" -and $continue -ne "s") {
        exit 0
    }
} else {
    Write-Host "✓ Base de datos encontrada en el dispositivo" -ForegroundColor Green
}
Write-Host ""

# Extraer la base de datos
Write-Host "[5/5] Extrayendo base de datos..." -ForegroundColor Yellow
Write-Host "Desde: $DEVICE_DB_PATH" -ForegroundColor Gray
Write-Host "Hacia: $OutputPath" -ForegroundColor Gray
Write-Host ""

# Crear directorio de destino si no existe
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Cerrar la app si está corriendo (para evitar bloqueos)
Write-Host "Cerrando la app para evitar bloqueos..." -ForegroundColor Gray
adb shell am force-stop $PACKAGE_NAME | Out-Null
Start-Sleep -Seconds 1

# Extraer el archivo
try {
    adb pull $DEVICE_DB_PATH $OutputPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✓ Base de datos extraída exitosamente" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Ubicación: $OutputPath" -ForegroundColor Cyan
        Write-Host ""
        
        # Mostrar información del archivo
        $fileInfo = Get-Item $OutputPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        Write-Host "Tamaño: $fileSizeMB MB" -ForegroundColor Cyan
        Write-Host "Fecha: $($fileInfo.LastWriteTime)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Ahora puedes:" -ForegroundColor Yellow
        Write-Host "1. Abrir Beekeeper Studio" -ForegroundColor White
        Write-Host "2. Crear una nueva conexión SQLite" -ForegroundColor White
        Write-Host "3. Seleccionar este archivo: $OutputPath" -ForegroundColor White
        Write-Host ""
        
        # Preguntar si quiere abrir Beekeeper Studio
        $openBeekeeper = Read-Host "¿Abrir Beekeeper Studio ahora? (S/N)"
        if ($openBeekeeper -eq "S" -or $openBeekeeper -eq "s") {
            $beekeeperPath = Get-Command beekeeper-studio -ErrorAction SilentlyContinue
            if ($beekeeperPath) {
                Start-Process "beekeeper-studio" -ArgumentList $OutputPath
            } else {
                Write-Host "Beekeeper Studio no encontrado en el PATH. Ábrelo manualmente." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host ""
        Write-Host "ERROR: No se pudo extraer la base de datos" -ForegroundColor Red
        Write-Host "Código de error: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "Posibles causas:" -ForegroundColor Yellow
        Write-Host "1. La app está corriendo (ciérrala primero)" -ForegroundColor White
        Write-Host "2. No tienes permisos (necesitas dispositivo rooteado o usar run-as)" -ForegroundColor White
        Write-Host "3. La base de datos no existe aún" -ForegroundColor White
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Excepción al extraer la base de datos" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}


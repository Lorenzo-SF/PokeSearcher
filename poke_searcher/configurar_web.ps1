# Script para configurar archivos WebAssembly necesarios para web
# Ejecutar: .\configurar_web.ps1

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Configuración de WebAssembly para PokeSearch" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$webDir = Join-Path $PSScriptRoot "web"

# Verificar si el directorio web existe
if (-not (Test-Path $webDir)) {
    Write-Host "Error: Directorio 'web' no encontrado" -ForegroundColor Red
    exit 1
}

Write-Host "Directorio web: $webDir" -ForegroundColor Yellow
Write-Host ""

# Verificar archivos existentes
$sqlite3Wasm = Join-Path $webDir "sqlite3.wasm"
$driftWorker = Join-Path $webDir "drift_worker.js"

$necesitaSqlite = -not (Test-Path $sqlite3Wasm)
$necesitaWorker = -not (Test-Path $driftWorker)

if (-not $necesitaSqlite -and -not $necesitaWorker) {
    Write-Host "✓ Todos los archivos WebAssembly ya están presentes" -ForegroundColor Green
    Write-Host ""
    Write-Host "Archivos encontrados:" -ForegroundColor Yellow
    Write-Host "  - sqlite3.wasm" -ForegroundColor Green
    Write-Host "  - drift_worker.js" -ForegroundColor Green
    exit 0
}

Write-Host "Archivos necesarios:" -ForegroundColor Yellow
if ($necesitaSqlite) {
    Write-Host "  ✗ sqlite3.wasm (faltante)" -ForegroundColor Red
} else {
    Write-Host "  ✓ sqlite3.wasm (presente)" -ForegroundColor Green
}

if ($necesitaWorker) {
    Write-Host "  ✗ drift_worker.js (faltante)" -ForegroundColor Red
} else {
    Write-Host "  ✓ drift_worker.js (presente)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Para descargar los archivos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. sqlite3.wasm:" -ForegroundColor Cyan
Write-Host "   https://github.com/simolus3/sqlite3.dart/releases" -ForegroundColor White
Write-Host "   Buscar la última versión y descargar sqlite3.wasm" -ForegroundColor Gray
Write-Host ""
Write-Host "2. drift_worker.js:" -ForegroundColor Cyan
Write-Host "   https://github.com/simolus3/drift/releases" -ForegroundColor White
Write-Host "   Buscar la última versión y descargar drift_worker.js" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Colocar ambos archivos en: $webDir" -ForegroundColor Yellow
Write-Host ""

# Intentar descargar automáticamente (opcional)
$descargar = Read-Host "¿Intentar descargar automáticamente? (S/N)"

if ($descargar -eq "S" -or $descargar -eq "s") {
    Write-Host ""
    Write-Host "Descargando archivos..." -ForegroundColor Yellow
    
    try {
        # Intentar descargar sqlite3.wasm
        if ($necesitaSqlite) {
            Write-Host "Descargando sqlite3.wasm..." -ForegroundColor Cyan
            # Nota: Esto es un ejemplo, las URLs reales pueden variar
            $sqliteUrl = "https://github.com/simolus3/sqlite3.dart/releases/latest/download/sqlite3.wasm"
            try {
                Invoke-WebRequest -Uri $sqliteUrl -OutFile $sqlite3Wasm -ErrorAction Stop
                Write-Host "✓ sqlite3.wasm descargado" -ForegroundColor Green
            } catch {
                Write-Host "✗ No se pudo descargar automáticamente. Descarga manual requerida." -ForegroundColor Red
            }
        }
        
        # Intentar descargar drift_worker.js
        if ($necesitaWorker) {
            Write-Host "Descargando drift_worker.js..." -ForegroundColor Cyan
            $workerUrl = "https://github.com/simolus3/drift/releases/latest/download/drift_worker.js"
            try {
                Invoke-WebRequest -Uri $workerUrl -OutFile $driftWorker -ErrorAction Stop
                Write-Host "✓ drift_worker.js descargado" -ForegroundColor Green
            } catch {
                Write-Host "✗ No se pudo descargar automáticamente. Descarga manual requerida." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host ""
        Write-Host "Error al descargar automáticamente. Por favor, descarga manualmente." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Configuración completada" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para ejecutar en web:" -ForegroundColor Yellow
Write-Host "  flutter run -d chrome" -ForegroundColor White
Write-Host ""


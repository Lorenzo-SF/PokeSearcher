# Script para ejecutar PokeSearch en diferentes plataformas
# Uso: .\ejecutar.ps1 [android|windows|web]

param(
    [Parameter(Position=0)]
    [ValidateSet("android", "windows", "web", "")]
    [string]$Plataforma = ""
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PokeSearch - Ejecutar Aplicación" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que Flutter está instalado
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "Flutter detectado: $flutterVersion" -ForegroundColor Green
} catch {
    Write-Host "Error: Flutter no está instalado o no está en el PATH" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Si no se especificó plataforma, mostrar menú
if ([string]::IsNullOrEmpty($Plataforma)) {
    Write-Host "Selecciona la plataforma:" -ForegroundColor Yellow
    Write-Host "  1. Android (móvil/tablet)" -ForegroundColor White
    Write-Host "  2. Windows (aplicación de escritorio)" -ForegroundColor White
    Write-Host "  3. Web (Chrome)" -ForegroundColor White
    Write-Host ""
    
    $opcion = Read-Host "Opción (1-3)"
    
    switch ($opcion) {
        "1" { $Plataforma = "android" }
        "2" { $Plataforma = "windows" }
        "3" { $Plataforma = "web" }
        default {
            Write-Host "Opción inválida" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Plataforma seleccionada: $Plataforma" -ForegroundColor Yellow
Write-Host ""

# Verificar dependencias
Write-Host "Verificando dependencias..." -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al obtener dependencias" -ForegroundColor Red
    exit 1
}

# Generar código de Drift si es necesario
$generatedFile = Join-Path $PSScriptRoot "lib\database\app_database.g.dart"
if (-not (Test-Path $generatedFile)) {
    Write-Host ""
    Write-Host "Generando código de Drift..." -ForegroundColor Cyan
    flutter pub run build_runner build --delete-conflicting-outputs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error al generar código" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Ejecutando aplicación..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Ejecutar según la plataforma
switch ($Plataforma.ToLower()) {
    "android" {
        Write-Host "Ejecutando en Android..." -ForegroundColor Green
        Write-Host ""
        flutter run
    }
    "windows" {
        Write-Host "Ejecutando en Windows..." -ForegroundColor Green
        Write-Host ""
        flutter run -d windows
    }
    "web" {
        Write-Host "Ejecutando en Web (Chrome)..." -ForegroundColor Green
        Write-Host ""
        
        # Verificar archivos WASM
        $webDir = Join-Path $PSScriptRoot "web"
        $sqlite3Wasm = Join-Path $webDir "sqlite3.wasm"
        $driftWorker = Join-Path $webDir "drift_worker.js"
        
        if (-not (Test-Path $sqlite3Wasm) -or -not (Test-Path $driftWorker)) {
            Write-Host "Advertencia: Archivos WebAssembly no encontrados" -ForegroundColor Yellow
            Write-Host "La base de datos puede tener funcionalidad limitada en web." -ForegroundColor Yellow
            Write-Host "Ejecuta .\configurar_web.ps1 para configurar WebAssembly" -ForegroundColor Yellow
            Write-Host ""
            $continuar = Read-Host "¿Continuar de todos modos? (S/N)"
            if ($continuar -ne "S" -and $continuar -ne "s") {
                exit 0
            }
        }
        
        flutter run -d chrome
    }
    default {
        Write-Host "Plataforma no reconocida: $Plataforma" -ForegroundColor Red
        exit 1
    }
}


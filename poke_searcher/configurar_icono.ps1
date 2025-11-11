# Script para configurar el icono de la app desde pokeball.svg
# Este script convierte el SVG a PNG y luego genera los iconos para todas las plataformas

$svgPath = "assets\pokeball.svg"
$pngPath = "assets\pokeball_icon.png"

Write-Host "=== Configurando icono de la app desde pokeball.svg ===" -ForegroundColor Cyan
Write-Host ""

# Paso 1: Convertir SVG a PNG
Write-Host "Paso 1: Convirtiendo SVG a PNG..." -ForegroundColor Yellow

$converted = $false

# Intentar con Inkscape
if (Get-Command inkscape -ErrorAction SilentlyContinue) {
    Write-Host "  Usando Inkscape..." -ForegroundColor Green
    inkscape $svgPath --export-filename=$pngPath --export-width=1024 --export-height=1024
    if ($LASTEXITCODE -eq 0 -and (Test-Path $pngPath)) {
        Write-Host "  ✓ Conversión exitosa con Inkscape" -ForegroundColor Green
        $converted = $true
    }
}

# Intentar con ImageMagick si Inkscape no funcionó
if (-not $converted -and (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host "  Usando ImageMagick..." -ForegroundColor Green
    magick $svgPath -resize 1024x1024 -background none $pngPath
    if ($LASTEXITCODE -eq 0 -and (Test-Path $pngPath)) {
        Write-Host "  ✓ Conversión exitosa con ImageMagick" -ForegroundColor Green
        $converted = $true
    }
}

# Si no hay herramientas, usar conversor online o manual
if (-not $converted) {
    Write-Host ""
    Write-Host "⚠ No se encontraron herramientas de conversión instaladas" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opciones para convertir el SVG a PNG:" -ForegroundColor Cyan
    Write-Host "  1. Instalar Inkscape: https://inkscape.org/release/" -ForegroundColor White
    Write-Host "  2. Instalar ImageMagick: https://imagemagick.org/script/download.php" -ForegroundColor White
    Write-Host "  3. Usar conversor online:" -ForegroundColor White
    Write-Host "     - https://convertio.co/svg-png/" -ForegroundColor Gray
    Write-Host "     - https://cloudconvert.com/svg-to-png" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Si usas un conversor online:" -ForegroundColor Yellow
    Write-Host "  - Sube: $svgPath" -ForegroundColor White
    Write-Host "  - Descarga como PNG de 1024x1024 píxeles" -ForegroundColor White
    Write-Host "  - Guárdalo como: $pngPath" -ForegroundColor White
    Write-Host ""
    
    $continue = Read-Host "¿Ya tienes el PNG en $pngPath? (S/N)"
    if ($continue -ne "S" -and $continue -ne "s") {
        Write-Host "Operación cancelada. Vuelve a ejecutar este script después de convertir el SVG." -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $pngPath)) {
        Write-Host "Error: No se encontró el archivo $pngPath" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  ✓ Archivo PNG encontrado" -ForegroundColor Green
    $converted = $true
}

if (-not $converted) {
    Write-Host "Error: No se pudo convertir el SVG a PNG" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Paso 2: Actualizando pubspec.yaml..." -ForegroundColor Yellow

# Leer pubspec.yaml
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

# Actualizar la configuración de flutter_launcher_icons
$newConfig = @"
# Configuración de iconos de la app
flutter_launcher_icons:
  android: true
  ios: true
  web:
    generate: true
  windows:
    generate: true
  macos:
    generate: true
  linux:
    generate: true
  image_path: "assets/pokeball_icon.png"
  min_sdk_android: 21
  adaptive_icon_background: "#DC143C"
  adaptive_icon_foreground: "assets/pokeball_icon.png"
"@

# Reemplazar la sección de flutter_launcher_icons
if ($pubspecContent -match "(?s)# Configuración de iconos.*?adaptive_icon_foreground.*?\n") {
    $pubspecContent = $pubspecContent -replace "(?s)# Configuración de iconos.*?adaptive_icon_foreground.*?\n", $newConfig + "`n"
} else {
    # Si no existe, agregarlo al final
    $pubspecContent = $pubspecContent.TrimEnd() + "`n`n" + $newConfig
}

Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline
Write-Host "  ✓ pubspec.yaml actualizado" -ForegroundColor Green

Write-Host ""
Write-Host "Paso 3: Instalando dependencias..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al instalar dependencias" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Dependencias instaladas" -ForegroundColor Green

Write-Host ""
Write-Host "Paso 4: Generando iconos para todas las plataformas..." -ForegroundColor Yellow
flutter pub run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al generar iconos" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Iconos generados exitosamente" -ForegroundColor Green

Write-Host ""
Write-Host "=== ¡Icono configurado correctamente! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Los iconos se han generado para:" -ForegroundColor Cyan
Write-Host "  - Android" -ForegroundColor White
Write-Host "  - iOS" -ForegroundColor White
Write-Host "  - Web" -ForegroundColor White
Write-Host "  - Windows" -ForegroundColor White
Write-Host "  - macOS" -ForegroundColor White
Write-Host "  - Linux" -ForegroundColor White
Write-Host ""
Write-Host "Reconstruye la app para ver los cambios:" -ForegroundColor Yellow
Write-Host "  flutter clean" -ForegroundColor Gray
Write-Host "  flutter run" -ForegroundColor Gray


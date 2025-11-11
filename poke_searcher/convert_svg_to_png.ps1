# Script para convertir pokeball.svg a PNG para el icono de la app
# Requiere que tengas instalado Inkscape o ImageMagick

$svgPath = "assets\pokeball.svg"
$pngPath = "assets\pokeball_icon.png"

Write-Host "Intentando convertir $svgPath a $pngPath..."

# Intentar con Inkscape
if (Get-Command inkscape -ErrorAction SilentlyContinue) {
    Write-Host "Usando Inkscape..."
    inkscape $svgPath --export-filename=$pngPath --export-width=1024 --export-height=1024
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Conversión exitosa con Inkscape"
        exit 0
    }
}

# Intentar con ImageMagick
if (Get-Command magick -ErrorAction SilentlyContinue) {
    Write-Host "Usando ImageMagick..."
    magick $svgPath -resize 1024x1024 $pngPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Conversión exitosa con ImageMagick"
        exit 0
    }
}

# Si no hay herramientas, proporcionar instrucciones
Write-Host ""
Write-Host "No se encontraron herramientas de conversión (Inkscape o ImageMagick)"
Write-Host ""
Write-Host "Opciones:"
Write-Host "1. Instalar Inkscape desde https://inkscape.org/"
Write-Host "2. Instalar ImageMagick desde https://imagemagick.org/"
Write-Host "3. Usar un conversor online: https://convertio.co/svg-png/"
Write-Host "4. Usar el SVG directamente (requiere configuración manual)"
Write-Host ""
Write-Host "Si conviertes manualmente, guarda el PNG como: assets/pokeball_icon.png (1024x1024 px)"
exit 1


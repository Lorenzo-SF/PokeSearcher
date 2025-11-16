# Corrección: Descarga Completa de Archivos Multimedia

## Problema Identificado

El script estaba descargando solo archivos "esenciales", lo que causaba que los ZIPs ocuparan mucho menos espacio (~200MB vs ~700MB esperados). Esto se debía a:

1. **Filtro demasiado restrictivo en urls.txt**: Solo descargaba archivos "esenciales" (dream-world SVG, official-artwork PNG, home PNG, cries)
2. **Solo 3 tipos de sprites de versions**: Solo descargaba `front_transparent`, `front_shiny_transparent`, `front_gray`
3. **No descargaba sprites de back**: Faltaban `back_default`, `back_shiny`, `back_transparent`, etc.
4. **Muchos archivos disponibles no se descargaban**: El filtro descartaba la mayoría de archivos multimedia

## Correcciones Aplicadas

### 1. Eliminación del Filtro "Esenciales"

**Antes:**
```powershell
# Filtrar solo las URLs esenciales:
$isEssential = $false
if ($urlLower -match 'dream-world.*\.svg$') {
    $isEssential = $true
}
# ... más filtros restrictivos ...
if (-not $isEssential) {
    continue
}
```

**Después:**
```powershell
# Descargar TODOS los archivos multimedia (no solo "esenciales")
# Filtrar solo archivos multimedia válidos (imágenes, audio, video)
$isMedia = $urlLower -match '\.(png|jpg|jpeg|gif|svg|webp|bmp|ogg|mp3|wav|mp4|webm)$'
if (-not $isMedia) {
    continue
}
```

### 2. Descarga Completa de Sprites de Versions

**Antes:**
```powershell
# Solo descargaba 3 tipos:
- front_transparent
- front_shiny_transparent
- front_gray
```

**Después:**
```powershell
# Descarga TODOS los sprites disponibles:
$spriteProperties = @(
    'front_default', 'front_shiny', 'front_transparent', 'front_shiny_transparent', 'front_gray',
    'back_default', 'back_shiny', 'back_transparent', 'back_shiny_transparent', 'back_gray'
)
```

### 3. Descarga de Sprites de Back

**Añadido:**
```powershell
# Descargar sprites de back (back_default, back_shiny)
if ($sprites.back_default) {
    # Descargar back_default
}
if ($sprites.back_shiny) {
    # Descargar back_shiny
}
```

## Impacto Esperado

Con estas correcciones, el script ahora descargará:

1. **Todos los archivos multimedia desde urls.txt** (no solo "esenciales")
2. **Todos los sprites de versions** (10 tipos por generación/versión en lugar de 3)
3. **Sprites de back** (back_default, back_shiny)
4. **Todos los archivos disponibles** en PokeAPI

Esto debería aumentar significativamente el tamaño de los ZIPs, acercándose a los ~700MB esperados.

## Próximos Pasos

1. **Ejecutar FASE 2 nuevamente** para descargar todos los archivos:
   ```powershell
   .\scripts\descargar_pokeapi.ps1
   # O solo FASE 2 si ya tienes los JSONs:
   # (ejecutar manualmente la función Download-MediaFilesInParallel)
   ```

2. **Verificar el tamaño de los archivos descargados**:
   ```powershell
   Get-ChildItem -Path "$env:USERPROFILE\Desktop\pokemon_data\pokemon" -Recurse -File | 
       Measure-Object -Property Length -Sum | 
       Select-Object @{Name="TotalMB";Expression={[Math]::Round($_.Sum / 1MB, 2)}}
   ```

3. **Regenerar ZIPs** (FASE 3):
   ```powershell
   .\scripts\descargar_pokeapi.ps1 -OnlyPhase3
   ```

4. **Verificar tamaño de ZIPs generados**:
   ```powershell
   Get-ChildItem -Path "$env:USERPROFILE\Desktop\pokemon_data\backup\git_backups\*.zip" | 
       Select-Object Name, @{Name="SizeMB";Expression={[Math]::Round($_.Length / 1MB, 2)}}
   ```

## Notas

- El proceso de descarga tomará más tiempo (más archivos)
- El tamaño de los ZIPs debería aumentar significativamente
- Todos los archivos se seguirán organizando con nombres aplanados para Flutter
- La compresión sigue siendo `Optimal` para balancear tamaño y velocidad


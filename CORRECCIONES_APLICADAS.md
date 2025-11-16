# Correcciones Aplicadas - Problemas de Archivos Multimedia y Pokedexes

## Problemas Identificados

### 1. Archivos `artwork_official` no encontrados

**Error observado:**
```
[ERROR] Archivo de imagen no existe: /data/user/0/.../poke_searcher_data/media_pokemon_1_artwork_official.svg
```

**Causa:**
- El script genera archivos con formato: `pokemon_{id}_default_artwork_official.{ext}`
- Se copian como: `media_pokemon_{id}_default_artwork_official.{ext}`
- Pero `MediaPathHelper` transforma la ruta `media/pokemon/{id}/artwork_official.{ext}` a `media_pokemon_{id}_artwork_official.{ext}` (sin `_default_`)
- Por lo tanto, no encuentra el archivo porque el nombre real incluye `_default_`

**Solución aplicada:**
- Modificado `MediaPathHelper.assetPathToLocalPath` para buscar también la variante con `_default_` cuando no encuentra el archivo sin `_default_`
- Aplica a: `artwork_official`, `sprite_front_default`, `sprite_front_shiny`, `cry_latest`, `cry_legacy`

**Archivo modificado:**
- `poke_searcher/lib/utils/media_path_helper.dart`

### 2. Pokedexes marcadas como incompletas incorrectamente

**Error observado:**
```
[REGION] [kanto] Incompleta (2 pokedexes faltantes)
[POKEDEX] [ID: 2] Pokedex incompleta
[ERROR] Error al obtener pokedexes incompletas: ApiException: Error al obtener recurso desde URL: 404
```

**Causa posible:**
- Las relaciones de `PokedexEntries` no se están generando o insertando correctamente
- La verificación de pokedexes incompletas está marcando pokedexes como incompletas cuando en realidad tienen entradas
- El error 404 sugiere que está intentando descargar pokedexes que ya deberían estar en la BD

**Solución aplicada:**
- Añadido logging adicional en `getIncompletePokedexes` para diagnosticar el problema
- Verificar que las relaciones se están generando correctamente en el CSV
- Verificar que las relaciones se están insertando correctamente desde el CSV

**Archivos modificados:**
- `poke_searcher/lib/services/download/download_service.dart` (logging adicional)

**Verificación necesaria:**
- Revisar el CSV `27_pokedex_entries.csv` generado para verificar que tiene entradas
- Revisar los logs de inserción en `BackupProcessor._insertPokedexEntries` para verificar que se están insertando correctamente

## Correcciones Aplicadas

### ✅ Corrección 1: MediaPathHelper - Búsqueda de archivos con `_default_`

**Archivo:** `poke_searcher/lib/utils/media_path_helper.dart`

**Cambio:**
- Añadida lógica para buscar variantes con `_default_` cuando no se encuentra el archivo sin `_default_`
- Aplica a archivos de pokemon: `artwork_official`, `sprite_front_default`, `sprite_front_shiny`, `cry_latest`, `cry_legacy`

**Código añadido:**
```dart
// PRIORIDAD 2: Para archivos de pokemon, buscar variante con _default_
// Ejemplo: media_pokemon_1_artwork_official.svg -> media_pokemon_1_default_artwork_official.svg
if (fileName.startsWith('media_pokemon_') && 
    (fileName.contains('_artwork_official') || 
     fileName.contains('_sprite_front_default') ||
     fileName.contains('_sprite_front_shiny') ||
     fileName.contains('_cry_latest') ||
     fileName.contains('_cry_legacy'))) {
  // Intentar insertar _default_ antes del tipo de archivo
  // ... lógica de búsqueda alternativa
}
```

### ✅ Corrección 2: Logging adicional para diagnóstico de pokedexes

**Archivo:** `poke_searcher/lib/services/download/download_service.dart`

**Cambio:**
- Añadido logging para ver cuántas entradas tiene cada pokedex
- Ayuda a diagnosticar si el problema es que no hay entradas o si la verificación está mal

**Código añadido:**
```dart
Logger.pokedex('Pokedex tiene ${entries.length} entradas', pokedexName: 'ID: $apiId');
```

## Verificaciones Necesarias

### 1. Verificar generación de CSV de PokedexEntries

**Comando:**
```powershell
# Ejecutar solo FASE 3 del script
.\scripts\descargar_pokeapi.ps1 -OnlyPhase3
```

**Verificar:**
- El archivo `27_pokedex_entries.csv` tiene filas (más allá del header)
- Las filas tienen formato: `pokedex_id;pokemon_id;entry_number`
- Los `pokemon_id` son válidos (existen en `23_pokemon.csv`)

### 2. Verificar inserción de PokedexEntries

**Revisar logs:**
- Buscar en los logs: `[BackupProcessor] _insertPokedexEntries`
- Verificar que se están insertando entradas (no debería decir "0 entries válidos")
- Verificar que no hay muchos errores

### 3. Verificar relaciones en la BD

**Query SQL sugerida:**
```sql
-- Verificar que hay entradas de pokedex
SELECT COUNT(*) FROM pokedex_entries;

-- Verificar entradas por pokedex
SELECT pokedex_id, COUNT(*) as count 
FROM pokedex_entries 
GROUP BY pokedex_id 
ORDER BY pokedex_id;

-- Verificar que los pokemon_id existen
SELECT COUNT(*) 
FROM pokedex_entries pe
LEFT JOIN pokemon p ON pe.pokemon_id = p.id
WHERE p.id IS NULL;
```

## Próximos Pasos

1. **Ejecutar script de generación de CSV** para verificar que se generan correctamente las relaciones
2. **Revisar logs de inserción** para verificar que se están insertando correctamente
3. **Verificar en la BD** que las relaciones existen
4. **Si el problema persiste**, revisar la lógica de `Generate-PokedexEntriesCsv` para verificar que está asignando correctamente los pokemons a las pokedexes

## Notas

- El problema de archivos `artwork_official` debería estar resuelto con la corrección aplicada
- El problema de pokedexes incompletas requiere verificación adicional para determinar si es un problema de generación, inserción o verificación


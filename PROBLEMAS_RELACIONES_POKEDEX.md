# Problemas Identificados: Relaciones de Pokedex y Pokemons Iniciales

## Problemas Reportados

1. **Ninguna región muestra listados de pokemon**
2. **No se muestran los pokemons iniciales**
3. **Pokedexes marcadas como incompletas cuando deberían estar completas**

## Análisis del Problema

### Problema Principal: Relaciones de PokedexEntries no se están generando/insertando

**Síntomas:**
- `getPokedexEntries(pokedex.id)` retorna lista vacía
- `getUniquePokemonByRegion(regionId)` retorna mapa vacío
- Por lo tanto, no se muestran pokemons en las regiones

**Causa posible:**
1. El CSV `27_pokedex_entries.csv` no se está generando correctamente
2. El CSV se genera pero está vacío o con datos incorrectos
3. El CSV se genera correctamente pero no se está insertando en la BD
4. Los IDs de pokemon no coinciden entre el CSV y la BD

## Correcciones Aplicadas

### ✅ 1. MediaPathHelper - Búsqueda de archivos con `_default_`

**Archivo:** `poke_searcher/lib/utils/media_path_helper.dart`

**Problema:** Los archivos se generan como `media_pokemon_{id}_default_artwork_official.{ext}` pero se buscan como `media_pokemon_{id}_artwork_official.{ext}`

**Solución:** Añadida lógica para buscar variante con `_default_` cuando no se encuentra sin `_default_`

### ✅ 2. Logging adicional en script de generación

**Archivo:** `scripts/descargar_pokeapi.ps1`

**Añadido:**
- Logging de conteo de filas generadas para `PokedexEntries`, `Pokemon`, `Regions`
- Validación de que pokemons existen en `idMaps` antes de usar `Get-DbId`
- Validación de que variantes existen antes de asignarlas
- Advertencias cuando no se asignan pokemons a pokedexes
- Resumen final con estadísticas de generación

### ✅ 3. Logging adicional en verificación de pokedexes

**Archivo:** `poke_searcher/lib/services/download/download_service.dart`

**Añadido:**
- Logging de cuántas entradas tiene cada pokedex
- Ayuda a diagnosticar si el problema es generación o inserción

## Verificaciones Necesarias

### 1. Verificar que el CSV se está generando correctamente

**Comando:**
```powershell
# Ejecutar solo FASE 3 del script
.\scripts\descargar_pokeapi.ps1 -OnlyPhase3
```

**Verificar en la salida:**
- `[INFO] PokedexEntries generado: X relaciones` - Debe ser > 0
- `[INFO] Resumen: X especies procesadas, Y con entradas, Z entradas generadas` - Debe tener valores > 0
- No debe aparecer `[ERROR CRÍTICO] PokedexEntries está vacío`

**Verificar archivo CSV:**
- Abrir `backup/git_backups/poke_searcher_backup_database.zip`
- Extraer `27_pokedex_entries.csv`
- Verificar que tiene filas (más allá del header)
- Verificar formato: `pokedex_id;pokemon_id;entry_number`
- Verificar que los `pokemon_id` son válidos (existen en `23_pokemon.csv`)

### 2. Verificar que el CSV se está insertando correctamente

**Revisar logs de la app:**
- Buscar: `[BackupProcessor] _insertPokedexEntries`
- Verificar que dice: `Procesados X entries, Y válidos, 0 errores`
- Verificar que `Y válidos` es > 0
- Verificar que no dice: `⚠️ ADVERTENCIA: No se pudo procesar ningún pokedex entry válido`

### 3. Verificar relaciones en la BD

**Query SQL sugerida:**
```sql
-- Verificar que hay entradas de pokedex
SELECT COUNT(*) FROM pokedex_entries;
-- Debe ser > 0

-- Verificar entradas por pokedex
SELECT pokedex_id, COUNT(*) as count 
FROM pokedex_entries 
GROUP BY pokedex_id 
ORDER BY pokedex_id;
-- Cada pokedex debe tener entradas

-- Verificar que los pokemon_id existen
SELECT COUNT(*) 
FROM pokedex_entries pe
LEFT JOIN pokemon p ON pe.pokemon_id = p.id
WHERE p.id IS NULL;
-- Debe ser 0 (todos los pokemon_id deben existir)

-- Verificar pokemons por región
SELECT r.name, COUNT(DISTINCT pe.pokemon_id) as pokemon_count
FROM regions r
JOIN pokedex p ON p.region_id = r.id
JOIN pokedex_entries pe ON pe.pokedex_id = p.id
GROUP BY r.id, r.name
ORDER BY r.name;
-- Cada región debe tener pokemons
```

### 4. Verificar pokemons iniciales

**Verificar en CSV de Regions:**
- Abrir `03_regions.csv`
- Verificar columna `processed_starters_json`
- Debe contener JSON con array de nombres: `["bulbasaur","charmander","squirtle"]` para kanto

**Verificar en BD:**
```sql
-- Verificar processed_starters_json
SELECT id, name, processed_starters_json 
FROM regions 
WHERE processed_starters_json IS NOT NULL;
-- Debe tener datos para cada región

-- Verificar que se pueden obtener pokemons iniciales
-- (usar la app o el DAO)
```

## Posibles Causas del Problema

### Causa 1: Orden de generación incorrecto

**Problema:** `Generate-PokedexEntriesCsv` se ejecuta antes de que `Generate-PokemonCsv` complete la generación de IDs.

**Verificación:** El orden en el script es correcto:
- `23_pokemon.csv` (línea 4064) se genera ANTES de
- `27_pokedex_entries.csv` (línea 4068)

**Solución aplicada:** Añadida validación para verificar que pokemons existen en `idMaps` antes de usar `Get-DbId`

### Causa 2: IDs no coinciden

**Problema:** Los IDs generados en `Generate-PokemonCsv` no coinciden con los usados en `Generate-PokedexEntriesCsv`.

**Verificación:** Ambos usan `Get-DbId "pokemon" $apiId` que usa el mismo `$script:idMaps["pokemon"]`, así que deberían coincidir.

**Solución aplicada:** Añadida validación para verificar que pokemons existen antes de usarlos

### Causa 3: CSV no se está insertando

**Problema:** El CSV se genera correctamente pero `BackupProcessor._insertPokedexEntries` no lo está insertando.

**Verificación:** Revisar logs de inserción

**Solución aplicada:** Añadido logging adicional en inserción

### Causa 4: Lógica de asignación incorrecta

**Problema:** La lógica en `Generate-PokedexEntriesCsv` no está asignando pokemons correctamente a pokedexes.

**Verificación:** Revisar warnings en la salida del script

**Solución aplicada:** Añadidos warnings cuando no se asignan pokemons

## Próximos Pasos

1. **Ejecutar script de generación** y revisar la salida para ver:
   - Cuántas relaciones se generan
   - Si hay warnings sobre pokemons no encontrados
   - Si hay warnings sobre especies sin pokemon default

2. **Revisar CSV generado** para verificar:
   - Que tiene filas
   - Que los IDs son válidos
   - Que el formato es correcto

3. **Revisar logs de inserción** para verificar:
   - Que se están insertando entradas
   - Que no hay errores

4. **Verificar en la BD** que las relaciones existen

5. **Si el problema persiste**, revisar la lógica de asignación en `Generate-PokedexEntriesCsv`

## Notas sobre Pokemons Iniciales

Los pokemons iniciales se detectan en el script usando el diccionario `$RegionStarters` y se guardan en `processed_starters_json` en el CSV de Regions.

La app los lee usando `PokedexDao.getStarterPokemon(regionId)` que:
1. Obtiene la región
2. Parsea `processed_starters_json` para obtener nombres
3. Busca las especies por nombre
4. Obtiene los pokemons de esas especies

**Verificar:**
- Que `processed_starters_json` se está generando correctamente en el CSV
- Que se está insertando correctamente en la BD
- Que `getStarterPokemon` está funcionando correctamente


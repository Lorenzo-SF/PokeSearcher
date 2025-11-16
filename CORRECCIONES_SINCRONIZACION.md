# Correcciones de Sincronización Script ↔ App

## Problemas Identificados

1. **Rutas de archivos multimedia no coinciden**:
   - Script genera: `assets/media_pokemon_1_default_artwork_official.svg`
   - App busca: `media_pokemon_1_artwork_official.svg` (sin `_default_`)
   - Archivo real: `media_pokemon_1_default_artwork_official.svg`

2. **Relaciones pokedex_entries no se generan correctamente**:
   - Validaciones añadidas pero puede haber problemas de orden
   - Necesita verificar que pokemons se generan antes de relaciones

3. **Pokemons iniciales no se muestran**:
   - `processed_starters` se genera pero puede no insertarse correctamente

## Correcciones Aplicadas

### ✅ 1. Rutas de archivos multimedia sincronizadas

**Script (`Copy-PokemonMediaFiles`):**
- ✅ Ahora genera rutas como `assets/media_pokemon_{id}_default_{filename}.{ext}`
- ✅ Los archivos se copian como `media_pokemon_{id}_default_{filename}.{ext}`

**App (`MediaPathHelper`):**
- ✅ Ya tiene lógica para buscar variantes con `_default_`
- ✅ Busca primero el nombre exacto, luego la variante con `_default_`

### ✅ 2. `version_groups_json` añadido a Pokedex

**Script:**
- ✅ `Generate-PokedexCsv` ahora incluye `version_groups_json`

**Modelo:**
- ✅ `Pokedex` tiene columna `versionGroupsJson`

**BackupProcessor:**
- ✅ `_insertPokedex` inserta `versionGroupsJson`

### ✅ 3. Detección de variantes regionales mejorada

**Script:**
- ✅ `Get-RegionNameFromPokemonName` busca al principio y al final
- ✅ Mapeo para "kantonian" → "kanto"

### ✅ 4. Validaciones y logging

**Script:**
- ✅ Validación de que pokemons existen antes de usar
- ✅ Logging de estadísticas
- ✅ Advertencias cuando no se asignan pokemons

**BackupProcessor:**
- ✅ Verificación de CSV vacío
- ✅ Resumen de entradas por pokedex
- ✅ Logging de pokemons iniciales

## Verificaciones Necesarias

1. **Orden de generación de CSV**:
   - `Pokemon` (23) debe generarse ANTES de `PokedexEntries` (27) ✅
   - `PokemonSpecies` (21) debe generarse ANTES de `Pokemon` (23) ✅

2. **Sincronización de nombres de archivo**:
   - Script genera: `pokemon_{id}_default_{filename}.{ext}`
   - Script copia como: `media_pokemon_{id}_default_{filename}.{ext}`
   - CSV tiene: `assets/media_pokemon_{id}_default_{filename}.{ext}`
   - App busca: `media_pokemon_{id}_default_{filename}.{ext}` (después de quitar `assets/`)

3. **Lógica de asignación de variantes**:
   - Si hay variante regional → usar variante para pokedexes de esa región
   - Si NO hay variante → usar default para todas las pokedexes
   - Si hay variante → default NO va a pokedexes de esa región

## Próximos Pasos

1. Ejecutar script y verificar logs
2. Verificar CSV generado
3. Probar inserción en app
4. Verificar que se muestran pokemons por región
5. Verificar que se muestran pokemons iniciales


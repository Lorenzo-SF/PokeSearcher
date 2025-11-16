# Definiciones de Relaciones y Datos de Pokémon

## Fuente de Datos: PokeAPI JSONs

### 1. Regiones (`region`)

**Datos disponibles en JSON:**
- `pokedexes`: Lista de pokedexes de esta región
- `pokemon_starters`: Lista de pokemons iniciales de esta región (nombres)
- `version_groups`: Grupos de versiones (juegos) de esta región
- `main_generation`: Generación principal de esta región

**Uso:**
- **Lista de pokemons por región**: Se obtiene de las pokedexes de la región
- **Relación generación-región**: `main_generation` → `generation`
- **Relación versiones-región**: `version_groups` → `version_groups`

**Implementación actual:**
- ✅ `pokedexes_json`: Se guarda en CSV
- ✅ `processed_starters_json`: Se procesa y guarda como JSON array de nombres
- ✅ `version_groups_json`: Se guarda en CSV
- ✅ `main_generation_id`: Se guarda como FK a `generations`

---

### 2. Pokedex (`pokedex`)

**Datos disponibles en JSON:**
- `processed_color`: Color de la pokedex (generado o procesado)
- `version_groups`: Relación de la pokedex con sus juegos (version groups)
- `pokemon_entries`: Lista de pokemons y su número de posición en la pokedex
  - Cada entrada tiene: `pokemon_species`, `entry_number`

**Uso:**
- **Color de pokedex**: Se usa para visualización
- **Relación pokedex-version_groups**: Para filtrar por juego
- **Lista de pokemons**: Se obtiene de `pokemon_entries`

**Implementación actual:**
- ✅ `color`: Se genera con `Get-PokedexColor` y se guarda
- ❌ `version_groups`: **NO SE ESTÁ GUARDANDO** - Falta en el CSV y en la tabla
- ✅ `pokemon_entries_json`: Se guarda en CSV
- ✅ `pokedex_entries`: Se genera tabla relacional con `pokedex_id`, `pokemon_id`, `entry_number`

**Problemas identificados:**
1. **`version_groups` de pokedex NO se guarda**: 
   - El CSV de `Pokedex` no incluye `version_groups_json`
   - La tabla `Pokedex` no tiene columna para `version_groups`
   - **Impacto**: No se puede filtrar pokedexes por versión/juego
2. **La relación `pokedex_entries` se genera desde `pokemon-species.pokedex_numbers`**:
   - Esto es correcto según las definiciones
   - Pero puede causar inconsistencias si los datos no coinciden con `pokedex.pokemon_entries`

---

### 3. Pokemon Species (`pokemon-species`)

**Datos disponibles en JSON:**
- `evolution-chain`: Cadena evolutiva completa
  - Contiene todas las especies de la cadena
  - Orden de evolución
  - Condiciones de evolución
- `pokedex_numbers`: Todas las pokedex en las que aparece esta especie y su posición
  - Cada entrada tiene: `pokedex`, `entry_number`
  - **IMPORTANTE**: De aquí se sacan las relaciones para `pokedex_entries`
- `varieties`: Todas las variantes de esta especie
  - Cada variante tiene: `pokemon`, `is_default`
  - **Lógica de asignación a pokedexes**:
    - Si `is_default = true`: Se asigna a pokedexes de regiones que NO tengan variante regional
    - Si el nombre contiene nombre de región (ej: "slowpoke-galar"):
      - La variante regional se asigna SOLO a pokedexes de esa región
      - El default NO se asigna a pokedexes de esa región

**Uso:**
- **Cadena evolutiva**: Se muestra en lista horizontal en detalle de pokemon
- **Relaciones pokedex**: Se genera `pokedex_entries` desde `pokedex_numbers`
- **Variantes**: Se muestran en lista horizontal de "variantes" en detalle de pokemon

**Implementación actual:**
- ✅ `evolution_chain_id`: Se guarda como FK a `evolution_chains`
- ✅ `pokedex_numbers`: Se usa en `Generate-PokedexEntriesCsv` para generar relaciones
- ✅ `varieties`: Se procesa en `Generate-PokedexEntriesCsv`
- ⚠️ **Problema**: La lógica de asignación puede no estar funcionando correctamente

**Lógica de asignación esperada:**
```
Para cada especie:
  1. Identificar pokemon default (is_default = true)
  2. Identificar variantes regionales (nombre contiene región)
  3. Para cada pokedex_number:
     a. Si la pokedex es de una región Y hay variante para esa región:
        → Asignar variante (NO default)
     b. Si la pokedex es de una región pero NO hay variante:
        → Asignar default
     c. Si la pokedex NO es de ninguna región (nacional):
        → Asignar default
     d. Si hay variante para una región, el default NO debe ir a pokedexes de esa región
```

---

### 4. Pokemon (`pokemon`)

**Datos disponibles en JSON:**
- `abilities`: Lista de habilidades de este pokemon (NO confundir con movimientos)
  - Cada habilidad tiene: `ability`, `is_hidden`, `slot`
- `moves`: Lista de ataques que puede usar este pokemon
  - Cada movimiento tiene: `move`, `version_group_details` (con `level_learned_at`, `move_learn_method`)
  - **IMPORTANTE**: Se muestran en acordeón al final de la pantalla de detalle
- `sprites`: Imágenes del pokemon
  - `other.dream-world.front_default`: SVG (prioridad máxima para normal)
  - `other.official-artwork.front_default`: PNG alta resolución
  - `other.home.front_default`: PNG fallback
  - `other.official-artwork.front_shiny`: PNG shiny alta resolución
  - `other.home.front_shiny`: PNG shiny fallback
  - `versions`: Sprites por generación/versión
    - Estructura: `versions.generation-{i}.{version-group}.front_transparent`
    - **IMPORTANTE**: Si se configura generación/versión, usar estos sprites
    - Si no hay datos para generación/versión, usar método default

**Uso:**
- **Habilidades**: Se muestran en detalle de pokemon
- **Movimientos**: Se muestran en acordeón con filtros por generación/versión
- **Sprites**: Se usan para visualización, con prioridad según configuración

**Implementación actual:**
- ✅ `abilities_json`: Se guarda en CSV
- ✅ `pokemon_abilities`: Tabla relacional con `pokemon_id`, `ability_id`, `is_hidden`, `slot`
- ✅ `moves_json`: Se guarda en CSV
- ✅ `pokemon_moves`: Tabla relacional con `pokemon_id`, `move_id`, `version_group_id`, `learn_method`, `level`
- ✅ `sprites_json`: Se guarda en CSV
- ✅ Sprites default: Se procesan y copian con nombres aplanados
- ✅ Sprites por versión: Se descargan y copian con formato `pokemon_{id}_{generation}_{version}_{filename}.{ext}`
- ⚠️ **Problema**: `PokemonImageHelper` puede no estar buscando correctamente los sprites por versión

---

## Verificación de Implementación

### ✅ Implementado Correctamente

1. **Regiones:**
   - ✅ `processed_starters_json`: Se genera y guarda correctamente
   - ✅ `version_groups_json`: Se guarda
   - ✅ `main_generation_id`: Se guarda como FK

2. **Pokedex:**
   - ✅ `color`: Se genera y guarda
   - ✅ `pokemon_entries_json`: Se guarda
   - ✅ `pokedex_entries`: Tabla relacional generada

3. **Pokemon Species:**
   - ✅ `evolution_chain_id`: Se guarda como FK
   - ✅ `pokedex_numbers`: Se procesa para generar relaciones
   - ✅ `varieties`: Se procesa para identificar variantes

4. **Pokemon:**
   - ✅ `abilities`: Se guarda en JSON y tabla relacional
   - ✅ `moves`: Se guarda en JSON y tabla relacional
   - ✅ `sprites`: Se procesan y copian

### ❌ Problemas Críticos Identificados

1. **`version_groups` de Pokedex NO se guarda:**
   - **Problema**: El CSV de `Pokedex` no incluye `version_groups_json`
   - **Problema**: La tabla `Pokedex` no tiene columna para `version_groups`
   - **Impacto**: No se puede filtrar pokedexes por versión/juego
   - **Solución necesaria**: 
     - Añadir `version_groups_json` al CSV de `Pokedex`
     - Añadir columna `versionGroupsJson` a la tabla `Pokedex`
     - Actualizar `BackupProcessor._insertPokedex` para insertar este campo

2. **Relaciones PokedexEntries:**
   - **Problema**: Las relaciones no se están generando o insertando correctamente
   - **Síntoma**: No se muestran pokemons en las regiones
   - **Causa posible**: 
     - Los pokemons no se están generando antes de las relaciones
     - Los IDs no coinciden
     - La lógica de asignación no está funcionando correctamente
   - **Solución aplicada**: 
     - Validación de que pokemons existen antes de usar `Get-DbId`
     - Logging adicional para diagnosticar
     - Verificación de que variantes existen

2. **Lógica de Asignación de Variantes:**
   - **Problema**: La lógica puede no estar asignando correctamente variantes regionales
   - **Verificación necesaria**: 
     - Revisar que variantes regionales se asignan solo a su región
     - Revisar que defaults no se asignan a regiones con variante

3. **Sprites por Versión:**
   - **Problema**: `PokemonImageHelper` puede no estar buscando correctamente
   - **Verificación necesaria**: 
     - Revisar que se buscan en la raíz de `poke_searcher_data`
     - Revisar que se usan nombres aplanados correctos

4. **Pokemons Iniciales:**
   - **Problema**: Pueden no estar mostrándose
   - **Verificación necesaria**: 
     - Revisar que `processed_starters_json` se está generando
     - Revisar que se está insertando correctamente
     - Revisar que `getStarterPokemon` está funcionando

---

## Checklist de Verificación

### Script PowerShell (`descargar_pokeapi.ps1`)

- [x] `Generate-RegionsCsv`: Genera `processed_starters_json` correctamente
- [x] `Generate-PokedexCsv`: Genera `color` correctamente
- [x] `Generate-PokedexCsv`: **CORREGIDO** - Ahora genera `version_groups_json`
- [ ] `Generate-PokedexEntriesCsv`: 
  - [ ] Procesa `pokemon-species.pokedex_numbers` correctamente
  - [ ] Identifica pokemon default correctamente
  - [ ] Identifica variantes regionales correctamente
  - [ ] Asigna pokemons a pokedexes según las reglas
  - [ ] Genera relaciones válidas (pokedex_id, pokemon_id, entry_number)
- [ ] `Generate-PokemonCsv`: Genera rutas de sprites correctamente
- [ ] `Extract-MediaUrlsFromFiles`: Descarga sprites por versión correctamente
- [ ] `Copy-PokemonMediaFiles`: Copia sprites con nombres aplanados correctamente

### Modelo de Datos (Flutter/Drift)

- [x] `Regions`: Tiene `processedStartersJson`
- [x] `Pokedex`: Tiene `color`
- [x] `Pokedex`: **CORREGIDO** - Ahora tiene `versionGroupsJson`
- [ ] `PokedexEntries`: Tiene `pokedexId`, `pokemonId`, `entryNumber`
- [ ] `Pokemon`: Tiene rutas de sprites
- [ ] `PokemonSpecies`: Tiene `evolutionChainId`
- [ ] `PokemonAbilities`: Tabla relacional existe
- [ ] `PokemonMoves`: Tabla relacional existe

### Extracción y Volcado (BackupProcessor)

- [x] `_insertRegions`: Inserta `processedStartersJson` correctamente
- [x] `_insertPokedex`: Inserta `color` correctamente
- [x] `_insertPokedex`: **CORREGIDO** - Ahora inserta `versionGroupsJson`
- [ ] `_insertPokedexEntries`: Inserta relaciones correctamente
- [ ] `_insertPokemon`: Inserta rutas de sprites correctamente
- [ ] `_insertPokemonAbilities`: Inserta habilidades correctamente
- [ ] `_insertPokemonMoves`: Inserta movimientos correctamente

### Helpers y DAOs

- [ ] `PokedexDao.getStarterPokemon`: Lee `processedStartersJson` correctamente
- [ ] `PokedexDao.getUniquePokemonByRegion`: Usa `pokedex_entries` correctamente
- [ ] `PokemonImageHelper.getBestImagePath`: Busca sprites por versión correctamente
- [ ] `MediaPathHelper.assetPathToLocalPath`: Busca archivos con `_default_` correctamente

---

## Correcciones Aplicadas

### ✅ 1. Añadido `version_groups_json` a Pokedex

**Script PowerShell:**
- ✅ `Generate-PokedexCsv`: Ahora incluye `version_groups_json` en el header y en todas las filas

**Modelo de Datos:**
- ✅ `Pokedex`: Añadida columna `versionGroupsJson`

**BackupProcessor:**
- ✅ `_insertPokedex`: Ahora lee e inserta `versionGroupsJson` (opcional para compatibilidad con CSVs antiguos)

### ✅ 2. Mejorada detección de variantes regionales

**Script PowerShell:**
- ✅ `Get-RegionNameFromPokemonName`: Ahora busca regiones al principio y al final del nombre
- ✅ Añadido mapeo para "kantonian" → "kanto"

### ✅ 3. Validaciones y logging adicional

**Script PowerShell:**
- ✅ Validación de que pokemons existen en `idMaps` antes de usar `Get-DbId`
- ✅ Validación de que variantes existen antes de asignarlas
- ✅ Logging de estadísticas de generación de `PokedexEntries`
- ✅ Advertencias cuando no se asignan pokemons

**BackupProcessor:**
- ✅ Verificación de que CSV no está vacío
- ✅ Resumen de entradas por pokedex
- ✅ Logging de pokemons iniciales por región

### ✅ 4. Corrección de búsqueda de archivos multimedia

**MediaPathHelper:**
- ✅ Búsqueda de variantes con `_default_` cuando no se encuentra sin `_default_`

## Próximos Pasos

1. **Ejecutar script de generación** y revisar logs:
   ```powershell
   .\scripts\descargar_pokeapi.ps1 -OnlyPhase3
   ```
   - Verificar que se generan relaciones (> 0)
   - Revisar warnings sobre pokemons no encontrados
   - Verificar que `version_groups_json` se genera

2. **Verificar CSV generado**:
   - `22_pokedex.csv`: Debe tener columna `version_groups_json`
   - `27_pokedex_entries.csv`: Debe tener filas (más allá del header)
   - Verificar que los IDs son válidos

3. **Regenerar modelo de datos** (si es necesario):
   ```bash
   cd poke_searcher
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Verificar inserción en BD** revisando logs de `BackupProcessor`:
   - Verificar que se insertan relaciones
   - Verificar que no hay errores críticos
   - Verificar que `versionGroupsJson` se inserta

5. **Verificar en BD** que las relaciones existen:
   - Query SQL para verificar `pokedex_entries`
   - Query SQL para verificar `versionGroupsJson` en `pokedex`

6. **Probar en app**:
   - Que se muestran pokemons por región
   - Que se muestran pokemons iniciales
   - Que se pueden filtrar pokedexes por versión (si se implementa)


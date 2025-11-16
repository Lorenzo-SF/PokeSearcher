# Informe de Lógica: Script PowerShell ↔ Aplicación Flutter

## Índice

1. [Arquitectura General](#arquitectura-general)
2. [Sistema de Relaciones entre Entidades](#sistema-de-relaciones-entre-entidades)
3. [Selección y Procesamiento de Archivos Multimedia](#selección-y-procesamiento-de-archivos-multimedia)
4. [Procesamiento de Datos y Generación de CSV](#procesamiento-de-datos-y-generación-de-csv)
5. [Sincronización Script ↔ App](#sincronización-script--app)
6. [Flujo Completo de Datos](#flujo-completo-de-datos)

---

## 1. Arquitectura General

### 1.1. Proceso de 3 Fases

El script `descargar_pokeapi.ps1` opera en 3 fases:

```
FASE 1: Descarga de JSONs
  └─> Descarga recursiva de todos los JSONs de PokeAPI
  └─> Guarda en estructura: {BaseDir}/{endpoint}/{id}/data.json

FASE 2: Descarga de Multimedia
  └─> Extrae URLs de archivos multimedia desde JSONs
  └─> Descarga con nombres normalizados
  └─> Guarda en: {BaseDir}/{endpoint}/{id}/{archivo}

FASE 3: Procesamiento y Generación de Backup
  └─> Procesa JSONs y genera CSV para base de datos
  └─> Copia multimedia con nombres aplanados
  └─> Crea ZIPs separados (database + media por tipo)
```

### 1.2. Sistema de IDs

**Mapeo API ID → DB ID:**
- El script usa `Get-DbId($table, $apiId)` para crear IDs autoincrementales
- Mantiene diccionarios `$script:idMaps` y contadores `$script:idCounters`
- Garantiza consistencia: mismo API ID → mismo DB ID

**Ejemplo:**
```powershell
# Pokemon API ID 1 (Bulbasaur)
$dbId = Get-DbId "pokemon" 1  # Retorna: 1 (primer pokemon)
# Pokemon API ID 2 (Ivysaur)
$dbId = Get-DbId "pokemon" 2  # Retorna: 2 (segundo pokemon)
```

---

## 2. Sistema de Relaciones entre Entidades

### 2.1. Jerarquía de Entidades

```
Region (Región)
  ├─> Pokedex (Pokedex regional)
  │     └─> PokedexEntries (Relación: pokedex_id → pokemon_id)
  │           └─> Pokemon (Instancia específica)
  │                 └─> PokemonSpecies (Especie)
  │                       └─> EvolutionChain (Cadena evolutiva)
  │
  ├─> VersionGroups (Grupos de versiones/juegos)
  │     └─> Generation (Generación)
  │
  └─> processed_starters_json (Pokemons iniciales)
```

### 2.2. Relación Pokedex ↔ Pokemon

**Problema:** Una especie puede tener múltiples pokemons (default + variantes regionales).

**Solución:** Asignar el pokemon correcto según la región de la pokedex.

#### 2.2.1. Lógica de Asignación (Generate-PokedexEntriesCsv)

**Paso 1: Identificar Variantes**

```powershell
# Para cada especie, analizar varieties:
foreach ($variety in $data.varieties) {
    if ($variety.is_default) {
        $defaultPokemon = $variety.pokemon
    } else {
        $regionName = Get-RegionNameFromPokemonName($variety.pokemon.name)
        if ($regionName) {
            $regionVariants[$regionName] = $variety.pokemon
        }
    }
}
```

**Paso 2: Asignar Pokemon a Pokedex**

```powershell
# Para cada pokedex_number en la especie:
foreach ($pokedexNumber in $data.pokedex_numbers) {
    $pokedexName = $pokedexNumber.pokedex.name
    $pokedexRegionName = Get-RegionNameFromPokedexName($pokedexName)
    
    # REGLA 1: Si la pokedex es de una región Y hay variante para esa región
    if ($pokedexRegionName -and $regionVariants.ContainsKey($pokedexRegionName)) {
        $pokemonToAssign = $regionVariants[$pokedexRegionName]  # Usar variante
    }
    # REGLA 2: Si la pokedex es de una región pero NO hay variante
    elseif ($pokedexRegionName -and -not $regionVariants.ContainsKey($pokedexRegionName)) {
        $pokemonToAssign = $defaultPokemon  # Usar default
    }
    # REGLA 3: Si la pokedex NO es de ninguna región específica (nacional)
    else {
        $pokemonToAssign = $defaultPokemon  # Usar default
    }
    # REGLA 4: Si hay variante para una región, el default NO va a pokedexes de esa región
    # (Implementado en la condición anterior)
}
```

**Ejemplo Práctico: Slowpoke**

```
Especie: Slowpoke (API ID 79)
  ├─> Default: slowpoke (API ID 79)
  └─> Variante: slowpoke-galar (API ID 10160)

Pokedexes:
  ├─> kanto (región: kanto)
  │     └─> Asigna: slowpoke (default) ✅
  ├─> galar (región: galar)
  │     └─> Asigna: slowpoke-galar (variante) ✅
  └─> national (sin región)
        └─> Asigna: slowpoke (default) ✅
```

#### 2.2.2. Detección de Variantes Regionales

**Función: `Get-RegionNameFromPokemonName`**

```powershell
# Busca regiones al principio o al final del nombre:
"slowpoke-galar" → "galar" ✅
"galarian-slowpoke" → "galar" ✅
"kantonian-meowth" → "kanto" ✅ (mapeo especial)
```

**Regiones detectadas:**
- `alola`, `galar`, `paldea`, `hisui`, `kantonian` → `kanto`, `johto`, `hoenn`, `sinnoh`, `unova`, `kalos`

#### 2.2.3. Detección de Región de Pokedex

**Función: `Get-RegionNameFromPokedexName`**

```powershell
# Mapa directo:
"kanto" → "kanto"
"original-johto" → "johto"
"isle-of-armor" → "galar"  # DLC de Galar
"blueberry" → "paldea"     # DLC de Paldea
```

### 2.3. Relación Region ↔ Pokemon Iniciales

**Proceso:**

1. **Script identifica iniciales:**
   ```powershell
   $RegionStarters = @{
       'kanto' = @('bulbasaur', 'charmander', 'squirtle')
       'johto' = @('chikorita', 'cyndaquil', 'totodile')
       # ...
   }
   
   # Añade a region.data.json:
   $regionData.processed_starters = $RegionStarters[$regionName]
   ```

2. **Script genera CSV:**
   ```csv
   id;api_id;name;...;processed_starters_json
   1;1;kanto;...;"[""bulbasaur"",""charmander"",""squirtle""]"
   ```

3. **App lee desde BD:**
   ```dart
   // PokedexDao.getStarterPokemon(regionId)
   final startersData = jsonDecode(region.processedStartersJson!) as List;
   // Busca especies por nombre: "bulbasaur", "charmander", "squirtle"
   ```

### 2.4. Relación Pokemon ↔ Species

**Estructura:**
- `Pokemon` tiene `species_id` (FK a `PokemonSpecies`)
- `PokemonSpecies` tiene `varieties_json` (lista de pokemons de la especie)
- Un `PokemonSpecies` puede tener múltiples `Pokemon` (default + variantes)

**Generación:**
```powershell
# Generate-PokemonCsv
$speciesApiId = Get-ApiIdFromUrl $data.species.url
$speciesId = Get-DbId "pokemonSpecies" $speciesApiId
# Guarda: pokemon.species_id = $speciesId
```

### 2.5. Relación Evolution Chain

**Estructura:**
- `PokemonSpecies` tiene `evolution_chain_id` (FK a `EvolutionChains`)
- `EvolutionChains` tiene `chain_json` (estructura completa de la cadena)

**Ejemplo de chain_json:**
```json
{
  "species": {"name": "bulbasaur", "url": "..."},
  "evolves_to": [{
    "species": {"name": "ivysaur", "url": "..."},
    "evolution_details": [...],
    "evolves_to": [{
      "species": {"name": "venusaur", "url": "..."},
      "evolves_to": []
    }]
  }]
}
```

---

## 3. Selección y Procesamiento de Archivos Multimedia

### 3.1. Estrategia de Priorización

#### 3.1.1. Imágenes de Pokemon (Default)

**Prioridad (de mayor a menor):**

1. **SVG desde dream-world** (vectorial, mejor calidad)
   - `sprites.other.dream_world.front_default` (SVG)
   - Nombre: `pokemon_{id}_default_sprite_front_default.svg`

2. **PNG desde official-artwork** (alta resolución)
   - `sprites.other.'official-artwork'.front_default` (PNG)
   - Nombre: `pokemon_{id}_default_sprite_front_default.png`

3. **PNG desde home** (fallback)
   - `sprites.other.home.front_default` (PNG)
   - Nombre: `pokemon_{id}_default_sprite_front_default.png`

**Código:**
```powershell
# 1. Intentar SVG desde dream-world
if ($sprites.other.dream_world.front_default -and $url.EndsWith('.svg')) {
    $normalUrl = $dreamWorldUrl
    $normalExt = "svg"
}
# 2. Si no hay SVG, usar PNG de official-artwork
elseif ($sprites.other.'official-artwork'.front_default) {
    $normalUrl = $officialDefault
    $normalExt = "png"
}
# 3. Si aún no hay, usar PNG de home
elseif ($sprites.other.home.front_default) {
    $normalUrl = $homeDefault
    $normalExt = "png"
}
```

#### 3.1.2. Imágenes Shiny

**Prioridad:**
1. SVG shiny (poco probable que exista)
2. PNG shiny desde official-artwork
3. PNG shiny desde home

#### 3.1.3. Imágenes por Generación/Version

**Estructura en JSON:**
```json
{
  "sprites": {
    "versions": {
      "generation-i": {
        "red-blue": {
          "front_transparent": "url...",
          "front_shiny_transparent": "url...",
          "front_gray": "url..."
        }
      }
    }
  }
}
```

**Nombres generados:**
```
pokemon_{id}_{generation}_{version}_front_transparent.{ext}
pokemon_{id}_{generation}_{version}_front_shiny_transparent.{ext}
pokemon_{id}_{generation}_{version}_front_gray.{ext}
```

**Ejemplo:**
```
pokemon_1_generation_i_red_blue_front_transparent.png
pokemon_1_generation_i_yellow_front_transparent.png
```

#### 3.1.4. Archivos de Audio (Cries)

**Prioridad:**
1. `cries.latest` (OGG) - versión moderna
2. `cries.legacy` (OGG) - versión clásica (fallback)

**Nombres:**
```
pokemon_{id}_default_cry_latest.ogg
pokemon_{id}_default_cry_legacy.ogg
```

### 3.2. Convención de Nombres

#### 3.2.1. Archivos Descargados (Estructura Original)

```
pokemon/
  └─> 1/
      ├─> data.json
      ├─> pokemon_1_default_sprite_front_default.svg
      ├─> pokemon_1_default_sprite_front_default.png
      ├─> pokemon_1_default_artwork_official.svg
      ├─> pokemon_1_default_artwork_official_shiny.png
      ├─> pokemon_1_default_cry_latest.ogg
      ├─> pokemon_1_generation_i_red_blue_front_transparent.png
      └─> pokemon_1_generation_i_yellow_front_transparent.png
```

#### 3.2.2. Archivos Copiados (Estructura Aplanada para Flutter)

```
media/pokemon/
  ├─> media_pokemon_1_default_sprite_front_default.svg
  ├─> media_pokemon_1_default_artwork_official.svg
  ├─> media_pokemon_1_generation_i_red_blue_front_transparent.png
  └─> ...
```

**Razón:** Flutter no puede crear directorios anidados al extraer ZIPs, así que todos los archivos se extraen en la raíz con nombres aplanados.

#### 3.2.3. Rutas en CSV

**Formato:**
```
assets/media_pokemon_{id}_default_{filename}.{ext}
```

**Ejemplo:**
```
assets/media_pokemon_1_default_artwork_official.svg
assets/media_pokemon_1_default_sprite_front_default.png
```

### 3.3. Procesamiento de Archivos

#### 3.3.1. FASE 2: Descarga

**Función: `Extract-MediaUrlsFromFiles`**

1. **Extrae URLs desde JSONs de pokemon:**
   - Analiza `sprites.other.dream_world`, `sprites.other.'official-artwork'`, `sprites.other.home`
   - Analiza `sprites.versions.{generation}.{version-group}`
   - Analiza `cries.latest` y `cries.legacy`

2. **Descarga con nombres normalizados:**
   - `pokemon_{id}_default_{filename}.{ext}`
   - `pokemon_{id}_{generation}_{version}_{filename}.{ext}`

3. **Crea copias para `artwork_official`:**
   - Copia `sprite_front_default` → `artwork_official`
   - Copia `sprite_front_shiny` → `artwork_official_shiny`

#### 3.3.2. FASE 3: Copia y Aplanado

**Función: `Copy-PokemonMediaFiles`**

1. **Busca archivos descargados:**
   ```powershell
   $defaultFiles = Get-ChildItem -Filter "pokemon_{id}_default_*"
   $versionFiles = Get-ChildItem -Filter "pokemon_{id}_*" -Exclude "*_default_*"
   ```

2. **Copia con prefijo `media_`:**
   ```powershell
   $flattenedName = "media_" + $defaultFile.Name
   # pokemon_1_default_artwork_official.svg → media_pokemon_1_default_artwork_official.svg
   ```

3. **Genera rutas para CSV:**
   ```powershell
   $mediaPaths['artworkOfficialPath'] = "assets/media_" + $defaultFile.Name
   # → "assets/media_pokemon_1_default_artwork_official.svg"
   ```

### 3.4. Búsqueda en la App

#### 3.4.1. Con Generación/Version Configurada

**Función: `PokemonImageHelper.getBestImagePath`**

```dart
// 1. Normalizar nombres
final genName = generation.name.replaceAll('-', '_');  // "generation-i" → "generation_i"
final vgName = versionGroup.name.replaceAll('-', '_');  // "red-blue" → "red_blue"

// 2. Construir nombre aplanado
final flattenedName = 'media_pokemon_${pokemon.apiId}_${genName}_${vgName}_front_transparent.png';

// 3. Buscar en raíz de poke_searcher_data
final file = File(path.join(dataDir.path, flattenedName));
if (await file.exists()) {
    return 'media/pokemon/${pokemon.apiId}/$genName/$vgName/front_transparent.png';
}
```

#### 3.4.2. Sin Generación/Version (Default)

**Prioridad:**
1. `artworkOfficialPath` (SVG) - desde dream-world
2. `spriteFrontDefaultPath` (SVG) - fallback
3. `artworkOfficialPath` (PNG) - official-artwork
4. `spriteFrontDefaultPath` (PNG) - home

**Función: `MediaPathHelper.assetPathToLocalPath`**

```dart
// 1. Aplanar ruta: "assets/media/pokemon/1/artwork_official.svg"
//    → "media_pokemon_1_artwork_official.svg"
final flattenedName = _flattenPath(assetPath);

// 2. Buscar en raíz
final file = File(path.join(dataDir.path, flattenedName));

// 3. Si no existe, buscar variante con _default_
if (!exists && fileName.contains('_artwork_official')) {
    final alternativeName = fileName.replaceFirst(
        '_artwork_official', 
        '_default_artwork_official'
    );
    // Buscar: media_pokemon_1_default_artwork_official.svg
}
```

---

## 4. Procesamiento de Datos y Generación de CSV

### 4.1. Orden de Generación

**Orden crítico (dependencias):**

```
01. Languages
02. Generations
03. Regions
04. Types
05. TypeDamageRelations
06. Stats
07. VersionGroups
08. MoveDamageClasses
09. Abilities
10. Moves
11. ItemPockets
12. ItemCategories
13. Items
14. EggGroups
15. GrowthRates
16. Natures
17. PokemonColors
18. PokemonShapes
19. PokemonHabitats
20. EvolutionChains
21. PokemonSpecies  ← Necesario para Pokemon
22. Pokedex
23. Pokemon  ← Necesario para PokedexEntries
24. PokemonTypes
25. PokemonAbilities
26. PokemonMoves
27. PokedexEntries  ← Necesita Pokemon y Pokedex
28. PokemonVariants
29. LocalizedNames
```

### 4.2. Procesamiento de Colores

#### 4.2.1. Colores de Tipos

**Función: `Get-TypeColor`**

```powershell
$TypeColors = @{
    'normal' = '#A8A77A'
    'fire' = '#EE8130'
    'water' = '#6390F0'
    # ...
}

# Se añade a type.data.json como processed_color
$typeData.processed_color = Get-TypeColor($typeName)
```

**CSV:**
```csv
id;api_id;name;...;color
1;1;normal;...;#A8A77A
```

#### 4.2.2. Colores de Pokedex

**Función: `Get-PokedexColor`**

```powershell
$PastelColors = @('#FFB3BA', '#FFDFBA', '#FFFFBA', ...)

# Asigna color pastel según índice
$color = Get-PokedexColor($pokedexIndex)
```

**CSV:**
```csv
id;api_id;name;...;color
1;1;national;...;#FFB3BA
2;2;kanto;...;#FFDFBA
```

### 4.3. Procesamiento de JSON Completo

**Estrategia:** Guardar JSON completo para campos complejos.

**Ejemplos:**
- `Pokemon.abilities_json` → `[{ability: {...}, is_hidden: false, slot: 1}, ...]`
- `Pokemon.moves_json` → `[{move: {...}, version_group_details: [...]}, ...]`
- `PokemonSpecies.varieties_json` → `[{is_default: true, pokemon: {...}}, ...]`
- `Pokedex.pokemon_entries_json` → `[{entry_number: 1, pokemon_species: {...}}, ...]`

**Ventajas:**
- Permite acceso a datos completos sin joins complejos
- Facilita consultas futuras
- Mantiene estructura original de PokeAPI

---

## 5. Sincronización Script ↔ App

### 5.1. Mapeo de Campos

#### 5.1.1. Pokedex

| Script (CSV) | App (Modelo) | Tipo |
|--------------|--------------|------|
| `id` | `id` | `IntColumn` (autoincrement) |
| `api_id` | `apiId` | `IntColumn` (unique) |
| `name` | `name` | `TextColumn` |
| `is_main_series` | `isMainSeries` | `BoolColumn` |
| `region_id` | `regionId` | `IntColumn` (nullable) |
| `color` | `color` | `TextColumn` (nullable) |
| `descriptions_json` | `descriptionsJson` | `TextColumn` (nullable) |
| `pokemon_entries_json` | `pokemonEntriesJson` | `TextColumn` (nullable) |
| `version_groups_json` | `versionGroupsJson` | `TextColumn` (nullable) |

#### 5.1.2. Pokemon

| Script (CSV) | App (Modelo) | Tipo |
|--------------|--------------|------|
| `id` | `id` | `IntColumn` (autoincrement) |
| `api_id` | `apiId` | `IntColumn` (unique) |
| `name` | `name` | `TextColumn` |
| `species_id` | `speciesId` | `IntColumn` (FK) |
| `artwork_official_path` | `artworkOfficialPath` | `TextColumn` (nullable) |
| `artwork_official_shiny_path` | `artworkOfficialShinyPath` | `TextColumn` (nullable) |
| `sprite_front_default_path` | `spriteFrontDefaultPath` | `TextColumn` (nullable) |
| `sprite_front_shiny_path` | `spriteFrontShinyPath` | `TextColumn` (nullable) |
| `cry_latest_path` | `cryLatestPath` | `TextColumn` (nullable) |
| `cry_legacy_path` | `cryLegacyPath` | `TextColumn` (nullable) |

#### 5.1.3. Regions

| Script (CSV) | App (Modelo) | Tipo |
|--------------|--------------|------|
| `id` | `id` | `IntColumn` (autoincrement) |
| `api_id` | `apiId` | `IntColumn` (unique) |
| `name` | `name` | `TextColumn` |
| `main_generation_id` | `mainGenerationId` | `IntColumn` (nullable) |
| `locations_json` | `locationsJson` | `TextColumn` (nullable) |
| `pokedexes_json` | `pokedexesJson` | `TextColumn` (nullable) |
| `version_groups_json` | `versionGroupsJson` | `TextColumn` (nullable) |
| `processed_starters_json` | `processedStartersJson` | `TextColumn` (nullable) |

#### 5.1.4. PokedexEntries

| Script (CSV) | App (Modelo) | Tipo |
|--------------|--------------|------|
| `pokedex_id` | `pokedexId` | `IntColumn` (FK) |
| `pokemon_id` | `pokemonId` | `IntColumn` (FK) |
| `entry_number` | `entryNumber` | `IntColumn` |

**IMPORTANTE:** Usa `pokemon_id` (no `pokemon_species_id`) para permitir variantes regionales.

### 5.2. Sincronización de Rutas de Archivos

#### 5.2.1. Flujo Completo

```
1. Script descarga:
   pokemon/1/pokemon_1_default_sprite_front_default.svg

2. Script copia (FASE 3):
   media/pokemon/media_pokemon_1_default_sprite_front_default.svg

3. Script genera CSV:
   assets/media_pokemon_1_default_sprite_front_default.svg

4. Script crea ZIP:
   media_pokemon_1_default_sprite_front_default.svg (en raíz del ZIP)

5. App extrae ZIP:
   poke_searcher_data/media_pokemon_1_default_sprite_front_default.svg

6. App busca:
   MediaPathHelper aplana: "assets/media_pokemon_1_default_sprite_front_default.svg"
   → "media_pokemon_1_default_sprite_front_default.svg"
   → Busca en: poke_searcher_data/media_pokemon_1_default_sprite_front_default.svg ✅
```

#### 5.2.2. Fallback para Archivos sin `_default_`

**Problema:** Algunas rutas en CSV pueden no tener `_default_`.

**Solución:** `MediaPathHelper` busca variante con `_default_`:

```dart
// Si busca: media_pokemon_1_artwork_official.svg
// Y no existe, busca: media_pokemon_1_default_artwork_official.svg
if (fileName.contains('_artwork_official')) {
    final alternativeName = fileName.replaceFirst(
        '_artwork_official', 
        '_default_artwork_official'
    );
}
```

### 5.3. Validaciones de Sincronización

#### 5.3.1. Script

```powershell
# Verificar que pokemon existe antes de usar
if (-not $script:idMaps["pokemon"].ContainsKey($pokemonApiId)) {
    Write-Warning "Pokemon API ID $pokemonApiId no encontrado"
    continue
}

# Verificar que se generaron relaciones
if ($rowCount -eq 0) {
    Write-Warning "[ERROR CRÍTICO] PokedexEntries está vacío"
}
```

#### 5.3.2. App (BackupProcessor)

```dart
// Verificar CSV no vacío
if (rows.length <= 1) {
    print('⚠️ ADVERTENCIA CRÍTICA: PokedexEntries CSV solo tiene header');
    return;
}

// Verificar inserción
if (companions.isEmpty) {
    print('⚠️ ADVERTENCIA CRÍTICA: No se pudo procesar ningún pokedex entry');
    return;
}
```

---

## 6. Flujo Completo de Datos

### 6.1. Flujo: Descarga → Procesamiento → App

```
┌─────────────────────────────────────────────────────────────┐
│ FASE 1: Descarga de JSONs                                    │
├─────────────────────────────────────────────────────────────┤
│ 1. Descarga recursiva desde PokeAPI                         │
│ 2. Guarda: pokemon/1/data.json                              │
│ 3. Extrae URLs y añade a cola                              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 2: Descarga de Multimedia                             │
├─────────────────────────────────────────────────────────────┤
│ 1. Extrae URLs desde JSONs                                 │
│ 2. Prioriza: SVG > PNG alta res > PNG baja res             │
│ 3. Descarga: pokemon/1/pokemon_1_default_sprite_*.svg      │
│ 4. Crea copias: pokemon/1/pokemon_1_default_artwork_*.svg  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 3: Procesamiento                                       │
├─────────────────────────────────────────────────────────────┤
│ 1. Procesa tipos → asigna colores                          │
│ 2. Procesa pokedexes → asigna colores pastel               │
│ 3. Procesa regiones → identifica iniciales                  │
│ 4. Genera CSV:                                             │
│    - PokemonSpecies (21)                                    │
│    - Pokemon (23)                                           │
│    - PokedexEntries (27) ← usa pokemon_id                  │
│ 5. Copia multimedia con nombres aplanados                   │
│ 6. Crea ZIPs: database.zip + media_*.zip                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ App: Descarga y Extracción                                 │
├─────────────────────────────────────────────────────────────┤
│ 1. Descarga ZIPs desde URL                                 │
│ 2. Verifica SHA256                                         │
│ 3. Extrae: database/*.csv → procesa                        │
│ 4. Extrae: media_*.zip → poke_searcher_data/ (raíz)        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ App: Inserción en BD                                        │
├─────────────────────────────────────────────────────────────┤
│ 1. BackupProcessor._insertPokedexEntries                    │
│    - Lee CSV: pokedex_id;pokemon_id;entry_number            │
│    - Inserta: PokedexEntries(pokedexId, pokemonId, ...)     │
│ 2. BackupProcessor._insertRegions                           │
│    - Lee: processed_starters_json                          │
│    - Inserta: Regions(processedStartersJson: "[...]")       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ App: Consulta y Visualización                               │
├─────────────────────────────────────────────────────────────┤
│ 1. PokedexDao.getUniquePokemonByRegion(regionId)           │
│    - Obtiene pokedexes de la región                         │
│    - Obtiene entries (pokedex_id → pokemon_id)             │
│    - Obtiene pokemons y sus especies                       │
│ 2. PokedexDao.getStarterPokemon(regionId)                  │
│    - Lee processedStartersJson                             │
│    - Busca especies por nombre                             │
│ 3. PokemonImageHelper.getBestImagePath(pokemon)            │
│    - Si hay gen/version: busca sprites.versions            │
│    - Si no: usa artworkOfficialPath                         │
│ 4. MediaPathHelper.assetPathToLocalPath(path)              │
│    - Aplana ruta: assets/media/... → media_...            │
│    - Busca en poke_searcher_data/                          │
└─────────────────────────────────────────────────────────────┘
```

### 6.2. Ejemplo Completo: Bulbasaur en Kanto

#### 6.2.1. Script Genera

**PokemonSpecies (ID 1):**
```csv
id;api_id;name;...;varieties_json
1;1;bulbasaur;...;"[{""is_default"":true,""pokemon"":{""name"":""bulbasaur"",""url"":""..."}}]"
```

**Pokemon (ID 1):**
```csv
id;api_id;name;species_id;...;artwork_official_path
1;1;bulbasaur;1;...;"assets/media_pokemon_1_default_artwork_official.svg"
```

**Pokedex (ID 2 - Kanto):**
```csv
id;api_id;name;region_id;...
2;2;kanto;1;...
```

**PokedexEntries:**
```csv
pokedex_id;pokemon_id;entry_number
2;1;1
```

**Region (ID 1 - Kanto):**
```csv
id;api_id;name;...;processed_starters_json
1;1;kanto;...;"[""bulbasaur"",""charmander"",""squirtle""]"
```

#### 6.2.2. App Consulta

**Obtener pokemons de Kanto:**
```dart
final pokemons = await pokedexDao.getUniquePokemonByRegion(1);
// Retorna: {speciesId: 1 → {species: Bulbasaur, pokedexNumbers: [...]}}
```

**Obtener iniciales de Kanto:**
```dart
final starters = await pokedexDao.getStarterPokemon(1);
// Retorna: [Bulbasaur, Charmander, Squirtle]
```

**Obtener imagen de Bulbasaur:**
```dart
final imagePath = await PokemonImageHelper.getBestImagePath(
    bulbasaur,
    appConfig: appConfig,
    database: database,
);
// Si hay gen/version: busca media_pokemon_1_generation_i_red_blue_front_transparent.png
// Si no: retorna assets/media_pokemon_1_default_artwork_official.svg
```

**Convertir a ruta local:**
```dart
final localPath = await MediaPathHelper.assetPathToLocalPath(imagePath);
// "assets/media_pokemon_1_default_artwork_official.svg"
// → "media_pokemon_1_default_artwork_official.svg"
// → Busca: poke_searcher_data/media_pokemon_1_default_artwork_official.svg ✅
```

---

## 7. Casos Especiales

### 7.1. Pokedex Nacional

**Tratamiento especial:**
- API ID: `1`
- Nombre: `"national"`
- Región: `9999` (región especial "national")
- No tiene región física asociada

**Generación:**
```powershell
if ($apiId -eq 1) {
    $nationalRegionDbId = Get-DbId "regions" 9999
    $row = "$dbId;1;national;1;$nationalRegionDbId;..."
}
```

### 7.2. Variantes Especiales (Mega, GMAX)

**No se tratan como variantes regionales:**
- `venusaur-mega` → NO es variante regional
- `venusaur-gmax` → NO es variante regional
- `slowpoke-galar` → SÍ es variante regional

**Detección:**
```powershell
function Get-RegionNameFromPokemonName($pokemonName) {
    # Solo busca regiones conocidas
    # "venusaur-mega" → null (no es regional)
    # "slowpoke-galar" → "galar" (es regional)
}
```

### 7.3. Archivos Faltantes

**Estrategia de fallback:**
1. Buscar archivo exacto
2. Buscar variante con `_default_`
3. Buscar en subdirectorios (por compatibilidad)
4. Retornar `null` si no existe

**Logging:**
```dart
if (!exists) {
    print('[ERROR] Archivo de imagen no existe: $localPath');
    // Continuar sin lanzar excepción (UI muestra placeholder)
}
```

---

## 8. Resumen de Convenciones

### 8.1. Nombres de Archivos

| Tipo | Formato | Ejemplo |
|------|---------|---------|
| Default sprite | `pokemon_{id}_default_{filename}.{ext}` | `pokemon_1_default_sprite_front_default.svg` |
| Version sprite | `pokemon_{id}_{gen}_{vg}_{filename}.{ext}` | `pokemon_1_generation_i_red_blue_front_transparent.png` |
| Artwork | `pokemon_{id}_default_artwork_official.{ext}` | `pokemon_1_default_artwork_official.svg` |
| Cry | `pokemon_{id}_default_cry_{version}.ogg` | `pokemon_1_default_cry_latest.ogg` |
| Item | `item_{id}_default_{filename}.{ext}` | `item_1_default_sprite.png` |
| Type | `type_{id}_{gen}_{vg}_name_icon.{ext}` | `type_1_generation_iii_ruby_sapphire_name_icon.png` |

### 8.2. Rutas en CSV

| Tipo | Formato | Ejemplo |
|------|---------|---------|
| Default | `assets/media_pokemon_{id}_default_{filename}.{ext}` | `assets/media_pokemon_1_default_artwork_official.svg` |
| Version | `assets/media_pokemon_{id}_{gen}_{vg}_{filename}.{ext}` | (no se guarda en CSV, se busca dinámicamente) |

### 8.3. Rutas en App

| Tipo | Formato | Ejemplo |
|------|---------|---------|
| Asset path | `assets/media_pokemon_{id}_default_{filename}.{ext}` | (desde CSV) |
| Local path | `poke_searcher_data/media_pokemon_{id}_default_{filename}.{ext}` | (después de extraer) |

---

## 9. Diagrama de Relaciones

```
┌─────────────┐
│   Region    │
│  (id, name) │
└──────┬──────┘
       │ 1:N
       │
       ├─────────────────────────────────────┐
       │                                     │
       ▼                                     ▼
┌─────────────┐                    ┌─────────────┐
│   Pokedex   │                    │VersionGroup│
│(id, regionId)│                    │  (id, ...) │
└──────┬──────┘                    └─────────────┘
       │ 1:N
       │
       ▼
┌─────────────┐
│PokedexEntry │
│(pokedexId,  │
│ pokemonId,  │
│ entryNumber)│
└──────┬──────┘
       │ N:1
       │
       ▼
┌─────────────┐
│   Pokemon   │
│(id, speciesId,│
│ artworkPath)│
└──────┬──────┘
       │ N:1
       │
       ▼
┌─────────────┐
│PokemonSpecies│
│(id, name,   │
│ varieties)  │
└──────┬──────┘
       │ 1:1
       │
       ▼
┌─────────────┐
│EvolutionChain│
│(id, chain)  │
└─────────────┘
```

---

## 10. Conclusión

El sistema implementa una arquitectura consistente y sincronizada entre el script PowerShell y la aplicación Flutter:

1. **Relaciones:** Usa `pokemon_id` (no `species_id`) en `PokedexEntries` para permitir variantes regionales
2. **Multimedia:** Nombres aplanados con prefijo `media_` para compatibilidad con Flutter
3. **Priorización:** SVG > PNG alta res > PNG baja res, con fallbacks
4. **Sincronización:** Validaciones y logging en ambos lados para detectar problemas
5. **Extensibilidad:** JSON completo guardado para consultas futuras sin cambios de esquema

El flujo garantiza que los datos generados por el script sean directamente consumibles por la app sin transformaciones adicionales.


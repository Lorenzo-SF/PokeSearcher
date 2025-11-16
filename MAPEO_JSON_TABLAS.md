# Mapeo de JSONs a Tablas de Base de Datos

Este documento detalla cómo se procesan y mapean los JSONs descargados de PokeAPI a las tablas de la base de datos, incluyendo relaciones, multimedia, índices y otros datos de interés.

## Índice

1. [Tablas Principales](#tablas-principales)
   - [Pokemon](#pokemon)
   - [PokemonSpecies](#pokemonspecies)
   - [Pokedex](#pokedex)
   - [PokedexEntries](#pokedexentries)
   - [Regions](#regions)
   - [Types](#types)
   - [Items](#items)
   - [Moves](#moves)
   - [Abilities](#abilities)
2. [Tablas de Relación](#tablas-de-relación)
   - [PokemonTypes](#pokemontypes)
   - [PokemonAbilities](#pokemonabilities)
   - [PokemonMoves](#pokemonmoves)
   - [TypeDamageRelations](#typedamagerelations)
   - [PokemonVariants](#pokemonvariants)
3. [Tablas Auxiliares](#tablas-auxiliares)
   - [Generations](#generations)
   - [VersionGroups](#versiongroups)
   - [EvolutionChains](#evolutionchains)
   - [LocalizedNames](#localizednames)
4. [Procesamiento de Multimedia](#procesamiento-de-multimedia)

---

## Tablas Principales

### Pokemon

**Tabla:** `pokemon`  
**JSON Origen:** `pokemon/{id}/data.json`  
**Uso:** Almacena información de cada variante de Pokémon (incluyendo variantes regionales, formas, etc.)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API (usado para mapeo) |
| `name` | TEXT | `data.name` | Nombre del pokemon (ej: "bulbasaur", "slowpoke-galar") |
| `speciesId` | INTEGER (FK) | `data.species.url` → Extrae API ID → Mapea a `pokemon_species.id` | Relación con especie |
| `baseExperience` | INTEGER (nullable) | `data.base_experience` | Experiencia base |
| `height` | INTEGER (nullable) | `data.height` | Altura (decímetros) |
| `weight` | INTEGER (nullable) | `data.weight` | Peso (hectogramos) |
| `isDefault` | BOOLEAN | `data.is_default` → Convierte a 1/0 | Si es la variante por defecto |
| `order` | INTEGER (nullable) | `data.order` | Orden de visualización |
| `locationAreaEncounters` | INTEGER (nullable) | `data.location_area_encounters` | ID de área de encuentro |
| `abilitiesJson` | TEXT (nullable) | `data.abilities` → `ConvertTo-Json` | JSON completo de habilidades |
| `formsJson` | TEXT (nullable) | `data.forms` → `ConvertTo-Json` | JSON completo de formas |
| `gameIndicesJson` | TEXT (nullable) | `data.game_indices` → `ConvertTo-Json` | JSON completo de índices de juego |
| `heldItemsJson` | TEXT (nullable) | `data.held_items` → `ConvertTo-Json` | JSON completo de items sostenidos |
| `movesJson` | TEXT (nullable) | `data.moves` → `ConvertTo-Json` | JSON completo de movimientos |
| `spritesJson` | TEXT (nullable) | `data.sprites` → `ConvertTo-Json` | JSON completo de sprites |
| `statsJson` | TEXT (nullable) | `data.stats` → `ConvertTo-Json` | JSON completo de estadísticas |
| `typesJson` | TEXT (nullable) | `data.types` → `ConvertTo-Json` | JSON completo de tipos |
| `criesJson` | TEXT (nullable) | `data.cries` → `ConvertTo-Json` | JSON completo de gritos |
| `spriteFrontDefaultPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_sprite_front_default.{ext}` |
| `spriteFrontShinyPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_sprite_front_shiny.{ext}` |
| `spriteBackDefaultPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_sprite_back_default.{ext}` |
| `spriteBackShinyPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_sprite_back_shiny.{ext}` |
| `artworkOfficialPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_artwork_official.{ext}` |
| `artworkOfficialShinyPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_artwork_official_shiny.{ext}` |
| `cryLatestPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_cry_latest.ogg` |
| `cryLegacyPath` | TEXT (nullable) | Generado por `Copy-PokemonMediaFiles` | Ruta asset: `assets/media_pokemon_{id}_default_cry_legacy.ogg` |

#### Relaciones

- **FK → `pokemon_species`**: `speciesId` referencia `pokemon_species.id`
- **Tabla intermedia → `pokemon_types`**: Relación many-to-many con `types` (ver [PokemonTypes](#pokemontypes))
- **Tabla intermedia → `pokemon_abilities`**: Relación many-to-many con `abilities` (ver [PokemonAbilities](#pokemonabilities))
- **Tabla intermedia → `pokemon_moves`**: Relación many-to-many con `moves` (ver [PokemonMoves](#pokemonmoves))
- **Tabla intermedia → `pokedex_entries`**: Relación many-to-many con `pokedex` (ver [PokedexEntries](#pokedexentries))
- **Tabla intermedia → `pokemon_variants`**: Relación many-to-many consigo misma (ver [PokemonVariants](#pokemonvariants))

#### Multimedia

**Proceso en Script (`descargar_pokeapi.ps1`):**

1. **Descarga (FASE 2):**
   - Descarga sprites desde `data.sprites`:
     - `sprites.other.dream_world.front_default` (SVG, prioridad máxima)
     - `sprites.other.'official-artwork'.front_default` (PNG, fallback)
     - `sprites.other.home.front_default` (PNG, último fallback)
     - `sprites.other.'official-artwork'.front_shiny` (PNG shiny)
     - `sprites.other.home.front_shiny` (PNG shiny fallback)
     - `sprites.back_default` y `sprites.back_shiny`
   - Descarga sprites de versions desde `data.sprites.versions`:
     - Para cada generación (ej: `generation-i`) y version-group (ej: `red-blue`):
       - `front_default`, `front_shiny`, `front_transparent`, `front_shiny_transparent`, `front_gray`
       - `back_default`, `back_shiny`, `back_transparent`, `back_shiny_transparent`, `back_gray`
   - Descarga cries desde `data.cries`:
     - `cries.latest` (OGG, prioridad)
     - `cries.legacy` (OGG, fallback)

2. **Nombres de Archivos (FASE 2):**
   - Archivos default: `pokemon_{apiId}_default_{tipo}.{ext}`
     - Ejemplo: `pokemon_1_default_sprite_front_default.svg`
   - Archivos de version: `pokemon_{apiId}_{generation}_{version}_{tipo}.{ext}`
     - Ejemplo: `pokemon_1_generation_i_red_blue_front_transparent.png`
   - Cries: `pokemon_{apiId}_default_cry_latest.ogg` o `pokemon_{apiId}_default_cry_legacy.ogg`

3. **Copia y Aplanado (FASE 3, `Copy-PokemonMediaFiles`):**
   - Busca TODOS los archivos multimedia en `pokemon/{apiId}/`
   - Copia cada archivo a `tempMediaDir/pokemon/` con prefijo `media_`
   - Nombre final: `media_pokemon_{apiId}_default_sprite_front_default.svg`
   - Mapea archivos conocidos a rutas CSV:
     - `_default_sprite_front_default` → `spriteFrontDefaultPath`
     - `_default_sprite_front_shiny` → `spriteFrontShinyPath`
     - `_default_sprite_back_default` → `spriteBackDefaultPath`
     - `_default_sprite_back_shiny` → `spriteBackShinyPath`
     - `_default_artwork_official` (sin shiny) → `artworkOfficialPath`
     - `_default_artwork_official_shiny` → `artworkOfficialShinyPath`
     - `_default_cry_latest` → `cryLatestPath`
     - `_default_cry_legacy` → `cryLegacyPath`

4. **Creación de Artwork Official (FASE 3, `Create-ArtworkOfficialFiles`):**
   - Si no existe `pokemon_{id}_default_artwork_official.{ext}`, copia desde `pokemon_{id}_default_sprite_front_default.{ext}`
   - Si no existe `pokemon_{id}_default_artwork_official_shiny.{ext}`, copia desde `pokemon_{id}_default_sprite_front_shiny.{ext}`

5. **ZIP (FASE 3):**
   - Todos los archivos de `tempMediaDir/pokemon/` se copian a un directorio temporal plano
   - Se crea ZIP: `poke_searcher_backup_media_pokemon.zip`
   - **IMPORTANTE:** Todos los archivos están en la raíz del ZIP (sin subdirectorios)

**Proceso en App (Flutter):**

1. **Extracción (`BackupProcessor._extractZip`):**
   - Extrae ZIP a `poke_searcher_data/`
   - **IMPORTANTE:** Flutter no preserva estructura de directorios, todos los archivos quedan en la raíz de `poke_searcher_data/`

2. **Búsqueda (`MediaPathHelper.assetPathToLocalPath`):**
   - Recibe ruta asset: `assets/media_pokemon_1_default_sprite_front_default.svg`
   - Aplana: `media_pokemon_1_default_sprite_front_default.svg`
   - Busca en `poke_searcher_data/`:
     - PRIORIDAD 1: Busca exactamente por nombre de archivo
     - PRIORIDAD 2: Para archivos de pokemon, busca variante con `_default_` si no encuentra
   - Retorna ruta absoluta: `/data/.../poke_searcher_data/media_pokemon_1_default_sprite_front_default.svg`

3. **Uso (`PokemonImageHelper.getBestImagePath`):**
   - Para imágenes default: busca `media_pokemon_{id}_default_artwork_official.{ext}` o `media_pokemon_{id}_default_sprite_front_default.{ext}`
   - Para imágenes de version: busca `media_pokemon_{id}_{gen}_{vg}_front_transparent.{ext}` directamente en la raíz de `poke_searcher_data/`
   - Usa `MediaPathHelper.assetPathToLocalPath` para convertir ruta asset a ruta local

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-PokemonCsv` (línea 2907-2967)
- La inserción se hace en `BackupProcessor._insertPokemon` (línea 2393-2518)
- El script valida que `speciesId` no sea null antes de generar la fila

---

### PokemonSpecies

**Tabla:** `pokemon_species`  
**JSON Origen:** `pokemon-species/{id}/data.json`  
**Uso:** Almacena información base de especies de Pokémon (sin variantes específicas)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre de la especie (ej: "bulbasaur") |
| `order` | INTEGER (nullable) | `data.order` | Orden de visualización |
| `genderRate` | INTEGER (nullable) | `data.gender_rate` | Tasa de género (-1 = sin género) |
| `captureRate` | INTEGER (nullable) | `data.capture_rate` | Tasa de captura |
| `baseHappiness` | INTEGER (nullable) | `data.base_happiness` | Felicidad base |
| `isBaby` | BOOLEAN | `data.is_baby` → 1/0 | Si es bebé |
| `isLegendary` | BOOLEAN | `data.is_legendary` → 1/0 | Si es legendario |
| `isMythical` | BOOLEAN | `data.is_mythical` → 1/0 | Si es mítico |
| `hatchCounter` | INTEGER (nullable) | `data.hatch_counter` | Contador de eclosión |
| `hasGenderDifferences` | BOOLEAN | `data.has_gender_differences` → 1/0 | Si tiene diferencias de género |
| `formsSwitchable` | INTEGER (nullable) | `data.forms_switchable` | Si las formas son intercambiables |
| `growthRateId` | INTEGER (nullable, FK) | `data.growth_rate.url` → Extrae API ID → Mapea a `growth_rates.id` | Relación con tasa de crecimiento |
| `colorId` | INTEGER (nullable, FK) | `data.color.url` → Extrae API ID → Mapea a `pokemon_colors.id` | Relación con color |
| `shapeId` | INTEGER (nullable, FK) | `data.shape.url` → Extrae API ID → Mapea a `pokemon_shapes.id` | Relación con forma |
| `habitatId` | INTEGER (nullable, FK) | `data.habitat.url` → Extrae API ID → Mapea a `pokemon_habitats.id` | Relación con hábitat |
| `generationId` | INTEGER (nullable, FK) | `data.generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación |
| `evolvesFromSpeciesId` | INTEGER (nullable, FK) | `data.evolves_from_species.url` → Extrae API ID → Mapea a `pokemon_species.id` | Relación con especie preevolutiva (self-reference) |
| `evolutionChainId` | INTEGER (nullable, FK) | `data.evolution_chain.url` → Extrae API ID → Mapea a `evolution_chains.id` | Relación con cadena evolutiva |
| `eggGroupsJson` | TEXT (nullable) | `data.egg_groups` → `ConvertTo-Json` | JSON completo de grupos de huevo |
| `flavorTextEntriesJson` | TEXT (nullable) | `data.flavor_text_entries` → `ConvertTo-Json` | JSON completo de textos de sabor |
| `formDescriptionsJson` | TEXT (nullable) | `data.form_descriptions` → `ConvertTo-Json` | JSON completo de descripciones de formas |
| `varietiesJson` | TEXT (nullable) | `data.varieties` → `ConvertTo-Json` | JSON completo de variedades (incluye default y variantes) |
| `generaJson` | TEXT (nullable) | `data.genera` → `ConvertTo-Json` | JSON completo de géneros (categorías) |

#### Relaciones

- **FK → `growth_rates`**: `growthRateId` referencia `growth_rates.id`
- **FK → `pokemon_colors`**: `colorId` referencia `pokemon_colors.id`
- **FK → `pokemon_shapes`**: `shapeId` referencia `pokemon_shapes.id`
- **FK → `pokemon_habitats`**: `habitatId` referencia `pokemon_habitats.id`
- **FK → `generations`**: `generationId` referencia `generations.id`
- **FK → `pokemon_species` (self)**: `evolvesFromSpeciesId` referencia `pokemon_species.id` (especie de la que evoluciona)
- **FK → `evolution_chains`**: `evolutionChainId` referencia `evolution_chains.id`
- **1:N → `pokemon`**: Una especie tiene múltiples pokemons (variantes)

#### Multimedia

**No tiene multimedia propia.** Las imágenes están en la tabla `pokemon`.

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-PokemonSpeciesCsv` (línea 2759-2831)
- La inserción se hace en `BackupProcessor._insertPokemonSpecies` (línea 2299-2352)
- El campo `varietiesJson` contiene la lista de todas las variantes (default + regionales), que se usa en `Generate-PokedexEntriesCsv` para asignar pokemons a pokedexes

---

### Pokedex

**Tabla:** `pokedex`  
**JSON Origen:** `pokedex/{id}/data.json`  
**Uso:** Almacena información de cada Pokedex (nacional, regional, etc.)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` o "national" (si apiId=1) | Nombre de la pokedex |
| `isMainSeries` | BOOLEAN | `data.is_main_series` → 1/0 | Si es de la serie principal |
| `regionId` | INTEGER (nullable, FK) | `data.region.url` → Extrae API ID → Mapea a `regions.id` (o 9999 si es nacional) | Relación con región |
| `color` | TEXT (nullable) | `Get-PokedexColor($pokedexIndex)` o `data.processed_color` | Color hexadecimal pastel para UI |
| `descriptionsJson` | TEXT (nullable) | `data.descriptions` → `ConvertTo-Json` | JSON completo de descripciones |
| `pokemonEntriesJson` | TEXT (nullable) | `data.pokemon_entries` → `ConvertTo-Json` | JSON completo de entradas originales |
| `versionGroupsJson` | TEXT (nullable) | `data.version_groups` → `ConvertTo-Json` | JSON completo de grupos de versión |

#### Relaciones

- **FK → `regions`**: `regionId` referencia `regions.id`
  - **Caso especial:** Pokedex nacional (apiId=1) se asigna a región nacional (apiId=9999)
- **Tabla intermedia → `pokedex_entries`**: Relación many-to-many con `pokemon` (ver [PokedexEntries](#pokedexentries))

#### Multimedia

**No tiene multimedia propia.**

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-PokedexCsv` (línea 2833-2905)
- La inserción se hace en `BackupProcessor._insertPokedex` (línea 2354-2391)
- La pokedex nacional (apiId=1) se procesa especialmente y se asigna a la región nacional (apiId=9999)
- El color se genera usando `Get-PokedexColor` que asigna colores pastel según el índice de la pokedex

---

### PokedexEntries

**Tabla:** `pokedex_entries`  
**JSON Origen:** `pokemon-species/{id}/data.json` (campo `pokedex_numbers`)  
**Uso:** Relación many-to-many entre Pokedex y Pokemon (específicos, no especies)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `pokedexId` | INTEGER (FK) | `pokedexNumber.pokedex.url` → Extrae API ID → Mapea a `pokedex.id` | Relación con pokedex |
| `pokemonId` | INTEGER (FK) | Lógica compleja (ver abajo) | Relación con pokemon específico |
| `entryNumber` | INTEGER | `pokedexNumber.entry_number` | Número de entrada en la pokedex |

#### Lógica de Asignación de Pokemon

**Función:** `Generate-PokedexEntriesCsv` (línea 3200-3421)

1. **Procesa cada especie** (`pokemon-species/{id}/data.json`):
   - Lee `data.pokedex_numbers` (array de entradas de pokedex)
   - Lee `data.varieties` (array de variantes: default + regionales)

2. **Identifica pokemons:**
   - **Default:** `variety.is_default = true` → `defaultPokemon`
   - **Variantes regionales:** `variety.is_default = false` + nombre contiene región (ej: "slowpoke-galar") → `regionVariants[regionName] = pokemonApiId`
   - **Otras variantes:** `variety.is_default = false` + nombre no contiene región → `otherVariants`

3. **Para cada entrada de pokedex (`pokedexNumber`):**
   - Obtiene `pokedexName` y `entryNumber`
   - Obtiene `pokedexRegionName` desde el nombre de la pokedex (ej: "kanto" → "kanto")
   - **Decide qué pokemon asignar:**
     - **Si la pokedex es de una región Y hay variante para esa región:** Usa la variante (NO el default)
     - **Si la pokedex es de una región pero NO hay variante:** Usa el default
     - **Si la pokedex NO es de ninguna región específica:** Usa el default
     - **IMPORTANTE:** Si hay variante para una región, el default NO debe ir a pokedexes de esa región

4. **Genera fila CSV:** `pokedexDbId;pokemonDbId;entryNumber`

#### Relaciones

- **FK → `pokedex`**: `pokedexId` referencia `pokedex.id`
- **FK → `pokemon`**: `pokemonId` referencia `pokemon.id` (NO `pokemon_species.id`)
- **UNIQUE:** `(pokedexId, pokemonId)` - Un pokemon solo puede aparecer una vez por pokedex

#### Multimedia

**No tiene multimedia propia.**

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE KEY:** `(pokedexId, pokemonId)`

#### Notas

- El CSV se genera en `Generate-PokedexEntriesCsv` (línea 3200-3421)
- La inserción se hace en `BackupProcessor._insertPokedexEntries` (línea 2606-2683)
- **CRÍTICO:** Esta tabla es la que permite mostrar pokemons en las regiones. Si está vacía, no se mostrarán pokemons.
- El script valida que el CSV no esté vacío y muestra advertencias críticas si no hay datos

---

### Regions

**Tabla:** `regions`  
**JSON Origen:** `region/{id}/data.json`  
**Uso:** Almacena información de regiones de Pokémon

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` o 9999 (nacional) | ID de la API |
| `name` | TEXT | `data.name` o "national" | Nombre de la región |
| `mainGenerationId` | INTEGER (nullable, FK) | `data.main_generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación principal |
| `locationsJson` | TEXT (nullable) | `data.locations` → `ConvertTo-Json` | JSON completo de ubicaciones |
| `pokedexesJson` | TEXT (nullable) | `data.pokedexes` → `ConvertTo-Json` | JSON completo de pokedexes |
| `versionGroupsJson` | TEXT (nullable) | `data.version_groups` → `ConvertTo-Json` | JSON completo de grupos de versión |
| `processedStartersJson` | TEXT (nullable) | `data.processed_starters` (añadido en FASE 3) o `$RegionStarters[$regionName]` | JSON array de nombres de pokemons iniciales |

#### Relaciones

- **FK → `generations`**: `mainGenerationId` referencia `generations.id`
- **1:N → `pokedex`**: Una región tiene múltiples pokedexes (a través de `pokedex.regionId`)

#### Procesamiento de Iniciales

**Función:** `Process-DataForBackup` (línea 4021-4047)

1. **Para cada región:**
   - Busca en `$RegionStarters` el nombre de la región (ej: "kanto")
   - Obtiene array de nombres: `@('bulbasaur', 'charmander', 'squirtle')`
   - Añade campo `processed_starters` al JSON de la región
   - Guarda JSON actualizado

2. **En CSV:**
   - Lee `data.processed_starters` (si existe)
   - Convierte a JSON: `["bulbasaur","charmander","squirtle"]`

3. **En App:**
   - `PokedexDao.getStarterPokemon` lee `processedStartersJson`
   - Parsea JSON a array de nombres
   - Busca `PokemonSpecy` por nombre
   - Retorna lista de especies iniciales

#### Multimedia

**No tiene multimedia propia.**

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-RegionsCsv` (línea 2081-2124)
- La inserción se hace en `BackupProcessor._insertRegions` (línea 1704-1746)
- Se añade región especial "national" (apiId=9999) manualmente para la pokedex nacional
- El script muestra logs de `processed_starters_json` para cada región

---

### Types

**Tabla:** `types`  
**JSON Origen:** `type/{id}/data.json`  
**Uso:** Almacena información de tipos de Pokémon

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre del tipo (ej: "normal", "fire") |
| `generationId` | INTEGER (nullable, FK) | `data.generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación |
| `moveDamageClassId` | INTEGER (nullable, FK) | `data.move_damage_class.url` → Extrae API ID → Mapea a `move_damage_classes.id` | Relación con clase de daño |
| `color` | TEXT (nullable) | `Get-TypeColor($data.name)` o `data.processed_color` | Color hexadecimal del tipo (ej: "#A8A77A" para normal) |
| `damageRelationsJson` | TEXT (nullable) | `data.damage_relations` → `ConvertTo-Json` | JSON completo de relaciones de daño |

#### Relaciones

- **FK → `generations`**: `generationId` referencia `generations.id`
- **FK → `move_damage_classes`**: `moveDamageClassId` referencia `move_damage_classes.id`
- **Tabla intermedia → `type_damage_relations`**: Relación many-to-many consigo misma (ver [TypeDamageRelations](#typedamagerelations))
- **Tabla intermedia → `pokemon_types`**: Relación many-to-many con `pokemon` (ver [PokemonTypes](#pokemontypes))

#### Multimedia

**Proceso en Script:**

1. **Descarga (FASE 2):**
   - Descarga sprites desde `data.sprites`:
     - Para cada generación (ej: `generation-iii`) y version-group (ej: `ruby-sapphire`):
       - `name_icon` (PNG o SVG)

2. **Nombres de Archivos (FASE 2):**
   - `type_{apiId}_{generation}_{version}_name_icon.{ext}`
   - Ejemplo: `type_1_generation_iii_ruby_sapphire_name_icon.png`

3. **Copia y Aplanado (FASE 3, `Copy-TypeMediaFiles`):**
   - Busca archivos en `type/{apiId}/`
   - Copia a `tempMediaDir/type/` con prefijo `media_`
   - Nombre final: `media_type_{apiId}_{generation}_{version}_name_icon.{ext}`

4. **ZIP (FASE 3):**
   - Todos los archivos de `tempMediaDir/type/` se copian a un directorio temporal plano
   - Se crea ZIP: `poke_searcher_backup_media_type.zip`
   - Todos los archivos están en la raíz del ZIP

**Proceso en App:**

1. **Extracción:** Igual que Pokemon
2. **Búsqueda (`TypeImageHelper.getBestImagePath`):**
   - Construye nombre: `media_type_{apiId}_{gen}_{vg}_name_icon.{ext}`
   - Busca directamente en la raíz de `poke_searcher_data/`
   - Usa `MediaPathHelper.assetPathToLocalPath` para convertir

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-TypesCsv` (línea 2126-2172)
- La inserción se hace en `BackupProcessor._insertTypes` (línea 1748-1777)
- El color se genera usando `Get-TypeColor` que busca en `$TypeColors` (hashmap hardcodeado)

---

### Items

**Tabla:** `items`  
**JSON Origen:** `item/{id}/data.json`  
**Uso:** Almacena información de objetos/items

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre del item |
| `cost` | INTEGER (nullable) | `data.cost` | Coste del item |
| `flingPower` | INTEGER (nullable) | `data.fling_power` | Poder de lanzamiento |
| `categoryId` | INTEGER (nullable, FK) | `data.category.url` → Extrae API ID → Mapea a `item_categories.id` | Relación con categoría |
| `flingEffectId` | INTEGER (nullable) | `data.fling_effect.url` → Extrae API ID (no se mapea, solo se guarda) | ID de efecto de lanzamiento (no hay tabla) |
| `fullDataJson` | TEXT (nullable) | `data` (objeto completo) → `ConvertTo-Json` | JSON completo del item |

#### Relaciones

- **FK → `item_categories`**: `categoryId` referencia `item_categories.id`

#### Multimedia

**Proceso en Script:**

1. **Descarga (FASE 2):**
   - Descarga sprite desde `data.sprites.default`

2. **Nombres de Archivos (FASE 2):**
   - `item_{apiId}_default_{filename}.{ext}`
   - Ejemplo: `item_1_default_sprite.png`

3. **Copia y Aplanado (FASE 3, `Copy-ItemMediaFiles`):**
   - Busca archivos en `item/{apiId}/`
   - Copia a `tempMediaDir/item/` con prefijo `media_`
   - Nombre final: `media_item_{apiId}_default_{filename}.{ext}`

4. **ZIP (FASE 3):**
   - Todos los archivos de `tempMediaDir/item/` se copian a un directorio temporal plano
   - Se crea ZIP: `poke_searcher_backup_media_item.zip`
   - Todos los archivos están en la raíz del ZIP

**Proceso en App:** Similar a Pokemon y Types

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-ItemsCsv` (línea 2497-2538)
- La inserción se hace en `BackupProcessor._insertItems` (línea 2013-2044)

---

### Moves

**Tabla:** `moves`  
**JSON Origen:** `move/{id}/data.json`  
**Uso:** Almacena información de movimientos

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre del movimiento |
| `accuracy` | INTEGER (nullable) | `data.accuracy` | Precisión |
| `effectChance` | INTEGER (nullable) | `data.effect_chance` | Probabilidad de efecto |
| `pp` | INTEGER (nullable) | `data.pp` | Puntos de poder |
| `priority` | INTEGER (nullable) | `data.priority` | Prioridad |
| `power` | INTEGER (nullable) | `data.power` | Poder |
| `typeId` | INTEGER (nullable, FK) | `data.type.url` → Extrae API ID → Mapea a `types.id` | Relación con tipo |
| `damageClassId` | INTEGER (nullable, FK) | `data.damage_class.url` → Extrae API ID → Mapea a `move_damage_classes.id` | Relación con clase de daño |
| `generationId` | INTEGER (nullable, FK) | `data.generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación |
| `fullDataJson` | TEXT (nullable) | `data` (objeto completo) → `ConvertTo-Json` | JSON completo del movimiento |

#### Relaciones

- **FK → `types`**: `typeId` referencia `types.id`
- **FK → `move_damage_classes`**: `damageClassId` referencia `move_damage_classes.id`
- **FK → `generations`**: `generationId` referencia `generations.id`
- **Tabla intermedia → `pokemon_moves`**: Relación many-to-many con `pokemon` (ver [PokemonMoves](#pokemonmoves))

#### Multimedia

**No tiene multimedia propia.**

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-MovesCsv` (línea 2392-2435)
- La inserción se hace en `BackupProcessor._insertMoves` (línea 1922-1957)

---

### Abilities

**Tabla:** `abilities`  
**JSON Origen:** `ability/{id}/data.json`  
**Uso:** Almacena información de habilidades

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre de la habilidad |
| `isMainSeries` | BOOLEAN | `data.is_main_series` → 1/0 | Si es de la serie principal |
| `generationId` | INTEGER (nullable, FK) | `data.generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación |
| `fullDataJson` | TEXT (nullable) | `data` (objeto completo) → `ConvertTo-Json` | JSON completo de la habilidad |

#### Relaciones

- **FK → `generations`**: `generationId` referencia `generations.id`
- **Tabla intermedia → `pokemon_abilities`**: Relación many-to-many con `pokemon` (ver [PokemonAbilities](#pokemonabilities))

#### Multimedia

**No tiene multimedia propia.**

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-AbilitiesCsv` (línea 2357-2390)
- La inserción se hace en `BackupProcessor._insertAbilities` (línea 1892-1921)

---

## Tablas de Relación

### PokemonTypes

**Tabla:** `pokemon_types`  
**JSON Origen:** `pokemon/{id}/data.json` (campo `types`)  
**Uso:** Relación many-to-many entre Pokemon y Types

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `pokemonId` | INTEGER (FK) | `data.id` → Mapea a `pokemon.id` | Relación con pokemon |
| `typeId` | INTEGER (FK) | `typeEntry.type.url` → Extrae API ID → Mapea a `types.id` | Relación con tipo |
| `slot` | INTEGER | `typeEntry.slot` | Slot del tipo (1 = primario, 2 = secundario) |

#### Relaciones

- **FK → `pokemon`**: `pokemonId` referencia `pokemon.id`
- **FK → `types`**: `typeId` referencia `types.id`
- **UNIQUE:** `(pokemonId, typeId, slot)` - Un pokemon no puede tener el mismo tipo en el mismo slot dos veces

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE KEY:** `(pokemonId, typeId, slot)`

#### Notas

- El CSV se genera en `Generate-PokemonTypesCsv` (línea 2969-3006)
- La inserción se hace en `BackupProcessor._insertPokemonTypes` (línea 2520-2546)
- Se genera una fila por cada tipo que tiene el pokemon (normalmente 1 o 2)

---

### PokemonAbilities

**Tabla:** `pokemon_abilities`  
**JSON Origen:** `pokemon/{id}/data.json` (campo `abilities`)  
**Uso:** Relación many-to-many entre Pokemon y Abilities

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `pokemonId` | INTEGER (FK) | `data.id` → Mapea a `pokemon.id` | Relación con pokemon |
| `abilityId` | INTEGER (FK) | `abilityEntry.ability.url` → Extrae API ID → Mapea a `abilities.id` | Relación con habilidad |
| `isHidden` | BOOLEAN | `abilityEntry.is_hidden` → 1/0 | Si es habilidad oculta |
| `slot` | INTEGER | `abilityEntry.slot` | Slot de la habilidad |

#### Relaciones

- **FK → `pokemon`**: `pokemonId` referencia `pokemon.id`
- **FK → `abilities`**: `abilityId` referencia `abilities.id`
- **UNIQUE:** `(pokemonId, abilityId)` - Un pokemon no puede tener la misma habilidad dos veces

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE KEY:** `(pokemonId, abilityId)`

#### Notas

- El CSV se genera en `Generate-PokemonAbilitiesCsv` (línea 3008-3046)
- La inserción se hace en `BackupProcessor._insertPokemonAbilities` (línea 2548-2575)

---

### PokemonMoves

**Tabla:** `pokemon_moves`  
**JSON Origen:** `pokemon/{id}/data.json` (campo `moves`)  
**Uso:** Relación many-to-many entre Pokemon y Moves, con información de versión y método de aprendizaje

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `pokemonId` | INTEGER (FK) | `data.id` → Mapea a `pokemon.id` | Relación con pokemon |
| `moveId` | INTEGER (FK) | `moveEntry.move.url` → Extrae API ID → Mapea a `moves.id` | Relación con movimiento |
| `versionGroupId` | INTEGER (nullable, FK) | `vgDetail.version_group.url` → Extrae API ID → Mapea a `version_groups.id` | Relación con grupo de versión |
| `learnMethod` | TEXT (nullable) | `vgDetail.move_learn_method.name` | Método de aprendizaje (ej: "level-up", "machine", "tutor", "egg") |
| `level` | INTEGER (nullable) | `vgDetail.level_learned_at` | Nivel en que se aprende (si es por nivel) |

#### Relaciones

- **FK → `pokemon`**: `pokemonId` referencia `pokemon.id`
- **FK → `moves`**: `moveId` referencia `moves.id`
- **FK → `version_groups`**: `versionGroupId` referencia `version_groups.id`

#### Lógica de Generación

**Función:** `Generate-PokemonMovesCsv` (línea 3048-3135)

1. **Para cada pokemon:**
   - Lee `data.moves` (array de movimientos)
   - Para cada movimiento:
     - Lee `moveEntry.version_group_details` (array de detalles por versión)
     - Para cada detalle:
       - Extrae `version_group`, `move_learn_method`, `level_learned_at`
       - Genera fila: `pokemonDbId;moveDbId;versionGroupDbId;learnMethod;level`

2. **Resultado:** Múltiples filas por pokemon (una por cada versión en que aprende el movimiento)

#### Índices

- **PRIMARY KEY:** `id`
- **No hay UNIQUE** - Un pokemon puede aprender el mismo movimiento en diferentes versiones

#### Notas

- El CSV se genera en `Generate-PokemonMovesCsv` (línea 3048-3135)
- La inserción se hace en `BackupProcessor._insertPokemonMoves` (línea 2577-2604)
- Esta es una de las tablas más grandes (miles de filas)

---

### TypeDamageRelations

**Tabla:** `type_damage_relations`  
**JSON Origen:** `type/{id}/data.json` (campo `damage_relations`)  
**Uso:** Relación many-to-many entre Types (atacante y defensor) con tipo de relación

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `attackingTypeId` | INTEGER (FK) | `data.id` → Mapea a `types.id` | Tipo atacante |
| `defendingTypeId` | INTEGER (FK) | `target.url` o `attacker.url` → Extrae API ID → Mapea a `types.id` | Tipo defensor |
| `relationType` | TEXT | String literal según el campo del JSON | Tipo de relación: "double_damage_to", "half_damage_to", "no_damage_to", "double_damage_from", "half_damage_from", "no_damage_from" |

#### Relaciones

- **FK → `types` (atacante)**: `attackingTypeId` referencia `types.id`
- **FK → `types` (defensor)**: `defendingTypeId` referencia `types.id`

#### Lógica de Generación

**Función:** `Generate-TypeDamageRelationsCsv` (línea 2174-2260)

1. **Para cada tipo:**
   - Lee `data.damage_relations`
   - **Para `double_damage_to`:**
     - Genera fila: `typeDbId;targetDbId;double_damage_to`
   - **Para `half_damage_to`:**
     - Genera fila: `typeDbId;targetDbId;half_damage_to`
   - **Para `no_damage_to`:**
     - Genera fila: `typeDbId;targetDbId;no_damage_to`
   - **Para `double_damage_from`:**
     - Genera fila: `attackerDbId;typeDbId;double_damage_from` (invertido)
   - **Para `half_damage_from`:**
     - Genera fila: `attackerDbId;typeDbId;half_damage_from` (invertido)
   - **Para `no_damage_from`:**
     - Genera fila: `attackerDbId;typeDbId;no_damage_from` (invertido)

2. **Resultado:** Múltiples filas por tipo (una por cada relación)

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE KEY:** `(attackingTypeId, defendingTypeId, relationType)` - No puede haber la misma relación duplicada

#### Notas

- El CSV se genera en `Generate-TypeDamageRelationsCsv` (línea 2174-2260)
- La inserción se hace en `BackupProcessor._insertTypeDamageRelations` (línea 1779-1805)

---

### PokemonVariants

**Tabla:** `pokemon_variants`  
**JSON Origen:** `pokemon-species/{id}/data.json` (campo `varieties`)  
**Uso:** Relación many-to-many entre Pokemon (default y variantes)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `pokemonId` | INTEGER (PK, FK) | `defaultPokemon` (variety.is_default = true) → Mapea a `pokemon.id` | Pokemon default |
| `variantPokemonId` | INTEGER (PK, FK) | `variety.pokemon` (variety.is_default = false) → Mapea a `pokemon.id` | Pokemon variante |

#### Relaciones

- **FK → `pokemon` (default)**: `pokemonId` referencia `pokemon.id`
- **FK → `pokemon` (variante)**: `variantPokemonId` referencia `pokemon.id`
- **COMPOSITE PRIMARY KEY:** `(pokemonId, variantPokemonId)`

#### Lógica de Generación

**Función:** `Generate-PokemonVariantsCsv` (línea 3423-3483)

1. **Para cada especie:**
   - Lee `data.varieties`
   - Identifica `defaultPokemon` (is_default = true)
   - Identifica todas las variantes (is_default = false)
   - **Si hay default y hay variantes:**
     - Genera fila por cada variante: `defaultPokemonDbId;variantPokemonDbId`
   - **Si no hay default pero hay múltiples pokemons:**
     - Usa el primero como base y genera filas para los demás

2. **Resultado:** Una fila por cada variante de cada especie

#### Índices

- **COMPOSITE PRIMARY KEY:** `(pokemonId, variantPokemonId)`

#### Notas

- El CSV se genera en `Generate-PokemonVariantsCsv` (línea 3423-3483)
- La inserción se hace en `BackupProcessor._insertPokemonVariants` (línea 2685-2709)

---

## Tablas Auxiliares

### Generations

**Tabla:** `generations`  
**JSON Origen:** `generation/{id}/data.json`  
**Uso:** Almacena información de generaciones

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre de la generación (ej: "generation-i") |
| `mainRegionId` | INTEGER (nullable, FK) | `data.main_region.url` → Extrae API ID → Mapea a `regions.id` | Relación con región principal |

#### Relaciones

- **FK → `regions`**: `mainRegionId` referencia `regions.id`
- **1:N → `version_groups`**: Una generación tiene múltiples grupos de versión
- **1:N → `pokemon_species`**: Una generación tiene múltiples especies

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-GenerationsCsv` (línea 2048-2079)
- La inserción se hace en `BackupProcessor._insertGenerations` (línea 1676-1703)

---

### VersionGroups

**Tabla:** `version_groups`  
**JSON Origen:** `version-group/{id}/data.json`  
**Uso:** Almacena información de grupos de versión (juegos)

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `name` | TEXT | `data.name` | Nombre del grupo (ej: "red-blue", "yellow") |
| `generationId` | INTEGER (nullable, FK) | `data.generation.url` → Extrae API ID → Mapea a `generations.id` | Relación con generación |
| `order` | INTEGER (nullable) | `data.order` | Orden de visualización |

#### Relaciones

- **FK → `generations`**: `generationId` referencia `generations.id`
- **1:N → `pokemon_moves`**: Un grupo de versión tiene múltiples relaciones con movimientos
- **N:M → `pokedex`**: Un grupo de versión puede estar en múltiples pokedexes (a través de `pokedex.versionGroupsJson`)

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-VersionGroupsCsv` (línea 2297-2328)
- La inserción se hace en `BackupProcessor._insertVersionGroups` (línea 1836-1864)

---

### EvolutionChains

**Tabla:** `evolution_chains`  
**JSON Origen:** `evolution-chain/{id}/data.json`  
**Uso:** Almacena cadenas de evolución completas

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `apiId` | INTEGER (UNIQUE) | `data.id` | ID de la API |
| `babyTriggerItemId` | INTEGER (nullable, FK) | `data.baby_trigger_item.url` → Extrae API ID → Mapea a `items.id` | Item que desencadena la evolución del bebé |
| `chainJson` | TEXT (nullable) | `data.chain` → `ConvertTo-Json` | JSON completo de la cadena de evolución (estructura recursiva) |

#### Relaciones

- **FK → `items`**: `babyTriggerItemId` referencia `items.id`
- **1:N → `pokemon_species`**: Una cadena tiene múltiples especies (a través de `pokemon_species.evolutionChainId`)

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE:** `apiId`

#### Notas

- El CSV se genera en `Generate-EvolutionChainsCsv` (línea 2726-2757)
- La inserción se hace en `BackupProcessor._insertEvolutionChains` (línea 2271-2298)
- El `chainJson` contiene una estructura recursiva compleja que se almacena completa

---

### LocalizedNames

**Tabla:** `localized_names`  
**JSON Origen:** Múltiples (regions, pokemon-species, moves, abilities)  
**Uso:** Almacena nombres traducidos de múltiples entidades

#### Columnas y Origen

| Columna | Tipo | Origen | Descripción |
|---------|------|--------|-------------|
| `id` | INTEGER (PK, autoincrement) | Generado | ID interno de la BD |
| `entityType` | TEXT | String literal según la entidad | Tipo de entidad: "region", "pokemon", "move", "ability" |
| `entityId` | INTEGER (FK) | Depende del tipo (ver abajo) | ID de la entidad (no es FK directa, depende de entityType) |
| `languageId` | INTEGER (FK) | `nameEntry.language.url` → Extrae API ID → Mapea a `languages.id` | Relación con idioma |
| `name` | TEXT | `nameEntry.name` | Nombre traducido |

#### Relaciones

- **FK → `languages`**: `languageId` referencia `languages.id`
- **FK implícita:** `entityId` referencia diferentes tablas según `entityType`:
  - "region" → `regions.id`
  - "pokemon" → `pokemon_species.id` (no `pokemon.id`)
  - "move" → `moves.id`
  - "ability" → `abilities.id`

#### Lógica de Generación

**Función:** `Generate-LocalizedNamesCsv` (línea 3485-3641)

1. **Para regions:**
   - Lee `data.names`
   - Genera fila: `region;regionDbId;languageDbId;name`

2. **Para pokemon-species:**
   - Lee `data.names`
   - Genera fila: `pokemon;speciesDbId;languageDbId;name`

3. **Para moves:**
   - Lee `data.names`
   - Genera fila: `move;moveDbId;languageDbId;name`

4. **Para abilities:**
   - Lee `data.names`
   - Genera fila: `ability;abilityDbId;languageDbId;name`

#### Índices

- **PRIMARY KEY:** `id`
- **UNIQUE KEY:** `(entityType, entityId, languageId)` - No puede haber el mismo nombre traducido duplicado

#### Notas

- El CSV se genera en `Generate-LocalizedNamesCsv` (línea 3485-3641)
- La inserción se hace en `BackupProcessor._insertLocalizedNames` (línea 2711-2737)
- Esta tabla permite búsquedas multilingües

---

## Procesamiento de Multimedia

### Flujo Completo

1. **FASE 2 (Descarga):**
   - `Extract-MediaUrlsFromFiles` extrae URLs de `urls.txt` y JSONs
   - `Download-MediaFilesInParallel` descarga archivos en paralelo
   - Archivos se guardan con nombres específicos: `pokemon_{id}_default_{tipo}.{ext}`

2. **FASE 3 (Procesamiento):**
   - `Copy-PokemonMediaFiles`, `Copy-ItemMediaFiles`, `Copy-TypeMediaFiles` copian archivos a `tempMediaDir/`
   - Se añade prefijo `media_` a los nombres
   - Archivos se organizan en subcarpetas: `pokemon/`, `item/`, `type/`, `pokemon-form/`, `form/`

3. **FASE 3 (ZIP):**
   - Para cada carpeta de media:
     - Se copian todos los archivos a un directorio temporal plano
     - Se crea ZIP: `poke_searcher_backup_media_{categoria}.zip`
     - **IMPORTANTE:** Todos los archivos están en la raíz del ZIP (sin subdirectorios)

4. **App (Extracción):**
   - `BackupProcessor._extractZip` extrae ZIP a `poke_searcher_data/`
   - **IMPORTANTE:** Flutter no preserva estructura de directorios, todos los archivos quedan en la raíz

5. **App (Búsqueda):**
   - `MediaPathHelper.assetPathToLocalPath` convierte ruta asset a ruta local
   - Busca archivo por nombre en `poke_searcher_data/` (recursivo)
   - Tiene fallbacks para buscar variantes de nombres (ej: con/sin `_default_`)

### Convenciones de Nombres

| Tipo | Formato Script | Formato ZIP/App | Ejemplo |
|------|---------------|-----------------|---------|
| Pokemon default | `pokemon_{id}_default_{tipo}.{ext}` | `media_pokemon_{id}_default_{tipo}.{ext}` | `media_pokemon_1_default_sprite_front_default.svg` |
| Pokemon version | `pokemon_{id}_{gen}_{vg}_{tipo}.{ext}` | `media_pokemon_{id}_{gen}_{vg}_{tipo}.{ext}` | `media_pokemon_1_generation_i_red_blue_front_transparent.png` |
| Item | `item_{id}_default_{filename}.{ext}` | `media_item_{id}_default_{filename}.{ext}` | `media_item_1_default_sprite.png` |
| Type | `type_{id}_{gen}_{vg}_name_icon.{ext}` | `media_type_{id}_{gen}_{vg}_name_icon.{ext}` | `media_type_1_generation_iii_ruby_sapphire_name_icon.png` |

### Rutas en CSV

Las rutas en los CSV tienen formato: `assets/media_{nombre_completo}`

Ejemplo: `assets/media_pokemon_1_default_sprite_front_default.svg`

**IMPORTANTE:** El prefijo `assets/` es solo conceptual. En la app, `MediaPathHelper` lo elimina y busca el archivo por nombre en `poke_searcher_data/`.

---

## Sistema de Mapeo de IDs

### Función: `Get-DbId($table, $apiId)`

**Ubicación:** Línea 1732-1745 y 3753-3766 (duplicada)

**Lógica:**
1. Si el `apiId` ya está en `$script:idMaps[$table]`, retorna el ID de BD existente
2. Si no, asigna un nuevo ID autoincremental desde `$script:idCounters[$table]`
3. Guarda el mapeo en `$script:idMaps[$table][$apiId] = $newId`
4. Incrementa el contador

**Importante:** Este sistema asegura que:
- Los IDs de BD son consistentes entre ejecuciones (siempre el mismo apiId → mismo dbId)
- Las relaciones FK funcionan correctamente
- No hay duplicados

### Orden de Generación de CSV

El orden es crítico porque las tablas dependen unas de otras:

1. `Languages` (no depende de nada)
2. `Generations` (depende de `Regions`, pero se genera antes porque `Regions` puede tener `mainGenerationId` null)
3. `Regions` (depende de `Generations`)
4. `Types` (depende de `Generations`, `MoveDamageClasses`)
5. `TypeDamageRelations` (depende de `Types`)
6. `Stats` (depende de `MoveDamageClasses`)
7. `VersionGroups` (depende de `Generations`)
8. `MoveDamageClasses` (no depende de nada)
9. `Abilities` (depende de `Generations`)
10. `Moves` (depende de `Types`, `MoveDamageClasses`, `Generations`)
11. `ItemPockets` (no depende de nada)
12. `ItemCategories` (depende de `ItemPockets`)
13. `Items` (depende de `ItemCategories`)
14. `EggGroups` (no depende de nada)
15. `GrowthRates` (no depende de nada)
16. `Natures` (depende de `Stats`)
17. `PokemonColors` (no depende de nada)
18. `PokemonShapes` (no depende de nada)
19. `PokemonHabitats` (no depende de nada)
20. `EvolutionChains` (depende de `Items`)
21. `PokemonSpecies` (depende de múltiples tablas)
22. `Pokedex` (depende de `Regions`)
23. `Pokemon` (depende de `PokemonSpecies`)
24. `PokemonTypes` (depende de `Pokemon`, `Types`)
25. `PokemonAbilities` (depende de `Pokemon`, `Abilities`)
26. `PokemonMoves` (depende de `Pokemon`, `Moves`, `VersionGroups`)
27. `PokedexEntries` (depende de `Pokedex`, `Pokemon`)
28. `PokemonVariants` (depende de `Pokemon`)
29. `LocalizedNames` (depende de múltiples tablas)

---

## Notas Finales

- **Todos los JSONs se almacenan completos** en campos `*Json` para evitar pérdida de información
- **Las relaciones se normalizan** en tablas intermedias para permitir consultas eficientes
- **Los archivos multimedia se aplanan** porque Flutter no puede crear directorios anidados al extraer ZIPs
- **El sistema de mapeo de IDs** asegura consistencia entre ejecuciones
- **El orden de generación de CSV** es crítico para mantener integridad referencial


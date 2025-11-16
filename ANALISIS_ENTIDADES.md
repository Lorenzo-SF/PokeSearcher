# Análisis de Entidades de PokeAPI

Este documento analiza todas las entidades descargadas de PokeAPI, su estructura JSON, relaciones y archivos multimedia asociados.

## Índice

1. [Entidades Principales](#entidades-principales)
2. [Entidades Secundarias](#entidades-secundarias)
3. [Relaciones entre Entidades](#relaciones-entre-entidades)
4. [Archivos Multimedia](#archivos-multimedia)
5. [Índices Necesarios](#índices-necesarios)

---

## Entidades Principales

### 1. Pokemon (`pokemon`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del pokemon
- `base_experience` (int): Experiencia base
- `height` (int): Altura en decímetros
- `weight` (int): Peso en hectogramos
- `is_default` (bool): Si es la forma por defecto
- `order` (int): Orden de visualización
- `abilities` (array): Habilidades del pokemon
  - `ability` (object): Referencia a Ability
  - `is_hidden` (bool): Si es habilidad oculta
  - `slot` (int): Slot de la habilidad
- `forms` (array): Formas del pokemon (referencias a PokemonForm)
- `game_indices` (array): Índices en diferentes juegos
  - `game_index` (int): Índice en el juego
  - `version` (object): Referencia a Version
- `held_items` (array): Items que puede sostener
  - `item` (object): Referencia a Item
  - `version_details` (array): Detalles por versión
- `location_area_encounters` (string): URL a encuentros
- `moves` (array): Movimientos que puede aprender
  - `move` (object): Referencia a Move
  - `version_group_details` (array): Detalles por version_group
- `sprites` (object): Sprites del pokemon
  - `front_default`, `back_default`, `front_shiny`, `back_shiny` (string): URLs de sprites
  - `other` (object): Otros sprites (dream-world, official-artwork, home)
  - `versions` (object): Sprites por generación/versión
- `species` (object): Referencia a PokemonSpecies
- `stats` (array): Estadísticas base
  - `stat` (object): Referencia a Stat
  - `effort` (int): Puntos de esfuerzo
  - `base_stat` (int): Valor base
- `types` (array): Tipos del pokemon
  - `slot` (int): Slot del tipo
  - `type` (object): Referencia a Type
- `cries` (object): URLs de sonidos
  - `latest` (string): URL del cry más reciente
  - `legacy` (string): URL del cry legacy

**Relaciones:**
- `abilities[].ability.url` → Ability (N:M, tabla intermedia: PokemonAbilities)
- `forms[].url` → PokemonForm (1:N)
- `game_indices[].version.url` → Version (N:M, tabla intermedia: PokemonGameIndices)
- `held_items[].item.url` → Item (N:M, tabla intermedia: PokemonHeldItems)
- `moves[].move.url` → Move (N:M, tabla intermedia: PokemonMoves)
- `sprites.other.dream_world.front_default` → Multimedia (SVG)
- `sprites.other.'official-artwork'.front_default` → Multimedia (PNG)
- `sprites.other.home.front_default` → Multimedia (PNG)
- `sprites.versions.*.*.front_transparent` → Multimedia (PNG)
- `sprites.versions.*.*.front_shiny_transparent` → Multimedia (PNG)
- `sprites.versions.*.*.front_gray` → Multimedia (PNG)
- `cries.latest` → Multimedia (OGG)
- `cries.legacy` → Multimedia (OGG)
- `species.url` → PokemonSpecies (N:1, FK)
- `stats[].stat.url` → Stat (N:M, tabla intermedia: PokemonStats)
- `types[].type.url` → Type (N:M, tabla intermedia: PokemonTypes)

**Multimedia:**
- Sprites default: `sprites.front_default`, `sprites.back_default`, `sprites.front_shiny`, `sprites.back_shiny`
- Sprites dream-world: `sprites.other.dream_world.front_default` (SVG, prioridad máxima)
- Sprites official-artwork: `sprites.other.'official-artwork'.front_default` (PNG, alta resolución)
- Sprites home: `sprites.other.home.front_default` (PNG, fallback)
- Sprites por versión: `sprites.versions.{generation}.{version_group}.{tipo}` (front_transparent, front_shiny_transparent, front_gray)
- Cries: `cries.latest` (prioridad) o `cries.legacy` (fallback)

**Nombres de archivos multimedia:**
- Default: `pokemon_{id}_default_sprite_{tipo}.{ext}`
- Versiones: `pokemon_{id}_{generation}_{version}_{tipo}.{ext}`
- Cries: `pokemon_{id}_default_cry_{latest|legacy}.ogg`

---

### 2. PokemonSpecies (`pokemon-species`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la especie
- `order` (int): Orden de visualización
- `gender_rate` (int): Tasa de género (-1 = sin género, 0-8 = tasa)
- `capture_rate` (int): Tasa de captura
- `base_happiness` (int): Felicidad base
- `is_baby` (bool): Si es bebé
- `is_legendary` (bool): Si es legendario
- `is_mythical` (bool): Si es mítico
- `hatch_counter` (int): Contador de eclosión
- `has_gender_differences` (bool): Si tiene diferencias de género
- `forms_switchable` (bool): Si puede cambiar de forma
- `growth_rate` (object): Referencia a GrowthRate
- `pokedex_numbers` (array): Números en diferentes pokedexes
  - `entry_number` (int): Número de entrada
  - `pokedex` (object): Referencia a Pokedex
- `egg_groups` (array): Grupos de huevo (referencias a EggGroup)
- `color` (object): Referencia a PokemonColor
- `shape` (object): Referencia a PokemonShape
- `evolves_from_species` (object|null): Referencia a PokemonSpecies (evolución anterior)
- `evolution_chain` (object): Referencia a EvolutionChain
- `habitat` (object|null): Referencia a PokemonHabitat
- `generation` (object): Referencia a Generation
- `names` (array): Nombres localizados
- `form_descriptions` (array): Descripciones de formas
- `flavor_text_entries` (array): Textos de sabor
  - `flavor_text` (string): Texto
  - `language` (object): Referencia a Language
  - `version` (object): Referencia a Version
- `genera` (array): Géneros
  - `genus` (string): Género
  - `language` (object): Referencia a Language
- `varieties` (array): Variedades del pokemon
  - `is_default` (bool): Si es la variedad por defecto
  - `pokemon` (object): Referencia a Pokemon

**Relaciones:**
- `growth_rate.url` → GrowthRate (N:1, FK)
- `pokedex_numbers[].pokedex.url` → Pokedex (N:M, tabla intermedia: PokedexEntries)
- `egg_groups[].url` → EggGroup (N:M, tabla intermedia: PokemonSpeciesEggGroups)
- `color.url` → PokemonColor (N:1, FK)
- `shape.url` → PokemonShape (N:1, FK)
- `evolves_from_species.url` → PokemonSpecies (1:1, FK nullable)
- `evolution_chain.url` → EvolutionChain (N:1, FK)
- `habitat.url` → PokemonHabitat (N:1, FK nullable)
- `generation.url` → Generation (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: PokemonSpeciesFlavorTexts)
- `flavor_text_entries[].version.url` → Version (N:M, tabla intermedia: PokemonSpeciesFlavorTexts)
- `genera[].language.url` → Language (N:M, tabla intermedia: PokemonSpeciesGenera)
- `varieties[].pokemon.url` → Pokemon (1:N)

**Multimedia:** Ninguno directo (usa multimedia de Pokemon)

---

### 3. Pokedex (`pokedex`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la pokedex
- `is_main_series` (bool): Si es de la serie principal
- `descriptions` (array): Descripciones
  - `description` (string): Texto
  - `language` (object): Referencia a Language
- `names` (array): Nombres localizados
- `pokemon_entries` (array): Entradas de pokemon
  - `entry_number` (int): Número de entrada
  - `pokemon_species` (object): Referencia a PokemonSpecies
- `region` (object|null): Referencia a Region
- `version_groups` (array): Grupos de versión (referencias a VersionGroup)

**Relaciones:**
- `descriptions[].language.url` → Language (N:M, tabla intermedia: PokedexDescriptions)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon_entries[].pokemon_species.url` → PokemonSpecies (N:M, tabla intermedia: PokedexEntries)
- `region.url` → Region (N:1, FK nullable)
- `version_groups[].url` → VersionGroup (N:M, tabla intermedia: PokedexVersionGroups)

**Multimedia:** Ninguno

---

### 4. Region (`region`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la región
- `locations` (array): Ubicaciones (referencias a Location)
- `main_generation` (object|null): Referencia a Generation
- `names` (array): Nombres localizados
- `pokedexes` (array): Pokedexes de la región (referencias a Pokedex)

**Relaciones:**
- `locations[].url` → Location (1:N)
- `main_generation.url` → Generation (N:1, FK nullable)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokedexes[].url` → Pokedex (1:N)

**Multimedia:** Ninguno

---

### 5. Type (`type`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del tipo
- `damage_relations` (object): Relaciones de daño
  - `double_damage_from` (array): Tipos que hacen doble daño
  - `double_damage_to` (array): Tipos que reciben doble daño
  - `half_damage_from` (array): Tipos que hacen medio daño
  - `half_damage_to` (array): Tipos que reciben medio daño
  - `no_damage_from` (array): Tipos que no hacen daño
  - `no_damage_to` (array): Tipos que no reciben daño
- `game_indices` (array): Índices en diferentes generaciones
  - `game_index` (int): Índice
  - `generation` (object): Referencia a Generation
- `generation` (object): Referencia a Generation
- `move_damage_class` (object|null): Referencia a MoveDamageClass
- `moves` (array): Movimientos de este tipo (referencias a Move)
- `names` (array): Nombres localizados
- `pokemon` (array): Pokemon de este tipo (referencias a Pokemon)

**Relaciones:**
- `damage_relations.*[].url` → Type (N:M, tabla intermedia: TypeDamageRelations)
- `game_indices[].generation.url` → Generation (N:M, tabla intermedia: TypeGameIndices)
- `generation.url` → Generation (N:1, FK)
- `move_damage_class.url` → MoveDamageClass (N:1, FK nullable)
- `moves[].url` → Move (1:N)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon[].url` → Pokemon (N:M, tabla intermedia: PokemonTypes)

**Multimedia:**
- Iconos por generación/versión: `sprites/generation-{n}/icons/{name}.png`
- Nombres de archivos: `type_{id}_{generation}_{version}_name_icon.{ext}`

---

### 6. Item (`item`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del item
- `cost` (int): Coste
- `fling_power` (int|null): Poder de lanzamiento
- `fling_effect` (object|null): Referencia a ItemFlingEffect
- `attributes` (array): Atributos (referencias a ItemAttribute)
- `category` (object): Referencia a ItemCategory
- `effect_entries` (array): Efectos
  - `effect` (string): Texto del efecto
  - `short_effect` (string): Efecto corto
  - `language` (object): Referencia a Language
- `flavor_text_entries` (array): Textos de sabor
- `game_indices` (array): Índices en diferentes generaciones
- `names` (array): Nombres localizados
- `held_by_pokemon` (array): Pokemon que lo sostienen
- `baby_trigger_for` (object|null): Referencia a EvolutionChain
- `machines` (array): Máquinas (referencias a Machine)

**Relaciones:**
- `fling_effect.url` → ItemFlingEffect (N:1, FK nullable)
- `attributes[].url` → ItemAttribute (N:M, tabla intermedia: ItemAttributes)
- `category.url` → ItemCategory (N:1, FK)
- `effect_entries[].language.url` → Language (N:M, tabla intermedia: ItemEffectEntries)
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: ItemFlavorTexts)
- `flavor_text_entries[].version_group.url` → VersionGroup (N:M, tabla intermedia: ItemFlavorTexts)
- `game_indices[].generation.url` → Generation (N:M, tabla intermedia: ItemGameIndices)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `held_by_pokemon[].pokemon.url` → Pokemon (N:M, tabla intermedia: PokemonHeldItems)
- `baby_trigger_for.url` → EvolutionChain (1:1, FK nullable)
- `machines[].url` → Machine (N:M, tabla intermedia: ItemMachines)

**Multimedia:**
- Sprites: `sprites.default` (URL a PNG)
- Nombres de archivos: `item_{id}_default_{filename}.{ext}`

---

### 7. Move (`move`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del movimiento
- `accuracy` (int|null): Precisión
- `effect_chance` (int|null): Probabilidad de efecto
- `pp` (int): Puntos de poder
- `priority` (int): Prioridad
- `power` (int|null): Poder
- `contest_combos` (object): Combos de concurso
- `contest_type` (object|null): Referencia a ContestType
- `contest_effect` (object|null): Referencia a ContestEffect
- `damage_class` (object): Referencia a MoveDamageClass
- `effect_entries` (array): Efectos
- `effect_changes` (array): Cambios de efecto
- `flavor_text_entries` (array): Textos de sabor
- `generation` (object): Referencia a Generation
- `machines` (array): Máquinas (referencias a Machine)
- `meta` (object): Metadatos
- `names` (array): Nombres localizados
- `past_values` (array): Valores pasados
- `stat_changes` (array): Cambios de estadísticas
- `super_contest_effect` (object|null): Referencia a SuperContestEffect
- `target` (object): Referencia a MoveTarget
- `type` (object): Referencia a Type

**Relaciones:**
- `contest_type.url` → ContestType (N:1, FK nullable)
- `contest_effect.url` → ContestEffect (N:1, FK nullable)
- `damage_class.url` → MoveDamageClass (N:1, FK)
- `effect_entries[].language.url` → Language (N:M, tabla intermedia: MoveEffectEntries)
- `effect_changes[].version_group.url` → VersionGroup (N:M, tabla intermedia: MoveEffectChanges)
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: MoveFlavorTexts)
- `flavor_text_entries[].version_group.url` → VersionGroup (N:M, tabla intermedia: MoveFlavorTexts)
- `generation.url` → Generation (N:1, FK)
- `machines[].url` → Machine (N:M, tabla intermedia: MoveMachines)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `stat_changes[].stat.url` → Stat (N:M, tabla intermedia: MoveStatChanges)
- `super_contest_effect.url` → SuperContestEffect (N:1, FK nullable)
- `target.url` → MoveTarget (N:1, FK)
- `type.url` → Type (N:1, FK)

**Multimedia:** Ninguno

---

### 8. Ability (`ability`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la habilidad
- `is_main_series` (bool): Si es de la serie principal
- `effect_entries` (array): Efectos
- `effect_changes` (array): Cambios de efecto
- `flavor_text_entries` (array): Textos de sabor
- `generation` (object): Referencia a Generation
- `names` (array): Nombres localizados
- `pokemon` (array): Pokemon con esta habilidad (referencias a Pokemon)

**Relaciones:**
- `effect_entries[].language.url` → Language (N:M, tabla intermedia: AbilityEffectEntries)
- `effect_changes[].version_group.url` → VersionGroup (N:M, tabla intermedia: AbilityEffectChanges)
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: AbilityFlavorTexts)
- `flavor_text_entries[].version_group.url` → VersionGroup (N:M, tabla intermedia: AbilityFlavorTexts)
- `generation.url` → Generation (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon[].url` → Pokemon (N:M, tabla intermedia: PokemonAbilities)

**Multimedia:** Ninguno

---

### 9. Generation (`generation`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la generación
- `abilities` (array): Habilidades introducidas (referencias a Ability)
- `main_region` (object): Referencia a Region
- `moves` (array): Movimientos introducidos (referencias a Move)
- `names` (array): Nombres localizados
- `pokemon_species` (array): Especies introducidas (referencias a PokemonSpecies)
- `types` (array): Tipos introducidos (referencias a Type)
- `version_groups` (array): Grupos de versión (referencias a VersionGroup)

**Relaciones:**
- `abilities[].url` → Ability (1:N)
- `main_region.url` → Region (1:N)
- `moves[].url` → Move (1:N)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon_species[].url` → PokemonSpecies (1:N)
- `types[].url` → Type (1:N)
- `version_groups[].url` → VersionGroup (1:N)

**Multimedia:** Ninguno

---

### 10. VersionGroup (`version-group`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del grupo de versión
- `order` (int): Orden
- `generation` (object): Referencia a Generation
- `move_learn_methods` (array): Métodos de aprendizaje (referencias a MoveLearnMethod)
- `pokedexes` (array): Pokedexes (referencias a Pokedex)
- `regions` (array): Regiones (referencias a Region)
- `versions` (array): Versiones (referencias a Version)

**Relaciones:**
- `generation.url` → Generation (N:1, FK)
- `move_learn_methods[].url` → MoveLearnMethod (N:M, tabla intermedia: VersionGroupMoveLearnMethods)
- `pokedexes[].url` → Pokedex (N:M, tabla intermedia: PokedexVersionGroups)
- `regions[].url` → Region (N:M, tabla intermedia: VersionGroupRegions)
- `versions[].url` → Version (1:N)

**Multimedia:** Ninguno

---

### 11. EvolutionChain (`evolution-chain`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `baby_trigger_item` (object|null): Referencia a Item
- `chain` (object): Cadena evolutiva
  - `is_baby` (bool): Si es bebé
  - `species` (object): Referencia a PokemonSpecies
  - `evolution_details` (array): Detalles de evolución
  - `evolves_to` (array): Evoluciones (recursivo)

**Relaciones:**
- `baby_trigger_item.url` → Item (1:1, FK nullable)
- `chain.species.url` → PokemonSpecies (1:1, FK)
- `chain.evolution_details[].item.url` → Item (N:1, FK nullable)
- `chain.evolution_details[].trigger.url` → EvolutionTrigger (N:1, FK)
- `chain.evolution_details[].known_move.url` → Move (N:1, FK nullable)
- `chain.evolution_details[].known_move_type.url` → Type (N:1, FK nullable)
- `chain.evolution_details[].location.url` → Location (N:1, FK nullable)
- `chain.evolution_details[].party_species.url` → PokemonSpecies (N:1, FK nullable)
- `chain.evolution_details[].party_type.url` → Type (N:1, FK nullable)
- `chain.evolution_details[].trade_species.url` → PokemonSpecies (N:1, FK nullable)
- `chain.evolves_to[].species.url` → PokemonSpecies (recursivo)

**Multimedia:** Ninguno

---

## Entidades Secundarias

### 12. Berry (`berry`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la baya
- `growth_time` (int): Tiempo de crecimiento
- `max_harvest` (int): Cosecha máxima
- `natural_gift_power` (int): Poder de regalo natural
- `size` (int): Tamaño
- `smoothness` (int): Suavidad
- `soil_dryness` (int): Sequedad del suelo
- `firmness` (object): Referencia a BerryFirmness
- `flavors` (array): Sabores
  - `flavor` (object): Referencia a BerryFlavor
  - `potency` (int): Potencia
- `item` (object): Referencia a Item
- `natural_gift_type` (object): Referencia a Type

**Relaciones:**
- `firmness.url` → BerryFirmness (N:1, FK)
- `flavors[].flavor.url` → BerryFlavor (N:M, tabla intermedia: BerryFlavors)
- `item.url` → Item (1:1, FK)
- `natural_gift_type.url` → Type (N:1, FK)

**Multimedia:** Ninguno

---

### 13. BerryFirmness (`berry-firmness`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la firmeza
- `berries` (array): Bayas con esta firmeza (referencias a Berry)
- `names` (array): Nombres localizados

**Relaciones:**
- `berries[].url` → Berry (1:N)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 14. BerryFlavor (`berry-flavor`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del sabor
- `berries` (array): Bayas con este sabor
  - `berry` (object): Referencia a Berry
  - `potency` (int): Potencia
- `contest_type` (object): Referencia a ContestType
- `names` (array): Nombres localizados

**Relaciones:**
- `berries[].berry.url` → Berry (N:M, tabla intermedia: BerryFlavors)
- `contest_type.url` → ContestType (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 15. Characteristic (`characteristic`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `gene_modulo` (int): Módulo del gen
- `possible_values` (array): Valores posibles
- `highest_stat` (object): Referencia a Stat
- `descriptions` (array): Descripciones
  - `description` (string): Texto
  - `language` (object): Referencia a Language

**Relaciones:**
- `highest_stat.url` → Stat (N:1, FK)
- `descriptions[].language.url` → Language (N:M, tabla intermedia: CharacteristicDescriptions)

**Multimedia:** Ninguno

---

### 16. ContestEffect (`contest-effect`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `appeal` (int): Apelación
- `jam` (int): Interferencia
- `effect_entries` (array): Efectos
- `flavor_text_entries` (array): Textos de sabor

**Relaciones:**
- `effect_entries[].language.url` → Language (N:M, tabla intermedia: ContestEffectEffectEntries)
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: ContestEffectFlavorTexts)

**Multimedia:** Ninguno

---

### 17. ContestType (`contest-type`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del tipo de concurso
- `berry_flavor` (object): Referencia a BerryFlavor
- `names` (array): Nombres localizados

**Relaciones:**
- `berry_flavor.url` → BerryFlavor (1:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 18. EncounterCondition (`encounter-condition`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la condición
- `names` (array): Nombres localizados
- `values` (array): Valores (referencias a EncounterConditionValue)

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `values[].url` → EncounterConditionValue (1:N)

**Multimedia:** Ninguno

---

### 19. EncounterConditionValue (`encounter-condition-value`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del valor
- `condition` (object): Referencia a EncounterCondition
- `names` (array): Nombres localizados

**Relaciones:**
- `condition.url` → EncounterCondition (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 20. EncounterMethod (`encounter-method`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del método
- `order` (int): Orden
- `names` (array): Nombres localizados

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 21. Gender (`gender`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del género
- `pokemon_species_details` (array): Detalles de especies
- `required_for_evolution` (array): Requerido para evolución

**Relaciones:**
- `pokemon_species_details[].pokemon_species.url` → PokemonSpecies (N:M, tabla intermedia: GenderPokemonSpecies)

**Multimedia:** Ninguno

---

### 22. ItemAttribute (`item-attribute`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del atributo
- `descriptions` (array): Descripciones
- `items` (array): Items con este atributo (referencias a Item)
- `names` (array): Nombres localizados

**Relaciones:**
- `descriptions[].language.url` → Language (N:M, tabla intermedia: ItemAttributeDescriptions)
- `items[].url` → Item (N:M, tabla intermedia: ItemAttributes)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 23. ItemFlingEffect (`item-fling-effect`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del efecto
- `effect_entries` (array): Efectos
- `items` (array): Items con este efecto (referencias a Item)

**Relaciones:**
- `effect_entries[].language.url` → Language (N:M, tabla intermedia: ItemFlingEffectEffectEntries)
- `items[].url` → Item (1:N)

**Multimedia:** Ninguno

---

### 24. Location (`location`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la ubicación
- `region` (object|null): Referencia a Region
- `names` (array): Nombres localizados
- `game_indices` (array): Índices en diferentes generaciones
- `areas` (array): Áreas (referencias a LocationArea)

**Relaciones:**
- `region.url` → Region (N:1, FK nullable)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `game_indices[].generation.url` → Generation (N:M, tabla intermedia: LocationGameIndices)
- `areas[].url` → LocationArea (1:N)

**Multimedia:** Ninguno

---

### 25. LocationArea (`location-area`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del área
- `game_index` (int): Índice en el juego
- `encounter_method_rates` (array): Tasas de métodos de encuentro
- `location` (object): Referencia a Location
- `names` (array): Nombres localizados
- `pokemon_encounters` (array): Encuentros de pokemon

**Relaciones:**
- `encounter_method_rates[].encounter_method.url` → EncounterMethod (N:M, tabla intermedia: LocationAreaEncounterMethodRates)
- `location.url` → Location (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon_encounters[].pokemon_species.url` → PokemonSpecies (N:M, tabla intermedia: LocationAreaPokemonEncounters)

**Multimedia:** Ninguno

---

### 26. Machine (`machine`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `item` (object): Referencia a Item
- `move` (object): Referencia a Move
- `version_group` (object): Referencia a VersionGroup

**Relaciones:**
- `item.url` → Item (N:1, FK)
- `move.url` → Move (N:1, FK)
- `version_group.url` → VersionGroup (N:1, FK)

**Multimedia:** Ninguno

---

### 27. MoveAilment (`move-ailment`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la aflicción
- `moves` (array): Movimientos con esta aflicción (referencias a Move)
- `names` (array): Nombres localizados

**Relaciones:**
- `moves[].url` → Move (1:N)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 28. MoveBattleStyle (`move-battle-style`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del estilo
- `names` (array): Nombres localizados

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 29. MoveCategory (`move-category`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la categoría
- `moves` (array): Movimientos de esta categoría (referencias a Move)
- `descriptions` (array): Descripciones

**Relaciones:**
- `moves[].url` → Move (1:N)
- `descriptions[].language.url` → Language (N:M, tabla intermedia: MoveCategoryDescriptions)

**Multimedia:** Ninguno

---

### 30. MoveLearnMethod (`move-learn-method`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del método
- `descriptions` (array): Descripciones
- `names` (array): Nombres localizados
- `version_groups` (array): Grupos de versión (referencias a VersionGroup)

**Relaciones:**
- `descriptions[].language.url` → Language (N:M, tabla intermedia: MoveLearnMethodDescriptions)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `version_groups[].url` → VersionGroup (N:M, tabla intermedia: VersionGroupMoveLearnMethods)

**Multimedia:** Ninguno

---

### 31. MoveTarget (`move-target`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del objetivo
- `descriptions` (array): Descripciones
- `moves` (array): Movimientos con este objetivo (referencias a Move)
- `names` (array): Nombres localizados

**Relaciones:**
- `descriptions[].language.url` → Language (N:M, tabla intermedia: MoveTargetDescriptions)
- `moves[].url` → Move (1:N)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)

**Multimedia:** Ninguno

---

### 32. PalParkArea (`pal-park-area`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre del área
- `names` (array): Nombres localizados
- `pokemon_encounters` (array): Encuentros de pokemon
  - `base_score` (int): Puntuación base
  - `rate` (int): Tasa
  - `pokemon_species` (object): Referencia a PokemonSpecies

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `pokemon_encounters[].pokemon_species.url` → PokemonSpecies (N:M, tabla intermedia: PalParkAreaPokemonEncounters)

**Multimedia:** Ninguno

---

### 33. PokeathlonStat (`pokeathlon-stat`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la estadística
- `names` (array): Nombres localizados
- `affecting_natures` (object): Naturalezas que afectan
  - `increase` (array): Aumentos
  - `decrease` (array): Decreases

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `affecting_natures.increase[].nature.url` → Nature (N:M, tabla intermedia: PokeathlonStatNatures)
- `affecting_natures.decrease[].nature.url` → Nature (N:M, tabla intermedia: PokeathlonStatNatures)

**Multimedia:** Ninguno

---

### 34. PokemonForm (`pokemon-form`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la forma
- `order` (int): Orden
- `form_order` (int): Orden de forma
- `is_default` (bool): Si es la forma por defecto
- `is_battle_only` (bool): Si es solo para batalla
- `is_mega` (bool): Si es mega evolución
- `form_name` (string): Nombre de la forma
- `pokemon` (object): Referencia a Pokemon
- `sprites` (object): Sprites de la forma
- `types` (array): Tipos de la forma
- `version_group` (object): Referencia a VersionGroup
- `names` (array): Nombres localizados
- `form_names` (array): Nombres de forma

**Relaciones:**
- `pokemon.url` → Pokemon (N:1, FK)
- `sprites.front_default`, `sprites.back_default`, etc. → Multimedia
- `types[].type.url` → Type (N:M, tabla intermedia: PokemonFormTypes)
- `version_group.url` → VersionGroup (N:1, FK)
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `form_names[].language.url` → Language (N:M, tabla intermedia: PokemonFormFormNames)

**Multimedia:**
- Sprites: `sprites.front_default`, `sprites.back_default`, `sprites.front_shiny`, `sprites.back_shiny`
- Nombres de archivos: `pokemon-form_{id}_default_{filename}.{ext}`

---

### 35. SuperContestEffect (`super-contest-effect`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `appeal` (int): Apelación
- `flavor_text_entries` (array): Textos de sabor

**Relaciones:**
- `flavor_text_entries[].language.url` → Language (N:M, tabla intermedia: SuperContestEffectFlavorTexts)

**Multimedia:** Ninguno

---

### 36. Version (`version`)

**Estructura JSON:**
- `id` (int): ID único de la API
- `name` (string): Nombre de la versión
- `names` (array): Nombres localizados
- `version_group` (object): Referencia a VersionGroup

**Relaciones:**
- `names[].language.url` → Language (N:M, tabla intermedia: LocalizedNames)
- `version_group.url` → VersionGroup (N:1, FK)

**Multimedia:** Ninguno

---

## Relaciones entre Entidades

### Tipos de Relaciones

1. **1:1 (One-to-One)**: Una entidad se relaciona con exactamente una instancia de otra
   - Ejemplo: `PokemonForm.pokemon` → `Pokemon` (una forma pertenece a un pokemon)

2. **1:N (One-to-Many)**: Una entidad se relaciona con múltiples instancias de otra
   - Ejemplo: `Region.pokedexes` → `Pokedex` (una región tiene múltiples pokedexes)

3. **N:M (Many-to-Many)**: Múltiples instancias de una entidad se relacionan con múltiples instancias de otra
   - Requiere tabla intermedia
   - Ejemplo: `Pokemon.types` → `Type` (tabla intermedia: `PokemonTypes`)

### Tablas Intermedias Necesarias

1. **PokemonAbilities**: Pokemon ↔ Ability
2. **PokemonTypes**: Pokemon ↔ Type
3. **PokemonMoves**: Pokemon ↔ Move
4. **PokemonStats**: Pokemon ↔ Stat
5. **PokemonHeldItems**: Pokemon ↔ Item
6. **PokemonGameIndices**: Pokemon ↔ Version
7. **PokedexEntries**: Pokedex ↔ PokemonSpecies
8. **TypeDamageRelations**: Type ↔ Type (relaciones de daño)
9. **PokemonSpeciesEggGroups**: PokemonSpecies ↔ EggGroup
10. **PokemonSpeciesFlavorTexts**: PokemonSpecies ↔ Language + Version
11. **PokemonSpeciesGenera**: PokemonSpecies ↔ Language
12. **BerryFlavors**: Berry ↔ BerryFlavor
13. **ItemAttributes**: Item ↔ ItemAttribute
14. **ItemFlavorTexts**: Item ↔ Language + VersionGroup
15. **ItemGameIndices**: Item ↔ Generation
16. **ItemMachines**: Item ↔ Machine
17. **MoveEffectEntries**: Move ↔ Language
18. **MoveEffectChanges**: Move ↔ VersionGroup
19. **MoveFlavorTexts**: Move ↔ Language + VersionGroup
20. **MoveStatChanges**: Move ↔ Stat
21. **MoveMachines**: Move ↔ Machine
22. **AbilityEffectEntries**: Ability ↔ Language
23. **AbilityEffectChanges**: Ability ↔ VersionGroup
24. **AbilityFlavorTexts**: Ability ↔ Language + VersionGroup
25. **TypeGameIndices**: Type ↔ Generation
26. **VersionGroupMoveLearnMethods**: VersionGroup ↔ MoveLearnMethod
27. **PokedexVersionGroups**: Pokedex ↔ VersionGroup
28. **VersionGroupRegions**: VersionGroup ↔ Region
29. **GenderPokemonSpecies**: Gender ↔ PokemonSpecies
30. **LocationAreaEncounterMethodRates**: LocationArea ↔ EncounterMethod
31. **LocationAreaPokemonEncounters**: LocationArea ↔ PokemonSpecies
32. **LocationGameIndices**: Location ↔ Generation
33. **PalParkAreaPokemonEncounters**: PalParkArea ↔ PokemonSpecies
34. **PokeathlonStatNatures**: PokeathlonStat ↔ Nature
35. **PokemonFormTypes**: PokemonForm ↔ Type
36. **PokemonFormFormNames**: PokemonForm ↔ Language
37. **LocalizedNames**: Varias entidades ↔ Language (tabla genérica)
38. **PokedexDescriptions**: Pokedex ↔ Language
39. **CharacteristicDescriptions**: Characteristic ↔ Language
40. **ContestEffectEffectEntries**: ContestEffect ↔ Language
41. **ContestEffectFlavorTexts**: ContestEffect ↔ Language
42. **ItemAttributeDescriptions**: ItemAttribute ↔ Language
43. **ItemFlingEffectEffectEntries**: ItemFlingEffect ↔ Language
44. **MoveCategoryDescriptions**: MoveCategory ↔ Language
45. **MoveLearnMethodDescriptions**: MoveLearnMethod ↔ Language
46. **MoveTargetDescriptions**: MoveTarget ↔ Language
47. **SuperContestEffectFlavorTexts**: SuperContestEffect ↔ Language

---

## Archivos Multimedia

### Convenciones de Nombres

#### Script (Estructura Original)
- Pokemon: `pokemon/{id}/{filename}.{ext}`
- Item: `item/{id}/{filename}.{ext}`
- Type: `type/{id}/{filename}.{ext}`
- PokemonForm: `pokemon-form/{id}/{filename}.{ext}`

#### App (Aplanado)
- Todos los archivos en raíz: `poke_searcher_data/`
- Prefijo: `media_`
- Formato: `media_{entidad}_{id}_{tipo}.{ext}`

### Tipos de Multimedia

1. **Sprites de Pokemon (Default)**
   - Prioridad: SVG dream-world > PNG official-artwork > PNG home
   - Nombres: `pokemon_{id}_default_sprite_{tipo}.{ext}`
   - Tipos: `front_default`, `back_default`, `front_shiny`, `back_shiny`, `artwork_official`

2. **Sprites de Pokemon (Versiones)**
   - De `sprites.versions.{generation}.{version_group}`
   - Nombres: `pokemon_{id}_{generation}_{version}_{tipo}.{ext}`
   - Tipos: `front_transparent`, `front_shiny_transparent`, `front_gray`

3. **Cries de Pokemon**
   - Prioridad: `cries.latest` > `cries.legacy`
   - Nombres: `pokemon_{id}_default_cry_{latest|legacy}.ogg`

4. **Sprites de Item**
   - De `sprites.default`
   - Nombres: `item_{id}_default_{filename}.{ext}`

5. **Iconos de Type**
   - Por generación/versión
   - Nombres: `type_{id}_{generation}_{version}_name_icon.{ext}`

6. **Sprites de PokemonForm**
   - Similar a Pokemon
   - Nombres: `pokemon-form_{id}_default_{filename}.{ext}`

---

## Índices Necesarios

### Índices por Nombre
- `idx_regions_name`
- `idx_types_name`
- `idx_pokemon_species_name`
- `idx_pokemon_name`
- `idx_moves_name`
- `idx_abilities_name`
- `idx_items_name`
- `idx_berries_name`
- `idx_locations_name`
- `idx_versions_name`

### Índices por Foreign Key
- `idx_regions_main_generation`
- `idx_types_generation`
- `idx_pokemon_species_id` (en Pokemon)
- `idx_pokemon_types_pokemon`
- `idx_pokemon_types_type`
- `idx_pokemon_abilities_pokemon`
- `idx_pokemon_abilities_ability`
- `idx_pokemon_moves_pokemon`
- `idx_pokemon_moves_move`
- `idx_pokedex_entries_pokedex`
- `idx_pokedex_entries_pokemon`
- `idx_pokedex_region`
- `idx_pokemon_form_pokemon`
- `idx_pokemon_form_version_group`
- `idx_machine_item`
- `idx_machine_move`
- `idx_machine_version_group`
- `idx_location_region`
- `idx_location_area_location`
- `idx_version_version_group`

### Índices Compuestos
- `idx_localized_names_entity` (entity_type, entity_id, language_id)
- `idx_download_sync_phase` (phase, entity_type)
- `idx_type_damage_relations` (type_id, related_type_id)
- `idx_pokedex_version_groups` (pokedex_id, version_group_id)

---

## Notas Finales

- Todas las tablas deben tener:
  - `id` (auto-increment, primary key)
  - `apiId` (único, desde JSON `id`)
  - `dataJson` (TEXT, JSON completo por si acaso)
  
- Las relaciones se resuelven durante la generación de CSV:
  - URLs → IDs de BD usando mapeo de `apiId`

- Los archivos multimedia se aplanan al crear el ZIP:
  - Estructura original → Nombre aplanado con prefijo `media_`
  - Rutas en BD: `assets/media_{nombre_aplanado}`

- La app busca archivos en estructura aplanada:
  - Directorio: `poke_searcher_data/`
  - Sin subdirectorios


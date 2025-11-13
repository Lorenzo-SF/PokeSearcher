# ============================================================
# Script para generar CSV desde JSONs descargados
# Lee todos los JSONs de pokemon_data y genera archivos CSV
# Compatible con PowerShell 5.1+
# ============================================================

param(
    [string]$DataDir = "C:\Users\loren\Desktop\pokemon_data",
    [string]$OutputDir = "C:\Users\loren\Desktop\proyectos\pokesearch\poke_searcher\assets\database",
    [string]$MediaDir = "C:\Users\loren\Desktop\proyectos\pokesearch\poke_searcher\assets\media"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ============================================================
# CONFIGURACIÓN
# ============================================================

# Colores para tipos (TypeColors.dart)
$TypeColors = @{
    'normal' = '#A8A77A'
    'fire' = '#EE8130'
    'water' = '#6390F0'
    'grass' = '#7AC74C'
    'electric' = '#F7D02C'
    'ice' = '#96D9D6'
    'fighting' = '#C22E28'
    'poison' = '#A33EA1'
    'ground' = '#E2BF65'
    'flying' = '#A98FF3'
    'psychic' = '#F95587'
    'bug' = '#A6B91A'
    'rock' = '#B6A136'
    'ghost' = '#735797'
    'dragon' = '#6F35FC'
    'dark' = '#705746'
    'steel' = '#B7B7CE'
    'fairy' = '#D685AD'
}

# Colores pastel para pokedexes
$PastelColors = @(
    '#FFB3BA', '#FFDFBA', '#FFFFBA', '#BAFFC9', '#BAE1FF',
    '#E0BBE4', '#FFCCCB', '#F0E68C', '#DDA0DD', '#98D8C8',
    '#F7DC6F', '#AED6F1', '#F8BBD0', '#C8E6C9', '#FFE5B4',
    '#E1BEE7', '#BBDEFB', '#FFECB3', '#C5E1A5', '#B2DFDB'
)

# Diccionarios para mapear API IDs a IDs de base de datos
$idMaps = @{
    languages = @{}
    regions = @{}
    types = @{}
    generations = @{}
    versionGroups = @{}
    stats = @{}
    abilities = @{}
    moves = @{}
    items = @{}
    pokedex = @{}
    pokemonSpecies = @{}
    pokemon = @{}
    eggGroups = @{}
    growthRates = @{}
    natures = @{}
    pokemonColors = @{}
    pokemonShapes = @{}
    pokemonHabitats = @{}
    moveDamageClasses = @{}
    itemCategories = @{}
    itemPockets = @{}
    evolutionChains = @{}
}

# Contadores de IDs autoincrementales
$idCounters = @{
    languages = 1
    regions = 1
    types = 1
    generations = 1
    versionGroups = 1
    stats = 1
    abilities = 1
    moves = 1
    items = 1
    pokedex = 1
    pokemonSpecies = 1
    pokemon = 1
    eggGroups = 1
    growthRates = 1
    natures = 1
    pokemonColors = 1
    pokemonShapes = 1
    pokemonHabitats = 1
    moveDamageClasses = 1
    itemCategories = 1
    itemPockets = 1
    evolutionChains = 1
}

# ============================================================
# FUNCIONES AUXILIARES
# ============================================================

function Get-ApiIdFromUrl($url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $null
    }
    
    try {
        $uri = [System.Uri]$url
        $segments = $uri.Segments
        if ($segments.Count -gt 0) {
            $lastSegment = $segments[$segments.Count - 1].TrimEnd('/')
            $parsedId = 0
            if ([int]::TryParse($lastSegment, [ref]$parsedId)) {
                return $parsedId
            }
        }
    }
    catch {
        # Ignorar errores
    }
    
    return $null
}

function Get-DbId($table, $apiId) {
    if ($null -eq $apiId) {
        return $null
    }
    
    if ($idMaps[$table].ContainsKey($apiId)) {
        return $idMaps[$table][$apiId]
    }
    
    $newId = $idCounters[$table]
    $idMaps[$table][$apiId] = $newId
    $idCounters[$table]++
    return $newId
}

function Escape-CsvValue($value) {
    if ($null -eq $value) {
        return ''
    }
    
    if ($value -is [bool]) {
        if ($value) {
            return '1'
        } else {
            return '0'
        }
    }
    
    if ($value -is [int] -or $value -is [long]) {
        return $value.ToString()
    }
    
    $str = $value.ToString()
    # Escapar comillas dobles duplicándolas
    $str = $str -replace '"', '""'
    # Si contiene ;, comillas o saltos de línea, envolver en comillas
    if ($str -match '[;"]' -or $str -match "`r`n|`n|`r") {
        return "`"$str`""
    }
    return $str
}

function Escape-CsvJson($value) {
    if ($null -eq $value) {
        return ''
    }
    
    $json = $value | ConvertTo-Json -Depth 100 -Compress
    # Escapar comillas dobles duplicándolas
    $json = $json -replace '"', '""'
    # Siempre envolver JSON en comillas porque puede contener ; y saltos de línea
    return "`"$json`""
}

function Get-AssetPath($relativePath) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return ''
    }
    # Normalizar separadores de ruta
    # Mantener el prefijo "assets/" para compatibilidad con el código existente
    # El código de Flutter convertirá estas rutas a rutas locales
    $normalized = $relativePath -replace '\\', '/'
    if (-not $normalized.StartsWith('assets/')) {
        $normalized = "assets/$normalized"
    }
    return $normalized
}

# Función auxiliar para obtener la ruta del archivo descargado desde una URL
function Get-DownloadedFilePath($url, $dataDir, $pokemonApiId) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $null
    }
    
    try {
        $uri = [System.Uri]$url
        $fileName = Split-Path $uri.AbsolutePath -Leaf
        $ext = [System.IO.Path]::GetExtension($url).TrimStart('.')
        if ([string]::IsNullOrWhiteSpace($ext)) {
            $ext = [System.IO.Path]::GetExtension($fileName).TrimStart('.')
        }
        
        # Extraer el ID del pokemon de la URL o usar el proporcionado
        $pokemonId = $pokemonApiId
        if ($null -eq $pokemonId -and $url -match '/pokemon/(\d+)') {
            $pokemonId = $matches[1]
        }
        
        if ($null -ne $pokemonId) {
            $pokemonDir = Join-Path $dataDir "pokemon\$pokemonId"
            if (Test-Path $pokemonDir) {
                # Primero intentar encontrar el archivo por el nombre exacto de la URL
                $filePath = Join-Path $pokemonDir $fileName
                if (Test-Path $filePath) {
                    return $filePath
                }
                
                # Si no se encuentra, buscar archivos con nombres genéricos basados en el ID
                # Los archivos descargados pueden tener nombres como: 1.svg, 1.png, 1.ogg, etc.
                $genericNames = @(
                    "$pokemonId.$ext",
                    "$pokemonId.$ext".ToLower(),
                    "$pokemonId.$ext".ToUpper()
                )
                
                foreach ($genericName in $genericNames) {
                    $filePath = Join-Path $pokemonDir $genericName
                    if (Test-Path $filePath) {
                        return $filePath
                    }
                }
                
                # Si aún no se encuentra, buscar cualquier archivo con la extensión correcta
                # pero priorizar archivos con nombres que contengan el ID
                $allFiles = Get-ChildItem -Path $pokemonDir -File -ErrorAction SilentlyContinue | Where-Object {
                    $_.Extension -eq ".$ext" -or $_.Extension -eq ".$($ext.ToLower())" -or $_.Extension -eq ".$($ext.ToUpper())"
                }
                
                if ($allFiles.Count -gt 0) {
                    # Priorizar archivos que contengan el ID en el nombre
                    $preferredFile = $allFiles | Where-Object { $_.Name -match "^$pokemonId\." } | Select-Object -First 1
                    if ($null -ne $preferredFile) {
                        return $preferredFile.FullName
                    }
                    # Si no hay ninguno con el ID, usar el primero encontrado
                    return $allFiles[0].FullName
                }
            }
        }
        
        # Buscar recursivamente en todos los directorios de pokemon (fallback)
        $pokemonDirs = Get-ChildItem -Path (Join-Path $dataDir "pokemon") -Directory -ErrorAction SilentlyContinue
        foreach ($pokemonDir in $pokemonDirs) {
            $filePath = Join-Path $pokemonDir.FullName $fileName
            if (Test-Path $filePath) {
                return $filePath
            }
        }
    }
    catch {
        # Ignorar errores
    }
    
    return $null
}

# Función auxiliar para copiar un archivo desde URL a destino con nombre específico
function Copy-MediaFromUrl($spriteUrl, $destFileName, $pokemonApiId, $dataDir, $pokemonMediaDir) {
    if ([string]::IsNullOrWhiteSpace($spriteUrl)) {
        return $false
    }
    
    $destPath = Join-Path $pokemonMediaDir $destFileName
    
    # Si ya existe, no copiar
    if (Test-Path $destPath) {
        return $true
    }
    
    # Buscar el archivo descargado (ahora con el ID del pokemon para mejor búsqueda)
    $sourceFile = Get-DownloadedFilePath $spriteUrl $dataDir $pokemonApiId
    
    if ($null -ne $sourceFile -and (Test-Path $sourceFile)) {
        try {
            Copy-Item -Path $sourceFile -Destination $destPath -Force -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
    
    return $false
}

function Process-PokemonMedia($pokemonApiId, $pokemonData, $dataDir, $mediaDir) {
    $mediaPaths = @{
        spriteFrontDefaultPath = $null
        spriteFrontShinyPath = $null
        spriteBackDefaultPath = $null
        spriteBackShinyPath = $null
        artworkOfficialPath = $null
        artworkOfficialShinyPath = $null
        cryLatestPath = $null
        cryLegacyPath = $null
    }
    
    $pokemonSourceDir = Join-Path $dataDir "pokemon\$pokemonApiId"
    $pokemonMediaDir = Join-Path $mediaDir "pokemon\$pokemonApiId"
    
    if (-not (Test-Path $pokemonSourceDir)) {
        return $mediaPaths
    }
    
    if (-not (Test-Path $pokemonMediaDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $pokemonMediaDir | Out-Null
        } catch {
            return $mediaPaths
        }
    }
    
    # Procesar sprites - usar las URLs directamente desde los datos
    if ($pokemonData.sprites) {
        $sprites = $pokemonData.sprites
        
        # front_default - priorizar dream_world (SVG), luego front_default (PNG)
        if ($sprites.other.dream_world.front_default) {
            if (Copy-MediaFromUrl $sprites.other.dream_world.front_default "sprite_front_default.svg" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.spriteFrontDefaultPath = Get-AssetPath "media/pokemon/$pokemonApiId/sprite_front_default.svg"
            }
        } elseif ($sprites.front_default) {
            if (Copy-MediaFromUrl $sprites.front_default "sprite_front_default.png" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.spriteFrontDefaultPath = Get-AssetPath "media/pokemon/$pokemonApiId/sprite_front_default.png"
            }
        }
        
        # front_shiny
        if ($sprites.front_shiny) {
            if (Copy-MediaFromUrl $sprites.front_shiny "sprite_front_shiny.png" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.spriteFrontShinyPath = Get-AssetPath "media/pokemon/$pokemonApiId/sprite_front_shiny.png"
            }
        }
        
        # back_default
        if ($sprites.back_default) {
            if (Copy-MediaFromUrl $sprites.back_default "sprite_back_default.png" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.spriteBackDefaultPath = Get-AssetPath "media/pokemon/$pokemonApiId/sprite_back_default.png"
            }
        }
        
        # back_shiny
        if ($sprites.back_shiny) {
            if (Copy-MediaFromUrl $sprites.back_shiny "sprite_back_shiny.png" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.spriteBackShinyPath = Get-AssetPath "media/pokemon/$pokemonApiId/sprite_back_shiny.png"
            }
        }
        
        # official-artwork front_default - priorizar SVG si está disponible
        if ($sprites.other.'official-artwork'.front_default) {
            $officialUrl = $sprites.other.'official-artwork'.front_default
            $ext = [System.IO.Path]::GetExtension($officialUrl).TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($ext)) {
                $ext = "png"
            }
            $fileName = "artwork_official.$ext"
            if (Copy-MediaFromUrl $officialUrl $fileName $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.artworkOfficialPath = Get-AssetPath "media/pokemon/$pokemonApiId/$fileName"
            }
        }
        
        # official-artwork front_shiny
        if ($sprites.other.'official-artwork'.front_shiny) {
            $officialShinyUrl = $sprites.other.'official-artwork'.front_shiny
            $ext = [System.IO.Path]::GetExtension($officialShinyUrl).TrimStart('.')
            if ([string]::IsNullOrWhiteSpace($ext)) {
                $ext = "png"
            }
            $fileName = "artwork_official_shiny.$ext"
            if (Copy-MediaFromUrl $officialShinyUrl $fileName $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.artworkOfficialShinyPath = Get-AssetPath "media/pokemon/$pokemonApiId/$fileName"
            }
        }
    }
    
    # Procesar cries
    if ($pokemonData.cries) {
        if ($pokemonData.cries.latest) {
            if (Copy-MediaFromUrl $pokemonData.cries.latest "cry_latest.ogg" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.cryLatestPath = Get-AssetPath "media/pokemon/$pokemonApiId/cry_latest.ogg"
            }
        }
        
        if ($pokemonData.cries.legacy) {
            if (Copy-MediaFromUrl $pokemonData.cries.legacy "cry_legacy.ogg" $pokemonApiId $dataDir $pokemonMediaDir) {
                $mediaPaths.cryLegacyPath = Get-AssetPath "media/pokemon/$pokemonApiId/cry_legacy.ogg"
            }
        }
    }
    
    return $mediaPaths
}

# Función para procesar y copiar archivos multimedia de items
function Process-ItemMedia($itemApiId, $itemData, $dataDir, $mediaDir) {
    $itemSourceDir = Join-Path $dataDir "item\$itemApiId"
    $itemMediaDir = Join-Path $mediaDir "item\$itemApiId"
    
    if (-not (Test-Path $itemSourceDir)) {
        return
    }
    
    if (-not (Test-Path $itemMediaDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $itemMediaDir | Out-Null
        } catch {
            return
        }
    }
    
    # Procesar sprites de items
    if ($itemData.sprites) {
        $sprites = $itemData.sprites
        
        # default sprite
        if ($sprites.default) {
            Copy-MediaFromUrl $sprites.default "sprite_default.png" $itemApiId $dataDir $itemMediaDir | Out-Null
        }
    }
}

# Función para procesar y copiar archivos multimedia de pokemon-form
function Process-PokemonFormMedia($formApiId, $formData, $dataDir, $mediaDir) {
    $formSourceDir = Join-Path $dataDir "pokemon-form\$formApiId"
    $formMediaDir = Join-Path $mediaDir "pokemon-form\$formApiId"
    
    if (-not (Test-Path $formSourceDir)) {
        return
    }
    
    if (-not (Test-Path $formMediaDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $formMediaDir | Out-Null
        } catch {
            return
        }
    }
    
    # Procesar sprites de formas
    if ($formData.sprites) {
        $sprites = $formData.sprites
        
        # front_default
        if ($sprites.front_default) {
            Copy-MediaFromUrl $sprites.front_default "sprite_front_default.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # front_shiny
        if ($sprites.front_shiny) {
            Copy-MediaFromUrl $sprites.front_shiny "sprite_front_shiny.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # back_default
        if ($sprites.back_default) {
            Copy-MediaFromUrl $sprites.back_default "sprite_back_default.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # back_shiny
        if ($sprites.back_shiny) {
            Copy-MediaFromUrl $sprites.back_shiny "sprite_back_shiny.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
    }
}

# Función para procesar y copiar archivos multimedia de form
function Process-FormMedia($formApiId, $formData, $dataDir, $mediaDir) {
    $formSourceDir = Join-Path $dataDir "form\$formApiId"
    $formMediaDir = Join-Path $mediaDir "form\$formApiId"
    
    if (-not (Test-Path $formSourceDir)) {
        return
    }
    
    if (-not (Test-Path $formMediaDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $formMediaDir | Out-Null
        } catch {
            return
        }
    }
    
    # Procesar sprites de formas
    if ($formData.sprites) {
        $sprites = $formData.sprites
        
        # front_default
        if ($sprites.front_default) {
            Copy-MediaFromUrl $sprites.front_default "sprite_front_default.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # front_shiny
        if ($sprites.front_shiny) {
            Copy-MediaFromUrl $sprites.front_shiny "sprite_front_shiny.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # back_default
        if ($sprites.back_default) {
            Copy-MediaFromUrl $sprites.back_default "sprite_back_default.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
        
        # back_shiny
        if ($sprites.back_shiny) {
            Copy-MediaFromUrl $sprites.back_shiny "sprite_back_shiny.png" $formApiId $dataDir $formMediaDir | Out-Null
        }
    }
}

function Get-TypeColor($typeName) {
    $normalized = $typeName.ToLower()
    if ($TypeColors.ContainsKey($normalized)) {
        return $TypeColors[$normalized]
    }
    return $null
}

function Get-PokedexColor($index) {
    if ($index -lt $PastelColors.Count) {
        return $PastelColors[$index]
    }
    
    $r = 180 + (Get-Random -Maximum 76)
    $g = 180 + (Get-Random -Maximum 76)
    $b = 180 + (Get-Random -Maximum 76)
    return "#$($r.ToString('X2'))$($g.ToString('X2'))$($b.ToString('X2'))"
}

# ============================================================
# FUNCIONES DE GENERACIÓN CSV POR TABLA
# ============================================================

function Generate-LanguagesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;official_name;iso639;iso3166"
    $rows += $header
    
    $languagesPath = Join-Path $dataDir "language"
    if (-not (Test-Path $languagesPath)) {
        return $rows
    }
    
    $langDirs = Get-ChildItem -Path $languagesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($langDir in $langDirs) {
        $dataJson = Join-Path $langDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "languages" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.official);$(Escape-CsvValue $data.iso639);$(Escape-CsvValue $data.iso3166)"
        $rows += $row
    }
    
    return $rows
}

function Generate-GenerationsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;main_region_id"
    $rows += $header
    
    $gensPath = Join-Path $dataDir "generation"
    if (-not (Test-Path $gensPath)) {
        return $rows
    }
    
    $genDirs = Get-ChildItem -Path $gensPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($genDir in $genDirs) {
        $dataJson = Join-Path $genDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "generations" $apiId
        
        $mainRegionId = $null
        if ($data.main_region) {
            $mainRegionApiId = Get-ApiIdFromUrl $data.main_region.url
            $mainRegionId = Get-DbId "regions" $mainRegionApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $mainRegionId)"
        $rows += $row
    }
    
    return $rows
}

function Generate-RegionsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;main_generation_id;locations_json;pokedexes_json;version_groups_json"
    $rows += $header
    
    $regionsPath = Join-Path $dataDir "region"
    if (-not (Test-Path $regionsPath)) {
        return $rows
    }
    
    $regionDirs = Get-ChildItem -Path $regionsPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($regionDir in $regionDirs) {
        $dataJson = Join-Path $regionDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "regions" $apiId
        
        $mainGenId = $null
        if ($data.main_generation) {
            $mainGenApiId = Get-ApiIdFromUrl $data.main_generation.url
            $mainGenId = Get-DbId "generations" $mainGenApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $mainGenId);$(Escape-CsvJson $data.locations);$(Escape-CsvJson $data.pokedexes);$(Escape-CsvJson $data.version_groups)"
        $rows += $row
    }
    
    # Añadir región Nacional (especial)
    $nationalApiId = 9999
    $nationalDbId = Get-DbId "regions" $nationalApiId
    $row = "$nationalDbId;$nationalApiId;Nacional;;;"
    $rows += $row
    
    return $rows
}

function Generate-TypesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;generation_id;move_damage_class_id;color;damage_relations_json"
    $rows += $header
    
    $typesPath = Join-Path $dataDir "type"
    if (-not (Test-Path $typesPath)) {
        return $rows
    }
    
    $typeDirs = Get-ChildItem -Path $typesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($typeDir in $typeDirs) {
        $dataJson = Join-Path $typeDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "types" $apiId
        
        $genId = $null
        if ($data.generation) {
            $genApiId = Get-ApiIdFromUrl $data.generation.url
            $genId = Get-DbId "generations" $genApiId
        }
        
        $damageClassId = $null
        if ($data.move_damage_class) {
            $damageClassApiId = Get-ApiIdFromUrl $data.move_damage_class.url
            $damageClassId = Get-DbId "moveDamageClasses" $damageClassApiId
        }
        
        $color = Get-TypeColor $data.name
        if ($null -eq $color -and $data.PSObject.Properties['processed_color']) {
            $color = $data.processed_color
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $genId);$(Escape-CsvValue $damageClassId);$(Escape-CsvValue $color);$(Escape-CsvJson $data.damage_relations)"
        $rows += $row
    }
    
    return $rows
}

function Generate-TypeDamageRelationsCsv($dataDir) {
    $rows = @()
    $header = "attacking_type_id;defending_type_id;relation_type"
    $rows += $header
    
    $typesPath = Join-Path $dataDir "type"
    if (-not (Test-Path $typesPath)) {
        return $rows
    }
    
    $typeDirs = Get-ChildItem -Path $typesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($typeDir in $typeDirs) {
        $dataJson = Join-Path $typeDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $typeApiId = $data.id
        $typeDbId = Get-DbId "types" $typeApiId
        
        if ($data.damage_relations) {
            $relations = $data.damage_relations
            
            # double_damage_to
            if ($relations.double_damage_to) {
                foreach ($target in $relations.double_damage_to) {
                    $targetApiId = Get-ApiIdFromUrl $target.url
                    $targetDbId = Get-DbId "types" $targetApiId
                    $row = "$typeDbId;$targetDbId;double_damage_to"
                    $rows += $row
                }
            }
            
            # half_damage_to
            if ($relations.half_damage_to) {
                foreach ($target in $relations.half_damage_to) {
                    $targetApiId = Get-ApiIdFromUrl $target.url
                    $targetDbId = Get-DbId "types" $targetApiId
                    $row = "$typeDbId;$targetDbId;half_damage_to"
                    $rows += $row
                }
            }
            
            # no_damage_to
            if ($relations.no_damage_to) {
                foreach ($target in $relations.no_damage_to) {
                    $targetApiId = Get-ApiIdFromUrl $target.url
                    $targetDbId = Get-DbId "types" $targetApiId
                    $row = "$typeDbId;$targetDbId;no_damage_to"
                    $rows += $row
                }
            }
            
            # double_damage_from
            if ($relations.double_damage_from) {
                foreach ($attacker in $relations.double_damage_from) {
                    $attackerApiId = Get-ApiIdFromUrl $attacker.url
                    $attackerDbId = Get-DbId "types" $attackerApiId
                    $row = "$attackerDbId;$typeDbId;double_damage_from"
                    $rows += $row
                }
            }
            
            # half_damage_from
            if ($relations.half_damage_from) {
                foreach ($attacker in $relations.half_damage_from) {
                    $attackerApiId = Get-ApiIdFromUrl $attacker.url
                    $attackerDbId = Get-DbId "types" $attackerApiId
                    $row = "$attackerDbId;$typeDbId;half_damage_from"
                    $rows += $row
                }
            }
            
            # no_damage_from
            if ($relations.no_damage_from) {
                foreach ($attacker in $relations.no_damage_from) {
                    $attackerApiId = Get-ApiIdFromUrl $attacker.url
                    $attackerDbId = Get-DbId "types" $attackerApiId
                    $row = "$attackerDbId;$typeDbId;no_damage_from"
                    $rows += $row
                }
            }
        }
    }
    
    return $rows
}

function Generate-StatsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;game_index;is_battle_only;move_damage_class_id"
    $rows += $header
    
    $statsPath = Join-Path $dataDir "stat"
    if (-not (Test-Path $statsPath)) {
        return $rows
    }
    
    $statDirs = Get-ChildItem -Path $statsPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($statDir in $statDirs) {
        $dataJson = Join-Path $statDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "stats" $apiId
        
        $damageClassId = $null
        if ($data.move_damage_class) {
            $damageClassApiId = Get-ApiIdFromUrl $data.move_damage_class.url
            $damageClassId = Get-DbId "moveDamageClasses" $damageClassApiId
        }
        
        $isBattleOnly = if ($data.is_battle_only) { 1 } else { 0 }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.game_index);$isBattleOnly;$(Escape-CsvValue $damageClassId)"
        $rows += $row
    }
    
    return $rows
}

function Generate-VersionGroupsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;generation_id;order"
    $rows += $header
    
    $vgPath = Join-Path $dataDir "version-group"
    if (-not (Test-Path $vgPath)) {
        return $rows
    }
    
    $vgDirs = Get-ChildItem -Path $vgPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($vgDir in $vgDirs) {
        $dataJson = Join-Path $vgDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "versionGroups" $apiId
        
        $genId = $null
        if ($data.generation) {
            $genApiId = Get-ApiIdFromUrl $data.generation.url
            $genId = Get-DbId "generations" $genApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $genId);$(Escape-CsvValue $data.order)"
        $rows += $row
    }
    
    return $rows
}

function Generate-MoveDamageClassesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $mdcPath = Join-Path $dataDir "move-damage-class"
    if (-not (Test-Path $mdcPath)) {
        return $rows
    }
    
    $mdcDirs = Get-ChildItem -Path $mdcPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($mdcDir in $mdcDirs) {
        $dataJson = Join-Path $mdcDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "moveDamageClasses" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-AbilitiesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;is_main_series;generation_id;full_data_json"
    $rows += $header
    
    $abilitiesPath = Join-Path $dataDir "ability"
    if (-not (Test-Path $abilitiesPath)) {
        return $rows
    }
    
    $abilityDirs = Get-ChildItem -Path $abilitiesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($abilityDir in $abilityDirs) {
        $dataJson = Join-Path $abilityDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "abilities" $apiId
        
        $genId = $null
        if ($data.generation) {
            $genApiId = Get-ApiIdFromUrl $data.generation.url
            $genId = Get-DbId "generations" $genApiId
        }
        
        $isMainSeries = if ($data.is_main_series) { 1 } else { 0 }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$isMainSeries;$(Escape-CsvValue $genId);$(Escape-CsvJson $data)"
        $rows += $row
    }
    
    return $rows
}

function Generate-MovesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;accuracy;effect_chance;pp;priority;power;type_id;damage_class_id;generation_id;full_data_json"
    $rows += $header
    
    $movesPath = Join-Path $dataDir "move"
    if (-not (Test-Path $movesPath)) {
        return $rows
    }
    
    $moveDirs = Get-ChildItem -Path $movesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($moveDir in $moveDirs) {
        $dataJson = Join-Path $moveDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "moves" $apiId
        
        $typeId = $null
        if ($data.type) {
            $typeApiId = Get-ApiIdFromUrl $data.type.url
            $typeId = Get-DbId "types" $typeApiId
        }
        
        $damageClassId = $null
        if ($data.damage_class) {
            $damageClassApiId = Get-ApiIdFromUrl $data.damage_class.url
            $damageClassId = Get-DbId "moveDamageClasses" $damageClassApiId
        }
        
        $genId = $null
        if ($data.generation) {
            $genApiId = Get-ApiIdFromUrl $data.generation.url
            $genId = Get-DbId "generations" $genApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.accuracy);$(Escape-CsvValue $data.effect_chance);$(Escape-CsvValue $data.pp);$(Escape-CsvValue $data.priority);$(Escape-CsvValue $data.power);$(Escape-CsvValue $typeId);$(Escape-CsvValue $damageClassId);$(Escape-CsvValue $genId);$(Escape-CsvJson $data)"
        $rows += $row
    }
    
    return $rows
}

function Generate-ItemPocketsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $ipPath = Join-Path $dataDir "item-pocket"
    if (-not (Test-Path $ipPath)) {
        return $rows
    }
    
    $ipDirs = Get-ChildItem -Path $ipPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($ipDir in $ipDirs) {
        $dataJson = Join-Path $ipDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "itemPockets" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-ItemCategoriesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;pocket_id"
    $rows += $header
    
    $icPath = Join-Path $dataDir "item-category"
    if (-not (Test-Path $icPath)) {
        return $rows
    }
    
    $icDirs = Get-ChildItem -Path $icPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($icDir in $icDirs) {
        $dataJson = Join-Path $icDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "itemCategories" $apiId
        
        $pocketId = $null
        if ($data.pocket) {
            $pocketApiId = Get-ApiIdFromUrl $data.pocket.url
            $pocketId = Get-DbId "itemPockets" $pocketApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $pocketId)"
        $rows += $row
    }
    
    return $rows
}

function Generate-ItemsCsv($dataDir, $mediaDir) {
    $rows = @()
    $header = "id;api_id;name;cost;fling_power;category_id;fling_effect_id;full_data_json"
    $rows += $header
    
    $itemsPath = Join-Path $dataDir "item"
    if (-not (Test-Path $itemsPath)) {
        return $rows
    }
    
    $itemDirs = Get-ChildItem -Path $itemsPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($itemDir in $itemDirs) {
        $dataJson = Join-Path $itemDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "items" $apiId
        
        # Procesar multimedia de items
        Process-ItemMedia $apiId $data $dataDir $mediaDir
        
        $categoryId = $null
        if ($data.category) {
            $categoryApiId = Get-ApiIdFromUrl $data.category.url
            $categoryId = Get-DbId "itemCategories" $categoryApiId
        }
        
        $flingEffectId = $null
        if ($data.fling_effect) {
            $flingEffectApiId = Get-ApiIdFromUrl $data.fling_effect.url
            # Nota: item-fling-effect no está en las tablas, se guarda en JSON
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.cost);$(Escape-CsvValue $data.fling_power);$(Escape-CsvValue $categoryId);$(Escape-CsvValue $flingEffectId);$(Escape-CsvJson $data)"
        $rows += $row
    }
    
    return $rows
}

function Generate-EggGroupsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $egPath = Join-Path $dataDir "egg-group"
    if (-not (Test-Path $egPath)) {
        return $rows
    }
    
    $egDirs = Get-ChildItem -Path $egPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($egDir in $egDirs) {
        $dataJson = Join-Path $egDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "eggGroups" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-GrowthRatesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;formula"
    $rows += $header
    
    $grPath = Join-Path $dataDir "growth-rate"
    if (-not (Test-Path $grPath)) {
        return $rows
    }
    
    $grDirs = Get-ChildItem -Path $grPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($grDir in $grDirs) {
        $dataJson = Join-Path $grDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "growthRates" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.formula)"
        $rows += $row
    }
    
    return $rows
}

function Generate-NaturesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;decreased_stat_id;increased_stat_id;hates_flavor_id;likes_flavor_id"
    $rows += $header
    
    $naturesPath = Join-Path $dataDir "nature"
    if (-not (Test-Path $naturesPath)) {
        return $rows
    }
    
    $natureDirs = Get-ChildItem -Path $naturesPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($natureDir in $natureDirs) {
        $dataJson = Join-Path $natureDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "natures" $apiId
        
        $decreasedStatId = $null
        if ($data.decreased_stat) {
            $decreasedStatApiId = Get-ApiIdFromUrl $data.decreased_stat.url
            $decreasedStatId = Get-DbId "stats" $decreasedStatApiId
        }
        
        $increasedStatId = $null
        if ($data.increased_stat) {
            $increasedStatApiId = Get-ApiIdFromUrl $data.increased_stat.url
            $increasedStatId = Get-DbId "stats" $increasedStatApiId
        }
        
        $hatesFlavorId = $null
        if ($data.hates_flavor) {
            $hatesFlavorApiId = Get-ApiIdFromUrl $data.hates_flavor.url
            # Nota: berry-flavor no está en las tablas, se guarda en JSON
        }
        
        $likesFlavorId = $null
        if ($data.likes_flavor) {
            $likesFlavorApiId = Get-ApiIdFromUrl $data.likes_flavor.url
            # Nota: berry-flavor no está en las tablas, se guarda en JSON
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $decreasedStatId);$(Escape-CsvValue $increasedStatId);$(Escape-CsvValue $hatesFlavorId);$(Escape-CsvValue $likesFlavorId)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokemonColorsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $pcPath = Join-Path $dataDir "pokemon-color"
    if (-not (Test-Path $pcPath)) {
        return $rows
    }
    
    $pcDirs = Get-ChildItem -Path $pcPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($pcDir in $pcDirs) {
        $dataJson = Join-Path $pcDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "pokemonColors" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokemonShapesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $psPath = Join-Path $dataDir "pokemon-shape"
    if (-not (Test-Path $psPath)) {
        return $rows
    }
    
    $psDirs = Get-ChildItem -Path $psPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($psDir in $psDirs) {
        $dataJson = Join-Path $psDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "pokemonShapes" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokemonHabitatsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name"
    $rows += $header
    
    $phPath = Join-Path $dataDir "pokemon-habitat"
    if (-not (Test-Path $phPath)) {
        return $rows
    }
    
    $phDirs = Get-ChildItem -Path $phPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($phDir in $phDirs) {
        $dataJson = Join-Path $phDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "pokemonHabitats" $apiId
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name)"
        $rows += $row
    }
    
    return $rows
}

function Generate-EvolutionChainsCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;baby_trigger_item_id;chain_json"
    $rows += $header
    
    $ecPath = Join-Path $dataDir "evolution-chain"
    if (-not (Test-Path $ecPath)) {
        return $rows
    }
    
    $ecDirs = Get-ChildItem -Path $ecPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($ecDir in $ecDirs) {
        $dataJson = Join-Path $ecDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "evolutionChains" $apiId
        
        $babyTriggerItemId = $null
        if ($data.baby_trigger_item) {
            $babyTriggerItemApiId = Get-ApiIdFromUrl $data.baby_trigger_item.url
            $babyTriggerItemId = Get-DbId "items" $babyTriggerItemApiId
        }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $babyTriggerItemId);$(Escape-CsvJson $data.chain)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokemonSpeciesCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;order;gender_rate;capture_rate;base_happiness;is_baby;is_legendary;is_mythical;hatch_counter;has_gender_differences;forms_switchable;growth_rate_id;color_id;shape_id;habitat_id;generation_id;evolves_from_species_id;evolution_chain_id;egg_groups_json;flavor_text_entries_json;form_descriptions_json;varieties_json;genera_json"
    $rows += $header
    
    $psPath = Join-Path $dataDir "pokemon-species"
    if (-not (Test-Path $psPath)) {
        return $rows
    }
    
    $psDirs = Get-ChildItem -Path $psPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($psDir in $psDirs) {
        $dataJson = Join-Path $psDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "pokemonSpecies" $apiId
        
        $growthRateId = $null
        if ($data.growth_rate) {
            $growthRateApiId = Get-ApiIdFromUrl $data.growth_rate.url
            $growthRateId = Get-DbId "growthRates" $growthRateApiId
        }
        
        $colorId = $null
        if ($data.color) {
            $colorApiId = Get-ApiIdFromUrl $data.color.url
            $colorId = Get-DbId "pokemonColors" $colorApiId
        }
        
        $shapeId = $null
        if ($data.shape) {
            $shapeApiId = Get-ApiIdFromUrl $data.shape.url
            $shapeId = Get-DbId "pokemonShapes" $shapeApiId
        }
        
        $habitatId = $null
        if ($data.habitat) {
            $habitatApiId = Get-ApiIdFromUrl $data.habitat.url
            $habitatId = Get-DbId "pokemonHabitats" $habitatApiId
        }
        
        $genId = $null
        if ($data.generation) {
            $genApiId = Get-ApiIdFromUrl $data.generation.url
            $genId = Get-DbId "generations" $genApiId
        }
        
        $evolvesFromSpeciesId = $null
        if ($data.evolves_from_species) {
            $evolvesFromApiId = Get-ApiIdFromUrl $data.evolves_from_species.url
            $evolvesFromSpeciesId = Get-DbId "pokemonSpecies" $evolvesFromApiId
        }
        
        $evolutionChainId = $null
        if ($data.evolution_chain) {
            $evolutionChainApiId = Get-ApiIdFromUrl $data.evolution_chain.url
            $evolutionChainId = Get-DbId "evolutionChains" $evolutionChainApiId
        }
        
        $isBaby = if ($data.is_baby) { 1 } else { 0 }
        $isLegendary = if ($data.is_legendary) { 1 } else { 0 }
        $isMythical = if ($data.is_mythical) { 1 } else { 0 }
        $hasGenderDifferences = if ($data.has_gender_differences) { 1 } else { 0 }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$(Escape-CsvValue $data.order);$(Escape-CsvValue $data.gender_rate);$(Escape-CsvValue $data.capture_rate);$(Escape-CsvValue $data.base_happiness);$isBaby;$isLegendary;$isMythical;$(Escape-CsvValue $data.hatch_counter);$hasGenderDifferences;$(Escape-CsvValue $data.forms_switchable);$(Escape-CsvValue $growthRateId);$(Escape-CsvValue $colorId);$(Escape-CsvValue $shapeId);$(Escape-CsvValue $habitatId);$(Escape-CsvValue $genId);$(Escape-CsvValue $evolvesFromSpeciesId);$(Escape-CsvValue $evolutionChainId);$(Escape-CsvJson $data.egg_groups);$(Escape-CsvJson $data.flavor_text_entries);$(Escape-CsvJson $data.form_descriptions);$(Escape-CsvJson $data.varieties);$(Escape-CsvJson $data.genera)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokedexCsv($dataDir) {
    $rows = @()
    $header = "id;api_id;name;is_main_series;region_id;color;descriptions_json;pokemon_entries_json"
    $rows += $header
    
    $pokedexPath = Join-Path $dataDir "pokedex"
    if (-not (Test-Path $pokedexPath)) {
        return $rows
    }
    
    $pokedexDirs = Get-ChildItem -Path $pokedexPath -Directory | Sort-Object { [int]($_.Name) }
    $pokedexIndex = 0
    
    foreach ($pokedexDir in $pokedexDirs) {
        $dataJson = Join-Path $pokedexDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $apiId = $data.id
        $dbId = Get-DbId "pokedex" $apiId
        
        $regionId = $null
        if ($data.region) {
            $regionApiId = Get-ApiIdFromUrl $data.region.url
            $regionId = Get-DbId "regions" $regionApiId
        }
        
        $color = Get-PokedexColor $pokedexIndex
        if ($null -eq $color -and $data.PSObject.Properties['processed_color']) {
            $color = $data.processed_color
        }
        
        $isMainSeries = if ($data.is_main_series) { 1 } else { 0 }
        
        $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$isMainSeries;$(Escape-CsvValue $regionId);$(Escape-CsvValue $color);$(Escape-CsvJson $data.descriptions);$(Escape-CsvJson $data.pokemon_entries)"
        $rows += $row
        
        $pokedexIndex++
    }
    
    # Añadir pokedex Nacional (especial)
    $nationalPokedexApiId = 1
    $nationalPokedexDbId = Get-DbId "pokedex" $nationalPokedexApiId
    $nationalRegionDbId = Get-DbId "regions" 9999
    $nationalColor = Get-PokedexColor 0
    
    $nationalPokedexPath = Join-Path $pokedexPath "1\data.json"
    if (Test-Path $nationalPokedexPath) {
        $nationalData = Get-Content $nationalPokedexPath -Raw | ConvertFrom-Json
        $row = "$nationalPokedexDbId;$nationalPokedexApiId;national;1;$nationalRegionDbId;$(Escape-CsvValue $nationalColor);$(Escape-CsvJson $nationalData.descriptions);$(Escape-CsvJson $nationalData.pokemon_entries)"
        $rows += $row
    }
    
    return $rows
}

function Generate-PokemonCsv($dataDir, $mediaDir) {
    $rows = @()
    # NOTA: Eliminamos campos URL y paths locales, solo dejamos referencias a assets
    $header = "id;api_id;name;species_id;base_experience;height;weight;is_default;order;location_area_encounters;abilities_json;forms_json;game_indices_json;held_items_json;moves_json;sprites_json;stats_json;types_json;cries_json;sprite_front_default_path;sprite_front_shiny_path;sprite_back_default_path;sprite_back_shiny_path;artwork_official_path;artwork_official_shiny_path;cry_latest_path;cry_legacy_path"
    $rows += $header
    
    $pokemonPath = Join-Path $dataDir "pokemon"
    if (-not (Test-Path $pokemonPath)) {
        return $rows
    }
    
    $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory | Sort-Object { [int]($_.Name) }
    $processed = 0
    $total = $pokemonDirs.Count
    
    foreach ($pokemonDir in $pokemonDirs) {
        $dataJson = Join-Path $pokemonDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $processed++
        if ($processed % 100 -eq 0) {
            Write-Host "  Procesando pokemon $processed/$total..." -ForegroundColor DarkGray
        }
        
        try {
            $jsonContent = Get-Content $dataJson -Raw
            $data = $jsonContent | ConvertFrom-Json
            $apiId = $data.id
            $dbId = Get-DbId "pokemon" $apiId
            
            $speciesId = $null
            if ($data.species) {
                $speciesApiId = Get-ApiIdFromUrl $data.species.url
                $speciesId = Get-DbId "pokemonSpecies" $speciesApiId
            }
            
            if ($null -eq $speciesId) {
                Write-Warning "  [AVISO] Pokemon $apiId no tiene species, saltando..."
                continue
            }
            
            # Procesar multimedia y obtener rutas de assets
            $mediaPaths = Process-PokemonMedia $apiId $data $dataDir $mediaDir
            
            $isDefault = if ($data.is_default) { 1 } else { 0 }
            
            $row = "$dbId;$apiId;$(Escape-CsvValue $data.name);$speciesId;$(Escape-CsvValue $data.base_experience);$(Escape-CsvValue $data.height);$(Escape-CsvValue $data.weight);$isDefault;$(Escape-CsvValue $data.order);$(Escape-CsvValue $data.location_area_encounters);$(Escape-CsvJson $data.abilities);$(Escape-CsvJson $data.forms);$(Escape-CsvJson $data.game_indices);$(Escape-CsvJson $data.held_items);$(Escape-CsvJson $data.moves);$(Escape-CsvJson $data.sprites);$(Escape-CsvJson $data.stats);$(Escape-CsvJson $data.types);$(Escape-CsvJson $data.cries);$(Escape-CsvValue $mediaPaths.spriteFrontDefaultPath);$(Escape-CsvValue $mediaPaths.spriteFrontShinyPath);$(Escape-CsvValue $mediaPaths.spriteBackDefaultPath);$(Escape-CsvValue $mediaPaths.spriteBackShinyPath);$(Escape-CsvValue $mediaPaths.artworkOfficialPath);$(Escape-CsvValue $mediaPaths.artworkOfficialShinyPath);$(Escape-CsvValue $mediaPaths.cryLatestPath);$(Escape-CsvValue $mediaPaths.cryLegacyPath)"
            $rows += $row
            
            $data = $null
            $jsonContent = $null
            if ($processed % 200 -eq 0) {
                [System.GC]::Collect()
            }
        } catch {
            Write-Warning "  [AVISO] Error procesando pokemon $($pokemonDir.Name): $_"
            continue
        }
    }
    
    return $rows
}

function Generate-PokemonTypesCsv($dataDir) {
    $rows = @()
    $header = "pokemon_id;type_id;slot"
    $rows += $header
    
    $pokemonPath = Join-Path $dataDir "pokemon"
    if (-not (Test-Path $pokemonPath)) {
        return $rows
    }
    
    $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($pokemonDir in $pokemonDirs) {
        $dataJson = Join-Path $pokemonDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $pokemonApiId = $data.id
        $pokemonDbId = Get-DbId "pokemon" $pokemonApiId
        
        if ($data.types) {
            foreach ($typeEntry in $data.types) {
                $typeInfo = $typeEntry.type
                $slot = $typeEntry.slot
                
                if ($typeInfo -and $slot) {
                    $typeApiId = Get-ApiIdFromUrl $typeInfo.url
                    $typeDbId = Get-DbId "types" $typeApiId
                    
                    $row = "$pokemonDbId;$typeDbId;$slot"
                    $rows += $row
                }
            }
        }
    }
    
    return $rows
}

function Generate-PokemonAbilitiesCsv($dataDir) {
    $rows = @()
    $header = "pokemon_id;ability_id;is_hidden;slot"
    $rows += $header
    
    $pokemonPath = Join-Path $dataDir "pokemon"
    if (-not (Test-Path $pokemonPath)) {
        return $rows
    }
    
    $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($pokemonDir in $pokemonDirs) {
        $dataJson = Join-Path $pokemonDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $pokemonApiId = $data.id
        $pokemonDbId = Get-DbId "pokemon" $pokemonApiId
        
        if ($data.abilities) {
            foreach ($abilityEntry in $data.abilities) {
                $abilityInfo = $abilityEntry.ability
                $isHidden = if ($abilityEntry.is_hidden) { 1 } else { 0 }
                $slot = $abilityEntry.slot
                
                if ($abilityInfo -and $slot) {
                    $abilityApiId = Get-ApiIdFromUrl $abilityInfo.url
                    $abilityDbId = Get-DbId "abilities" $abilityApiId
                    
                    $row = "$pokemonDbId;$abilityDbId;$isHidden;$slot"
                    $rows += $row
                }
            }
        }
    }
    
    return $rows
}

function Generate-PokemonMovesCsv($dataDir) {
    # Usar ArrayList para mejor rendimiento (evita recrear arrays)
    $rows = New-Object System.Collections.ArrayList
    $null = $rows.Add("pokemon_id;move_id;version_group_id;learn_method;level")
    
    $pokemonPath = Join-Path $dataDir "pokemon"
    if (-not (Test-Path $pokemonPath)) {
        return $rows
    }
    
    $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory | Sort-Object { [int]($_.Name) }
    $total = $pokemonDirs.Count
    $processed = 0
    $rowCount = 0
    
    Write-Host "  Procesando $total pokemon..." -ForegroundColor Cyan
    
    foreach ($pokemonDir in $pokemonDirs) {
        $dataJson = Join-Path $pokemonDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $processed++
        if ($processed % 50 -eq 0) {
            Write-Host "  Progreso: $processed/$total pokemon procesados, $rowCount filas generadas..." -ForegroundColor DarkGray
        }
        
        try {
            # Leer JSON de forma más eficiente
            $jsonContent = [System.IO.File]::ReadAllText($dataJson)
            $data = $jsonContent | ConvertFrom-Json
            $pokemonApiId = $data.id
            $pokemonDbId = Get-DbId "pokemon" $pokemonApiId
            
            if ($data.moves) {
                foreach ($moveEntry in $data.moves) {
                    $moveInfo = $moveEntry.move
                    
                    if ($null -eq $moveInfo) { continue }
                    
                    $moveApiId = Get-ApiIdFromUrl $moveInfo.url
                    if ($null -eq $moveApiId) { continue }
                    
                    $moveDbId = Get-DbId "moves" $moveApiId
                    
                    if ($moveEntry.version_group_details) {
                        foreach ($vgDetail in $moveEntry.version_group_details) {
                            $versionGroupInfo = $vgDetail.version_group
                            if ($null -eq $versionGroupInfo) { continue }
                            
                            $learnMethod = $null
                            if ($vgDetail.move_learn_method) {
                                $learnMethod = $vgDetail.move_learn_method.name
                            }
                            
                            $level = $null
                            if ($vgDetail.PSObject.Properties['level_learned_at']) {
                                $level = $vgDetail.level_learned_at
                            }
                            
                            $vgApiId = Get-ApiIdFromUrl $versionGroupInfo.url
                            if ($null -eq $vgApiId) { continue }
                            
                            $vgDbId = Get-DbId "versionGroups" $vgApiId
                            
                            $levelValue = if ($level -and $level -gt 0) { $level } else { '' }
                            $vgValue = if ($vgDbId) { $vgDbId } else { '' }
                            $row = "$pokemonDbId;$moveDbId;$vgValue;$(Escape-CsvValue $learnMethod);$levelValue"
                            $null = $rows.Add($row)
                            $rowCount++
                        }
                    }
                }
            }
            
            # Limpiar referencias
            $data = $null
            $jsonContent = $null
            
            # Garbage collection cada 100 pokemon (más frecuente)
            if ($processed % 100 -eq 0) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        } catch {
            Write-Warning "  [AVISO] Error procesando pokemon $($pokemonDir.Name): $_"
            continue
        }
    }
    
    Write-Host "  [OK] PokemonMoves completado: $rowCount filas generadas" -ForegroundColor DarkGreen
    return $rows
}

function Generate-PokedexEntriesCsv($dataDir) {
    $rows = @()
    $header = "pokedex_id;pokemon_species_id;entry_number"
    $rows += $header
    
    $pokedexPath = Join-Path $dataDir "pokedex"
    if (-not (Test-Path $pokedexPath)) {
        return $rows
    }
    
    $pokedexDirs = Get-ChildItem -Path $pokedexPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($pokedexDir in $pokedexDirs) {
        $dataJson = Join-Path $pokedexDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        $pokedexApiId = $data.id
        $pokedexDbId = Get-DbId "pokedex" $pokedexApiId
        
        if ($data.pokemon_entries) {
            foreach ($entry in $data.pokemon_entries) {
                $speciesInfo = $entry.pokemon_species
                $entryNumber = $entry.entry_number
                
                if ($speciesInfo -and $entryNumber) {
                    $speciesApiId = Get-ApiIdFromUrl $speciesInfo.url
                    $speciesDbId = Get-DbId "pokemonSpecies" $speciesApiId
                    
                    $row = "$pokedexDbId;$speciesDbId;$entryNumber"
                    $rows += $row
                }
            }
        }
    }
    
    # Añadir entradas de pokedex nacional
    $nationalPokedexDbId = Get-DbId "pokedex" 1
    $nationalPokedexPath = Join-Path $pokedexPath "1\data.json"
    if (Test-Path $nationalPokedexPath) {
        $nationalData = Get-Content $nationalPokedexPath -Raw | ConvertFrom-Json
        if ($nationalData.pokemon_entries) {
            foreach ($entry in $nationalData.pokemon_entries) {
                $speciesInfo = $entry.pokemon_species
                $entryNumber = $entry.entry_number
                
                if ($speciesInfo -and $entryNumber) {
                    $speciesApiId = Get-ApiIdFromUrl $speciesInfo.url
                    $speciesDbId = Get-DbId "pokemonSpecies" $speciesApiId
                    
                    $row = "$nationalPokedexDbId;$speciesDbId;$entryNumber"
                    $rows += $row
                }
            }
        }
    }
    
    return $rows
}

function Generate-PokemonVariantsCsv($dataDir) {
    $rows = @()
    $header = "pokemon_id;variant_pokemon_id"
    $rows += $header
    
    $psPath = Join-Path $dataDir "pokemon-species"
    if (-not (Test-Path $psPath)) {
        return $rows
    }
    
    $psDirs = Get-ChildItem -Path $psPath -Directory | Sort-Object { [int]($_.Name) }
    
    foreach ($psDir in $psDirs) {
        $dataJson = Join-Path $psDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $data = Get-Content $dataJson -Raw | ConvertFrom-Json
        
        if ($data.varieties) {
            $defaultPokemon = $null
            $variants = @()
            
            foreach ($variety in $data.varieties) {
                $isDefault = if ($variety.is_default) { 1 } else { 0 }
                $pokemonInfo = $variety.pokemon
                
                if ($pokemonInfo) {
                    $pokemonApiId = Get-ApiIdFromUrl $pokemonInfo.url
                    $pokemonDbId = Get-DbId "pokemon" $pokemonApiId
                    
                    if ($isDefault) {
                        $defaultPokemon = $pokemonDbId
                    } else {
                        $variants += $pokemonDbId
                    }
                }
            }
            
            if ($defaultPokemon -and $variants.Count -gt 0) {
                foreach ($variantDbId in $variants) {
                    $row = "$defaultPokemon;$variantDbId"
                    $rows += $row
                }
            }
        }
    }
    
    return $rows
}

function Generate-LocalizedNamesCsv($dataDir) {
    $rows = @()
    $header = "entity_type;entity_id;language_id;name"
    $rows += $header
    
    # Procesar nombres localizados de regions
    $regionsPath = Join-Path $dataDir "region"
    if (Test-Path $regionsPath) {
        $regionDirs = Get-ChildItem -Path $regionsPath -Directory | Sort-Object { [int]($_.Name) }
        
        foreach ($regionDir in $regionDirs) {
            $dataJson = Join-Path $regionDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $regionApiId = $data.id
                $regionDbId = Get-DbId "regions" $regionApiId
                
                if ($data.names) {
                    foreach ($nameEntry in $data.names) {
                        $languageInfo = $nameEntry.language
                        $name = $nameEntry.name
                        
                        if ($languageInfo -and $name) {
                            $languageApiId = Get-ApiIdFromUrl $languageInfo.url
                            $languageDbId = Get-DbId "languages" $languageApiId
                            
                            $row = "region;$regionDbId;$languageDbId;$(Escape-CsvValue $name)"
                            $rows += $row
                        }
                    }
                }
                $data = $null
            } catch {
                Write-Warning "  [AVISO] Error procesando region $($regionDir.Name): $_"
            }
        }
    }
    
    # Procesar nombres localizados de pokemon-species
    $psPath = Join-Path $dataDir "pokemon-species"
    if (Test-Path $psPath) {
        $psDirs = Get-ChildItem -Path $psPath -Directory | Sort-Object { [int]($_.Name) }
        $processed = 0
        $total = $psDirs.Count
        
        foreach ($psDir in $psDirs) {
            $dataJson = Join-Path $psDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            $processed++
            if ($processed % 200 -eq 0) {
                Write-Host "  Procesando nombres localizados de pokemon-species $processed/$total..." -ForegroundColor DarkGray
            }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $speciesApiId = $data.id
                $speciesDbId = Get-DbId "pokemonSpecies" $speciesApiId
                
                if ($data.names) {
                    foreach ($nameEntry in $data.names) {
                        $languageInfo = $nameEntry.language
                        $name = $nameEntry.name
                        
                        if ($languageInfo -and $name) {
                            $languageApiId = Get-ApiIdFromUrl $languageInfo.url
                            $languageDbId = Get-DbId "languages" $languageApiId
                            
                            $row = "pokemon;$speciesDbId;$languageDbId;$(Escape-CsvValue $name)"
                            $rows += $row
                        }
                    }
                }
                $data = $null
                if ($processed % 500 -eq 0) {
                    [System.GC]::Collect()
                }
            } catch {
                Write-Warning "  [AVISO] Error procesando pokemon-species $($psDir.Name): $_"
            }
        }
    }
    
    # Procesar nombres localizados de moves
    $movesPath = Join-Path $dataDir "move"
    if (Test-Path $movesPath) {
        $moveDirs = Get-ChildItem -Path $movesPath -Directory | Sort-Object { [int]($_.Name) }
        
        foreach ($moveDir in $moveDirs) {
            $dataJson = Join-Path $moveDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $moveApiId = $data.id
                $moveDbId = Get-DbId "moves" $moveApiId
                
                if ($data.names) {
                    foreach ($nameEntry in $data.names) {
                        $languageInfo = $nameEntry.language
                        $name = $nameEntry.name
                        
                        if ($languageInfo -and $name) {
                            $languageApiId = Get-ApiIdFromUrl $languageInfo.url
                            $languageDbId = Get-DbId "languages" $languageApiId
                            
                            $row = "move;$moveDbId;$languageDbId;$(Escape-CsvValue $name)"
                            $rows += $row
                        }
                    }
                }
                $data = $null
            } catch {
                Write-Warning "  [AVISO] Error procesando move $($moveDir.Name): $_"
            }
        }
    }
    
    # Procesar nombres localizados de abilities
    $abilitiesPath = Join-Path $dataDir "ability"
    if (Test-Path $abilitiesPath) {
        $abilityDirs = Get-ChildItem -Path $abilitiesPath -Directory | Sort-Object { [int]($_.Name) }
        
        foreach ($abilityDir in $abilityDirs) {
            $dataJson = Join-Path $abilityDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $abilityApiId = $data.id
                $abilityDbId = Get-DbId "abilities" $abilityApiId
                
                if ($data.names) {
                    foreach ($nameEntry in $data.names) {
                        $languageInfo = $nameEntry.language
                        $name = $nameEntry.name
                        
                        if ($languageInfo -and $name) {
                            $languageApiId = Get-ApiIdFromUrl $languageInfo.url
                            $languageDbId = Get-DbId "languages" $abilityApiId
                            
                            $row = "ability;$abilityDbId;$languageDbId;$(Escape-CsvValue $name)"
                            $rows += $row
                        }
                    }
                }
                $data = $null
            } catch {
                Write-Warning "  [AVISO] Error procesando ability $($abilityDir.Name): $_"
            }
        }
    }
    
    return $rows
}

# ============================================================
# SCRIPT PRINCIPAL
# ============================================================

Write-Host "=========================================="
Write-Host "Generador de CSV desde JSONs"
Write-Host "=========================================="
Write-Host "Directorio de datos: $DataDir"
Write-Host "Directorio de salida: $OutputDir"
Write-Host "Directorio de multimedia: $MediaDir"
Write-Host ""

if (-not (Test-Path $DataDir)) {
    Write-Error "El directorio de datos no existe: $DataDir"
    exit 1
}

# Limpiar y crear directorio de salida (assets/database)
if (Test-Path $OutputDir) {
    Write-Host "[INFO] Limpiando directorio de salida: $OutputDir" -ForegroundColor DarkYellow
    Remove-Item -Path $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Write-Host "[OK] Directorio de salida creado: $OutputDir" -ForegroundColor DarkGreen

# Limpiar y crear directorio de multimedia (assets/media)
# Usar el parámetro $MediaDir directamente en lugar de calcularlo
if (Test-Path $MediaDir) {
    Write-Host "[INFO] Limpiando directorio de multimedia: $MediaDir" -ForegroundColor DarkYellow
    Remove-Item -Path $MediaDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $MediaDir | Out-Null
Write-Host "[OK] Directorio de multimedia creado: $MediaDir" -ForegroundColor DarkGreen

Write-Host "[INFO] Generando CSV en archivos separados por tabla..." -ForegroundColor DarkCyan
Write-Host "[INFO] Directorio: $OutputDir" -ForegroundColor DarkYellow
Write-Host "[INFO] Procesando también archivos multimedia de items, pokemon-form y form..." -ForegroundColor DarkCyan
Write-Host ""

# Definir orden de tablas con sus nombres de archivo
$tables = @(
    @{Name="Languages"; File="01_languages.csv"; Func={Generate-LanguagesCsv $DataDir}},
    @{Name="Generations"; File="02_generations.csv"; Func={Generate-GenerationsCsv $DataDir}},
    @{Name="Regions"; File="03_regions.csv"; Func={Generate-RegionsCsv $DataDir}},
    @{Name="Types"; File="04_types.csv"; Func={Generate-TypesCsv $DataDir}},
    @{Name="TypeDamageRelations"; File="05_type_damage_relations.csv"; Func={Generate-TypeDamageRelationsCsv $DataDir}},
    @{Name="Stats"; File="06_stats.csv"; Func={Generate-StatsCsv $DataDir}},
    @{Name="VersionGroups"; File="07_version_groups.csv"; Func={Generate-VersionGroupsCsv $DataDir}},
    @{Name="MoveDamageClasses"; File="08_move_damage_classes.csv"; Func={Generate-MoveDamageClassesCsv $DataDir}},
    @{Name="Abilities"; File="09_abilities.csv"; Func={Generate-AbilitiesCsv $DataDir}},
    @{Name="Moves"; File="10_moves.csv"; Func={Generate-MovesCsv $DataDir}},
    @{Name="ItemPockets"; File="11_item_pockets.csv"; Func={Generate-ItemPocketsCsv $DataDir}},
    @{Name="ItemCategories"; File="12_item_categories.csv"; Func={Generate-ItemCategoriesCsv $DataDir}},
    @{Name="Items"; File="13_items.csv"; Func={Generate-ItemsCsv $DataDir $MediaDir}},
    @{Name="EggGroups"; File="14_egg_groups.csv"; Func={Generate-EggGroupsCsv $DataDir}},
    @{Name="GrowthRates"; File="15_growth_rates.csv"; Func={Generate-GrowthRatesCsv $DataDir}},
    @{Name="Natures"; File="16_natures.csv"; Func={Generate-NaturesCsv $DataDir}},
    @{Name="PokemonColors"; File="17_pokemon_colors.csv"; Func={Generate-PokemonColorsCsv $DataDir}},
    @{Name="PokemonShapes"; File="18_pokemon_shapes.csv"; Func={Generate-PokemonShapesCsv $DataDir}},
    @{Name="PokemonHabitats"; File="19_pokemon_habitats.csv"; Func={Generate-PokemonHabitatsCsv $DataDir}},
    @{Name="EvolutionChains"; File="20_evolution_chains.csv"; Func={Generate-EvolutionChainsCsv $DataDir}},
    @{Name="PokemonSpecies"; File="21_pokemon_species.csv"; Func={Generate-PokemonSpeciesCsv $DataDir}},
    @{Name="Pokedex"; File="22_pokedex.csv"; Func={Generate-PokedexCsv $DataDir}},
    @{Name="Pokemon"; File="23_pokemon.csv"; Func={Generate-PokemonCsv $DataDir $MediaDir}},
    @{Name="PokemonTypes"; File="24_pokemon_types.csv"; Func={Generate-PokemonTypesCsv $DataDir}},
    @{Name="PokemonAbilities"; File="25_pokemon_abilities.csv"; Func={Generate-PokemonAbilitiesCsv $DataDir}},
    @{Name="PokemonMoves"; File="26_pokemon_moves.csv"; Func={Generate-PokemonMovesCsv $DataDir}},
    @{Name="PokedexEntries"; File="27_pokedex_entries.csv"; Func={Generate-PokedexEntriesCsv $DataDir}},
    @{Name="PokemonVariants"; File="28_pokemon_variants.csv"; Func={Generate-PokemonVariantsCsv $DataDir}},
    @{Name="LocalizedNames"; File="29_localized_names.csv"; Func={Generate-LocalizedNamesCsv $DataDir}}
)

$tableIndex = 1
foreach ($table in $tables) {
    $filePath = Join-Path $OutputDir $table.File
    Write-Host "[$tableIndex/29] Generando $($table.Name)..." -ForegroundColor Cyan
    
    $csvRows = & $table.Func
    
    # Escribir CSV línea por línea para evitar problemas con saltos de línea en campos
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $stream = [System.IO.File]::Create($filePath)
    $writer = New-Object System.IO.StreamWriter($stream, $utf8NoBom)
    
    try {
        foreach ($row in $csvRows) {
            $writer.WriteLine($row)
        }
    } finally {
        $writer.Close()
        $stream.Close()
    }
    
    $tableIndex++
}

# Los archivos multimedia ya se copiaron directamente a assets/media durante la generación del CSV de Pokemon
Write-Host ""
Write-Host "[INFO] Archivos multimedia copiados durante la generación de CSV" -ForegroundColor DarkCyan

Write-Host ""
Write-Host "=========================================="
Write-Host "[INFO] Procesando archivos multimedia de pokemon-form y form..." -ForegroundColor DarkCyan
Write-Host "=========================================="
Write-Host ""

# Procesar archivos multimedia de pokemon-form
$pokemonFormPath = Join-Path $DataDir "pokemon-form"
if (Test-Path $pokemonFormPath) {
    Write-Host "[INFO] Procesando pokemon-form..." -ForegroundColor DarkCyan
    $pokemonFormDirs = Get-ChildItem -Path $pokemonFormPath -Directory -ErrorAction SilentlyContinue
    $processed = 0
    $total = $pokemonFormDirs.Count
    
    foreach ($formDir in $pokemonFormDirs) {
        $dataJson = Join-Path $formDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $processed++
        if ($processed % 50 -eq 0) {
            Write-Host "  Procesando pokemon-form $processed/$total..." -ForegroundColor DarkGray
        }
        
        try {
            $data = Get-Content $dataJson -Raw | ConvertFrom-Json
            $apiId = $data.id
            Process-PokemonFormMedia $apiId $data $DataDir $MediaDir
            $data = $null
        } catch {
            Write-Warning "  [AVISO] Error procesando pokemon-form $($formDir.Name): $_"
        }
    }
    Write-Host "[OK] Procesados $processed pokemon-form" -ForegroundColor DarkGreen
}

# Procesar archivos multimedia de form
$formPath = Join-Path $DataDir "form"
if (Test-Path $formPath) {
    Write-Host "[INFO] Procesando form..." -ForegroundColor DarkCyan
    $formDirs = Get-ChildItem -Path $formPath -Directory -ErrorAction SilentlyContinue
    $processed = 0
    $total = $formDirs.Count
    
    foreach ($formDir in $formDirs) {
        $dataJson = Join-Path $formDir.FullName "data.json"
        if (-not (Test-Path $dataJson)) { continue }
        
        $processed++
        if ($processed % 50 -eq 0) {
            Write-Host "  Procesando form $processed/$total..." -ForegroundColor DarkGray
        }
        
        try {
            $data = Get-Content $dataJson -Raw | ConvertFrom-Json
            $apiId = $data.id
            Process-FormMedia $apiId $data $DataDir $MediaDir
            $data = $null
        } catch {
            Write-Warning "  [AVISO] Error procesando form $($formDir.Name): $_"
        }
    }
    Write-Host "[OK] Procesados $processed form" -ForegroundColor DarkGreen
}

Write-Host ""
Write-Host "=========================================="
Write-Host "[COMPLETADO] CSV generado en archivos separados" -ForegroundColor DarkGreen
Write-Host "Directorio CSV: $OutputDir" -ForegroundColor DarkYellow
Write-Host "Directorio Multimedia: $MediaDir" -ForegroundColor DarkYellow
Write-Host "Total de archivos CSV: $($tables.Count)" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "Los archivos CSV están listos para ser usados en la app Flutter" -ForegroundColor Cyan
Write-Host "Las rutas de multimedia usan el formato assets/media/..." -ForegroundColor Cyan
Write-Host "=========================================="

# ============================================================
# Script de Descarga Recursiva de PokeAPI
# Descarga todos los datos de la API y crea estructura de carpetas
# Compatible con PowerShell 5.1+
# 
# FASE 1: Descarga todos los JSONs
# FASE 2: Descarga todos los archivos multimedia
# FASE 3: Procesa los datos igual que la app y genera backup procesable (SQL + multimedia)
# ============================================================

param(
    [string]$BaseUrl = "https://pokeapi.co/api/v2",
    [string]$BaseDir = "c:\users\loren\Desktop\pokemon_data",
    [string]$BackupDir = "c:\users\loren\Desktop\pokemon_data\backup"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# URL base de la API (sin trailing slash)
$ApiBaseUrl = $BaseUrl.TrimEnd('/')

# Cola de URLs pendientes de procesar
$queue = New-Object System.Collections.Queue
$processedUrls = New-Object System.Collections.Generic.HashSet[string]

# ============================================================
# CONFIGURACIÓN DE PROCESAMIENTO (igual que la app)
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

# Colores pastel para pokedexes (ColorGenerator.dart)
$PastelColors = @(
    '#FFB3BA', '#FFDFBA', '#FFFFBA', '#BAFFC9', '#BAE1FF',
    '#E0BBE4', '#FFCCCB', '#F0E68C', '#DDA0DD', '#98D8C8',
    '#F7DC6F', '#AED6F1', '#F8BBD0', '#C8E6C9', '#FFE5B4',
    '#E1BEE7', '#BBDEFB', '#FFECB3', '#C5E1A5', '#B2DFDB'
)

# Pokémon iniciales por región (StarterPokemon.dart)
$RegionStarters = @{
    'kanto' = @('bulbasaur', 'charmander', 'squirtle')
    'johto' = @('chikorita', 'cyndaquil', 'totodile')
    'hoenn' = @('treecko', 'torchic', 'mudkip')
    'sinnoh' = @('turtwig', 'chimchar', 'piplup')
    'unova' = @('snivy', 'tepig', 'oshawott')
    'kalos' = @('chespin', 'fennekin', 'froakie')
    'alola' = @('rowlet', 'litten', 'popplio')
    'galar' = @('grookey', 'scorbunny', 'sobble')
    'paldea' = @('sprigatito', 'fuecoco', 'quaxly')
    'hisui' = @('rowlet', 'cyndaquil', 'oshawott')
}

# ============================================================
# FUNCIONES AUXILIARES
# ============================================================

# Función para normalizar nombres de archivo/carpeta
function Normalize-PathName($name) {
    if ([string]::IsNullOrWhiteSpace($name)) {
        return "index"
    }
    # Reemplazar caracteres no válidos para nombres de archivo
    $normalized = $name -replace '[<>:"|?*\x00-\x1f]', '_'
    $normalized = $normalized -replace '\s+', '_'
    return $normalized.Trim('_')
}

# Función para obtener la ruta relativa desde la URL base
function Get-RelativePath($url) {
    if ($url -notmatch "^$([regex]::Escape($ApiBaseUrl))") {
        return $null
    }
    
    # Eliminar parametros de query string para el calculo de ruta
    $urlWithoutQuery = $url
    if ($url -match '\?') {
        $urlWithoutQuery = $url.Substring(0, $url.IndexOf('?'))
    }
    
    # Si es exactamente la URL base, retornar "v2"
    if ($urlWithoutQuery.TrimEnd('/') -eq $ApiBaseUrl) {
        return "v2"
    }
    
    # Para otras URLs, quitar la base y usar el resto (sin query string)
    $relative = $urlWithoutQuery.Substring($ApiBaseUrl.Length)
    $relative = $relative.TrimStart('/')
    return $relative
}

# Función para obtener la ruta completa del sistema de archivos
function Get-FileSystemPath($url) {
    $relative = Get-RelativePath $url
    if ($null -eq $relative) {
        return $null
    }
    
    # Si la URL termina con /, es un endpoint de lista (ej: /gender/)
    if ($url.EndsWith('/') -and $relative -ne 'v2') {
        $relative = $relative.TrimEnd('/')
    }
    
    # Si la URL tiene un ID numerico al final, extraerlo para la carpeta
    if ($relative -match '^(.+)/(\d+)/?$') {
        $basePath = $matches[1]
        $id = $matches[2]
        $relative = "$basePath/$id"
    }
    
    $pathParts = $relative -split '/'
    $normalizedParts = $pathParts | ForEach-Object { 
        $normalized = Normalize-PathName $_
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            return "index"
        }
        return $normalized
    }
    
    $fullPath = Join-Path $BaseDir ($normalizedParts -join '\')
    
    return $fullPath
}

# Función para detectar si una URL es un archivo multimedia
function Is-MediaUrl($url) {
    return ($url -match '\.(png|jpg|jpeg|gif|ogg|mp3|wav|svg|webp|bmp|mp4|webm)$')
}

# Función para extraer ID de una URL de la API
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

# Función para extraer todas las URLs de un objeto JSON recursivamente
function Extract-UrlsFromJson($obj, $path = "") {
    $urls = @()
    
    if ($null -eq $obj) {
        return $urls
    }
    
    if ($obj -is [System.Collections.IDictionary] -or $obj.GetType().Name -eq 'PSCustomObject') {
        # Es un objeto/diccionario
        $obj.PSObject.Properties | ForEach-Object {
            $propName = $_.Name
            $propValue = $_.Value
            $currentPath = if ($path) { "$path.$propName" } else { $propName }
            
            if ($propValue -is [string] -and $propValue -match '^https?://') {
                # Es una URL
                $urls += @{
                    Url = $propValue
                    Path = $currentPath
                }
            }
            elseif ($propValue -is [System.Collections.IList] -or $propValue -is [Array]) {
                # Es un array
                for ($i = 0; $i -lt $propValue.Count; $i++) {
                    $item = $propValue[$i]
                    $itemPath = "$currentPath[$i]"
                    
                    if ($item -is [string] -and $item -match '^https?://') {
                        $urls += @{
                            Url = $item
                            Path = $itemPath
                        }
                    }
                    else {
                        $urls += Extract-UrlsFromJson $item $itemPath
                    }
                }
            }
            else {
                # Recursión para objetos anidados
                $urls += Extract-UrlsFromJson $propValue $currentPath
            }
        }
    }
    elseif ($obj -is [System.Collections.IList] -or $obj -is [Array]) {
        # Es un array directo
        for ($i = 0; $i -lt $obj.Count; $i++) {
            $item = $obj[$i]
            $itemPath = if ($path) { "$path[$i]" } else { "[$i]" }
            
            if ($item -is [string] -and $item -match '^https?://') {
                $urls += @{
                    Url = $item
                    Path = $itemPath
                }
            }
            else {
                $urls += Extract-UrlsFromJson $item $itemPath
            }
        }
    }
    
    return $urls
}

# Función para guardar un archivo binario
function Save-MediaFile($url, $destPath) {
    # Chequear si el archivo ya existe antes de descargar
    if (Test-Path $destPath) {
        return $true
    }
    
    try {
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        
        Write-Host "  [MEDIA] Descargando: $url" -ForegroundColor DarkBlue
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "  [AVISO] Error al descargar archivo multimedia: $url -> $_"
        return $false
    }
}

# Función para descargar y guardar JSON
function Download-Json($url) {
    # Chequear si el archivo ya existe antes de descargar
    $fsPath = Get-FileSystemPath $url
    if ($null -ne $fsPath) {
        $dataJsonPath = Join-Path $fsPath "data.json"
        if (Test-Path $dataJsonPath) {
            try {
                $jsonRaw = Get-Content $dataJsonPath -Raw
                $json = $jsonRaw | ConvertFrom-Json
                return @{
                    IsJson = $true
                    Content = $json
                    RawContent = $jsonRaw
                }
            }
            catch {
                # Si hay error leyendo, continuar con descarga
            }
        }
    }
    
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $contentType = $response.Headers["Content-Type"]
        
        # Verificar si es un archivo multimedia
        if ($contentType -match 'image|audio|video|application/octet-stream' -or (Is-MediaUrl $url)) {
            return @{
                IsJson = $false
                Content = $null
                RawContent = $response.Content
            }
        }
        
        # Intentar parsear como JSON
        try {
            $json = $response.Content | ConvertFrom-Json
            return @{
                IsJson = $true
                Content = $json
                RawContent = $response.Content
            }
        }
        catch {
            Write-Warning "  [AVISO] No se pudo parsear como JSON: $url"
            return @{
                IsJson = $false
                Content = $null
                RawContent = $response.Content
            }
        }
    }
    catch {
        Write-Warning "  [AVISO] Error al descargar: $url -> $_"
        return $null
    }
}

# Función para escribir el archivo urls.txt
function Write-UrlsFile($filePath, $originalUrl, $urls, $estado = "pendiente") {
    $content = @()
    $content += "url_original: $originalUrl"
    $content += "estado: $estado"
    $content += ""
    
    foreach ($urlInfo in $urls) {
        $urlEstado = "pendiente"
        $urlNormalized = $urlInfo.Url
        if ($urlInfo.Url -match '\?') {
            $urlNormalized = $urlInfo.Url.Substring(0, $urlInfo.Url.IndexOf('?'))
        }
        $urlNormalized = $urlNormalized.TrimEnd('/')
        
        $isMedia = Is-MediaUrl $urlInfo.Url
        
        $urlPath = Get-FileSystemPath $urlInfo.Url
        
        if ($null -eq $urlPath -and $isMedia) {
            $urlPath = Split-Path $filePath -Parent
        }
        
        if ($null -ne $urlPath) {
            if ($isMedia) {
                $fileName = Split-Path $urlInfo.Url -Leaf
                if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq '/') {
                    $fileName = "media_file"
                }
                $mediaPath = Join-Path $urlPath $fileName
                if (Test-Path $mediaPath) {
                    $urlEstado = "procesado"
                }
            }
            else {
                $urlDataJson = Join-Path $urlPath "data.json"
                if (Test-Path $urlDataJson) {
                    $urlEstado = "procesado"
                }
            }
        }
        
        $mediaFlag = if ($isMedia) { "multimedia: si" } else { "multimedia: no" }
        $content += "$($urlInfo.Path): `"$($urlInfo.Url)`" | estado: $urlEstado | $mediaFlag"
    }
    
    $content | Out-File -FilePath $filePath -Encoding UTF8
}

# Función para actualizar el estado de una URL específica en urls.txt
function Update-UrlStatusInFile($filePath, $url, $newStatus) {
    if (-not (Test-Path $filePath)) {
        return
    }
    
    $content = Get-Content $filePath
    $newContent = @()
    $updated = $false
    
    foreach ($line in $content) {
        $lineUrl = $null
        if ($line -match '`"([^`"]+)`"') {
            $lineUrl = $matches[1]
        }
        
        if ($null -ne $lineUrl) {
            $normalizedLineUrl = $lineUrl
            if ($lineUrl -match '\?') {
                $normalizedLineUrl = $lineUrl.Substring(0, $lineUrl.IndexOf('?'))
            }
            $normalizedLineUrl = $normalizedLineUrl.TrimEnd('/')
            
            $normalizedInputUrl = $url
            if ($url -match '\?') {
                $normalizedInputUrl = $url.Substring(0, $url.IndexOf('?'))
            }
            $normalizedInputUrl = $normalizedInputUrl.TrimEnd('/')
            
            if ($normalizedLineUrl -eq $normalizedInputUrl -and $line -match '\| estado:') {
                $newLine = $line -replace '\| estado: (pendiente|procesado)', "| estado: $newStatus"
                $newContent += $newLine
                $updated = $true
            }
            else {
                $newContent += $line
            }
        }
        else {
            $newContent += $line
        }
    }
    
    if ($updated) {
        $newContent | Out-File -FilePath $filePath -Encoding UTF8
    }
}

# Función para verificar si todas las URLs de un urls.txt están procesadas
function Are-AllUrlsProcessed($filePath) {
    if (-not (Test-Path $filePath)) {
        return $false
    }
    
    $content = Get-Content $filePath
    $hasUrls = $false
    
    foreach ($line in $content) {
        if ($line -match '\| estado:') {
            $hasUrls = $true
            if ($line -match '\| estado: pendiente') {
                return $false
            }
        }
    }
    
    return $hasUrls
}

# Función para actualizar el estado general en urls.txt
function Update-UrlsFileStatus($filePath, $newStatus) {
    if (-not (Test-Path $filePath)) {
        return
    }
    
    $content = Get-Content $filePath
    $newContent = @()
    
    foreach ($line in $content) {
        if ($line -match '^estado: (pendiente|procesado)') {
            $newContent += "estado: $newStatus"
        }
        else {
            $newContent += $line
        }
    }
    
    $newContent | Out-File -FilePath $filePath -Encoding UTF8
}

# Función principal para procesar una URL
function Process-Url($url) {
    $normalizedForPath = $url
    if ($url -match '\?') {
        $normalizedForPath = $url.Substring(0, $url.IndexOf('?'))
    }
    $normalizedUrl = $normalizedForPath.TrimEnd('/')
    
    if ($processedUrls.Contains($normalizedUrl)) {
        return
    }
    
    if ($normalizedUrl -notmatch "^$([regex]::Escape($ApiBaseUrl))") {
        return
    }
    
    if (Is-MediaUrl $url) {
        $processedUrls.Add($normalizedUrl) | Out-Null
        return
    }
    
    $fsPath = Get-FileSystemPath $url
    if ($null -eq $fsPath) {
        Write-Warning "  [AVISO] No se pudo determinar la ruta para: $url"
        return
    }
    
    if (-not (Test-Path $fsPath)) {
        New-Item -ItemType Directory -Force -Path $fsPath | Out-Null
    }
    
    $dataJsonPath = Join-Path $fsPath "data.json"
    $urlsTxtPath = Join-Path $fsPath "urls.txt"
    
    $json = $null
    $jsonRaw = $null
    $downloadResult = $null
    $needsDownload = $false
    
    if (Test-Path $dataJsonPath) {
        Write-Host "[SKIP] JSON ya existe: $url -> $fsPath" -ForegroundColor DarkYellow
        try {
            $jsonRaw = Get-Content $dataJsonPath -Raw
            $json = $jsonRaw | ConvertFrom-Json
            $downloadResult = @{
                IsJson = $true
                Content = $json
                RawContent = $jsonRaw
            }
        }
        catch {
            Write-Warning "  [AVISO] Error al leer archivo existente, se reintentara descargar: $url"
            $downloadResult = $null
            $needsDownload = $true
        }
    }
    else {
        $needsDownload = $true
    }
    
    if ($needsDownload) {
        $downloadResult = Download-Json $url
        
        if ($null -eq $downloadResult) {
            return
        }
        
        if (-not $downloadResult.IsJson) {
            $processedUrls.Add($normalizedUrl) | Out-Null
            return
        }
        
        $json = $downloadResult.Content
        $jsonRaw = $downloadResult.RawContent
        
        try {
            $json | ConvertTo-Json -Depth 100 | Out-File -FilePath $dataJsonPath -Encoding UTF8
        }
        catch {
            $jsonRaw | Out-File -FilePath $dataJsonPath -Encoding UTF8
        }
    }
    
    if ($null -eq $json) {
        $json = $downloadResult.Content
    }
    if ($null -eq $jsonRaw) {
        $jsonRaw = $downloadResult.RawContent
    }
    
    $foundUrls = Extract-UrlsFromJson $json
    
    $apiUrls = $foundUrls | Where-Object { 
        $url = $_.Url
        $isApiUrl = $url -match "^$([regex]::Escape($ApiBaseUrl))"
        $isMedia = Is-MediaUrl $url
        return ($isApiUrl -or $isMedia)
    }
    
    Write-UrlsFile $urlsTxtPath $url $apiUrls "pendiente"
    
    foreach ($urlInfo in $apiUrls) {
        $foundUrl = $urlInfo.Url
        
        if (Is-MediaUrl $foundUrl) {
            continue
        }
        
        $normalizedForCheck = $foundUrl
        if ($foundUrl -match '\?') {
            $normalizedForCheck = $foundUrl.Substring(0, $foundUrl.IndexOf('?'))
        }
        $normalizedForCheck = $normalizedForCheck.TrimEnd('/')
        if (-not $processedUrls.Contains($normalizedForCheck)) {
            $queue.Enqueue($foundUrl)
        }
    }
    
    if (Are-AllUrlsProcessed $urlsTxtPath) {
        Update-UrlsFileStatus $urlsTxtPath "procesado"
    }
    
    $processedUrls.Add($normalizedUrl) | Out-Null
    
    Write-Host "  [OK] Procesado:  $fsPath" -ForegroundColor Green
}

# Función para extraer URLs multimedia de un objeto de sprites recursivamente
function Extract-SpriteUrls($sprites, $basePath) {
    $urls = New-Object System.Collections.ArrayList
    
    if ($null -eq $sprites) {
        return $urls
    }
    
    # Función auxiliar para añadir URL si existe y no es null
    function Add-UrlIfValid($url) {
        if ($null -ne $url -and $url -is [string] -and $url.Length -gt 0) {
            $null = $urls.Add($url)
        }
    }
    
    # Sprites básicos
    Add-UrlIfValid $sprites.front_default
    Add-UrlIfValid $sprites.front_shiny
    Add-UrlIfValid $sprites.back_default
    Add-UrlIfValid $sprites.back_shiny
    Add-UrlIfValid $sprites.front_female
    Add-UrlIfValid $sprites.front_shiny_female
    Add-UrlIfValid $sprites.back_female
    Add-UrlIfValid $sprites.back_shiny_female
    
    # Sprites de otras versiones
    if ($sprites.other) {
        if ($sprites.other.dream_world) {
            Add-UrlIfValid $sprites.other.dream_world.front_default
            Add-UrlIfValid $sprites.other.dream_world.front_female
        }
        if ($sprites.other.'official-artwork') {
            Add-UrlIfValid $sprites.other.'official-artwork'.front_default
            Add-UrlIfValid $sprites.other.'official-artwork'.front_shiny
        }
        if ($sprites.other.home) {
            Add-UrlIfValid $sprites.other.home.front_default
            Add-UrlIfValid $sprites.other.home.front_female
            Add-UrlIfValid $sprites.other.home.front_shiny
            Add-UrlIfValid $sprites.other.home.front_shiny_female
        }
        if ($sprites.other.showdown) {
            Add-UrlIfValid $sprites.other.showdown.front_default
            Add-UrlIfValid $sprites.other.showdown.front_shiny
            Add-UrlIfValid $sprites.other.showdown.front_female
            Add-UrlIfValid $sprites.other.showdown.front_shiny_female
            Add-UrlIfValid $sprites.other.showdown.back_default
            Add-UrlIfValid $sprites.other.showdown.back_shiny
            Add-UrlIfValid $sprites.other.showdown.back_female
            Add-UrlIfValid $sprites.other.showdown.back_shiny_female
        }
    }
    
    # Versiones animadas (si existen)
    if ($sprites.versions) {
        $versions = $sprites.versions
        foreach ($genKey in $versions.PSObject.Properties.Name) {
            $gen = $versions.$genKey
            foreach ($gameKey in $gen.PSObject.Properties.Name) {
                $game = $gen.$gameKey
                foreach ($spriteKey in $game.PSObject.Properties.Name) {
                    $spriteValue = $game.$spriteKey
                    if ($spriteValue -is [string]) {
                        Add-UrlIfValid $spriteValue
                    }
                    elseif ($spriteValue -is [PSCustomObject]) {
                        foreach ($subKey in $spriteValue.PSObject.Properties.Name) {
                            Add-UrlIfValid $spriteValue.$subKey
                        }
                    }
                }
            }
        }
    }
    
    return $urls
}

# Función para extraer URLs de cries
function Extract-CryUrls($cries) {
    $urls = @()
    if ($null -ne $cries) {
        if ($null -ne $cries.latest -and $cries.latest -is [string] -and $cries.latest.Length -gt 0) {
            $urls += $cries.latest
        }
        if ($null -ne $cries.legacy -and $cries.legacy -is [string] -and $cries.legacy.Length -gt 0) {
            $urls += $cries.legacy
        }
    }
    return $urls
}

# Función para extraer todas las URLs multimedia de todos los urls.txt Y de los JSONs de pokemon
function Extract-MediaUrlsFromFiles {
    $mediaUrls = New-Object System.Collections.ArrayList
    $processedUrls = New-Object System.Collections.Generic.HashSet[string]
    
    if (-not (Test-Path $BaseDir)) {
        return $mediaUrls
    }
    
    Write-Host "Extrayendo URLs multimedia de todos los urls.txt..." -ForegroundColor DarkYellow
    $allUrlsFiles = Get-ChildItem -Path $BaseDir -Filter "urls.txt" -Recurse -ErrorAction SilentlyContinue
    
    foreach ($urlsFile in $allUrlsFiles) {
        $content = Get-Content $urlsFile.FullName -ErrorAction SilentlyContinue
        if ($null -eq $content) {
            continue
        }
        
        foreach ($line in $content) {
            if ($line -match ':\s*"([^"]+)".*multimedia:\s*si') {
                $foundUrl = $matches[1]
                
                if ($processedUrls.Contains($foundUrl)) {
                    continue
                }
                
                $mediaPath = Get-FileSystemPath $foundUrl
                
                if ($null -eq $mediaPath) {
                    $mediaPath = Split-Path $urlsFile.FullName -Parent
                }
                
                if ($null -ne $mediaPath) {
                    $fileName = Split-Path $foundUrl -Leaf
                    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq '/') {
                        $fileName = "media_file_" + ($foundUrl -replace '[^\w]', '_').Substring(0, [Math]::Min(50, ($foundUrl -replace '[^\w]', '_').Length))
                    }
                    $mediaFilePath = Join-Path $mediaPath $fileName
                    
                    if (-not (Test-Path $mediaFilePath)) {
                        $null = $mediaUrls.Add(@{
                            Url = $foundUrl
                            DestPath = $mediaFilePath
                            ParentPath = $mediaPath
                        })
                        $processedUrls.Add($foundUrl) | Out-Null
                    }
                }
            }
        }
    }
    
    # Extraer URLs multimedia directamente de los JSONs de pokemon
    Write-Host "Extrayendo URLs multimedia de JSONs de pokemon (sprites, cries, etc.)..." -ForegroundColor DarkYellow
    $pokemonPath = Join-Path $BaseDir "pokemon"
    if (Test-Path $pokemonPath) {
        $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory -ErrorAction SilentlyContinue
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
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                
                # Extraer URLs de sprites
                if ($data.sprites) {
                    $spriteUrls = Extract-SpriteUrls $data.sprites $pokemonDir.FullName
                    foreach ($spriteUrl in $spriteUrls) {
                        if ($processedUrls.Contains($spriteUrl)) {
                            continue
                        }
                        
                        $mediaPath = $pokemonDir.FullName
                        $fileName = Split-Path $spriteUrl -Leaf
                        if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq '/') {
                            $fileName = "media_file_" + ($spriteUrl -replace '[^\w]', '_').Substring(0, [Math]::Min(50, ($spriteUrl -replace '[^\w]', '_').Length))
                        }
                        $mediaFilePath = Join-Path $mediaPath $fileName
                        
                        if (-not (Test-Path $mediaFilePath)) {
                            $null = $mediaUrls.Add(@{
                                Url = $spriteUrl
                                DestPath = $mediaFilePath
                                ParentPath = $mediaPath
                            })
                            $processedUrls.Add($spriteUrl) | Out-Null
                        }
                    }
                }
                
                # Extraer URLs de cries
                if ($data.cries) {
                    $cryUrls = Extract-CryUrls $data.cries
                    foreach ($cryUrl in $cryUrls) {
                        if ($processedUrls.Contains($cryUrl)) {
                            continue
                        }
                        
                        $mediaPath = $pokemonDir.FullName
                        $fileName = Split-Path $cryUrl -Leaf
                        if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq '/') {
                            $fileName = "media_file_" + ($cryUrl -replace '[^\w]', '_').Substring(0, [Math]::Min(50, ($cryUrl -replace '[^\w]', '_').Length))
                        }
                        $mediaFilePath = Join-Path $mediaPath $fileName
                        
                        if (-not (Test-Path $mediaFilePath)) {
                            $null = $mediaUrls.Add(@{
                                Url = $cryUrl
                                DestPath = $mediaFilePath
                                ParentPath = $mediaPath
                            })
                            $processedUrls.Add($cryUrl) | Out-Null
                        }
                    }
                }
                
                $data = $null
            }
            catch {
                Write-Warning "  [AVISO] Error procesando pokemon $($pokemonDir.Name): $_"
            }
        }
    }
    
    Write-Host "[OK] Encontradas $($mediaUrls.Count) URLs multimedia pendientes de descargar" -ForegroundColor DarkGreen
    return $mediaUrls
}

# Función para descargar archivos multimedia en paralelo por lotes
function Download-MediaFilesInParallel($mediaUrls, $batchSize = 10) {
    if ($mediaUrls.Count -eq 0) {
        Write-Host "[INFO] No hay archivos multimedia pendientes de descargar" -ForegroundColor DarkCyan
        return
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "Descargando archivos multimedia" -ForegroundColor DarkYellow
    Write-Host "Total de archivos: $($mediaUrls.Count)" -ForegroundColor DarkYellow
    Write-Host "Tamaño de lote: $batchSize" -ForegroundColor DarkYellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    $totalFiles = $mediaUrls.Count
    $downloaded = 0
    $failed = 0
    
    for ($i = 0; $i -lt $mediaUrls.Count; $i += $batchSize) {
        $batch = $mediaUrls[$i..([Math]::Min($i + $batchSize - 1, $mediaUrls.Count - 1))]
        
        Write-Host "[LOTE] Procesando lote $([Math]::Floor($i / $batchSize) + 1) - Archivos $($i + 1) a $([Math]::Min($i + $batchSize, $totalFiles)) de $totalFiles" -ForegroundColor DarkYellow
        
        $jobs = @()
        foreach ($mediaFile in $batch) {
            if (Test-Path $mediaFile.DestPath) {
                Write-Host "  [SKIP] Ya existe: $($mediaFile.Url)" -ForegroundColor DarkYellow
                $downloaded++
                continue
            }
            
            $job = Start-Job -ScriptBlock {
                param($url, $destPath)
                try {
                    $destDir = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    }
                    Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
                    return @{ Success = $true; Url = $url }
                }
                catch {
                    return @{ Success = $false; Url = $url; Error = $_.Exception.Message }
                }
            } -ArgumentList $mediaFile.Url, $mediaFile.DestPath
            
            $jobs += $job
        }
        
        if ($jobs.Count -gt 0) {
            $jobs | Wait-Job | Out-Null
            
            foreach ($job in $jobs) {
                $result = Receive-Job $job
                Remove-Job $job
                
                if ($result.Success) {
                    Write-Host "  [OK] Descargado: $($result.Url)" -ForegroundColor Green
                    $downloaded++
                }
                else {
                    Write-Warning "  [ERROR] Fallo al descargar: $($result.Url) -> $($result.Error)"
                    $failed++
                }
            }
        }
        
        Write-Host ""
    }
    
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "[COMPLETADO] Descarga de multimedia finalizada" -ForegroundColor DarkGreen
    Write-Host "Descargados: $downloaded" -ForegroundColor DarkYellow
    Write-Host "Fallidos: $failed" -ForegroundColor DarkYellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
}

# Función para cargar URLs pendientes desde urls.txt existentes
function Load-PendingUrlsFromFiles {
    if (-not (Test-Path $BaseDir)) {
        return
    }
    
    Write-Host "Cargando URLs pendientes desde archivos existentes..."
    $allUrlsFiles = Get-ChildItem -Path $BaseDir -Filter "urls.txt" -Recurse -ErrorAction SilentlyContinue
    $loadedCount = 0
    
    foreach ($urlsFile in $allUrlsFiles) {
        $content = Get-Content $urlsFile.FullName -ErrorAction SilentlyContinue
        if ($null -eq $content) {
            continue
        }
        
        foreach ($line in $content) {
            if ($line -match '`"([^`"]+)`".*\| estado: pendiente.*multimedia: no') {
                $foundUrl = $matches[1]
                
                $normalizedUrl = $foundUrl
                if ($foundUrl -match '\?') {
                    $normalizedUrl = $foundUrl.Substring(0, $foundUrl.IndexOf('?'))
                }
                $normalizedUrl = $normalizedUrl.TrimEnd('/')
                
                $urlPath = Get-FileSystemPath $foundUrl
                if ($null -ne $urlPath) {
                    $urlDataJson = Join-Path $urlPath "data.json"
                    if (Test-Path $urlDataJson) {
                        Update-UrlStatusInFile $urlsFile.FullName $foundUrl "procesado"
                        $processedUrls.Add($normalizedUrl) | Out-Null
                        continue
                    }
                }
                
                if (-not $processedUrls.Contains($normalizedUrl)) {
                    $queue.Enqueue($foundUrl)
                    $loadedCount++
                }
            }
        }
    }
    
    if ($loadedCount -gt 0) {
        Write-Host "[OK] Cargadas $loadedCount URLs pendientes desde archivos existentes" -ForegroundColor DarkGreen
    }
    else {
        Write-Host "[OK] No se encontraron URLs pendientes" -ForegroundColor DarkGreen
    }
    Write-Host ""
}

# ============================================================
# FASE 3: PROCESAMIENTO Y GENERACIÓN DE CSV
# ============================================================

# Diccionarios para mapear API IDs a IDs de base de datos
$script:idMaps = @{
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
$script:idCounters = @{
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

# Función para obtener ID de base de datos desde API ID
function Get-DbId($table, $apiId) {
    if ($null -eq $apiId) {
        return $null
    }
    
    if ($script:idMaps[$table].ContainsKey($apiId)) {
        return $script:idMaps[$table][$apiId]
    }
    
    $newId = $script:idCounters[$table]
    $script:idMaps[$table][$apiId] = $newId
    $script:idCounters[$table]++
    return $newId
}

# Función para escapar valores CSV
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

# Función para escapar JSON en CSV
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

# Función para obtener ruta de asset
function Get-AssetPath($relativePath) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return ''
    }
    # Normalizar separadores de ruta y añadir prefijo assets/
    $normalized = $relativePath -replace '\\', '/'
    if (-not $normalized.StartsWith('assets/')) {
        $normalized = "assets/$normalized"
    }
    return $normalized
}

# Función para obtener color de tipo
function Get-TypeColor($typeName) {
    $normalized = $typeName.ToLower()
    if ($TypeColors.ContainsKey($normalized)) {
        return $TypeColors[$normalized]
    }
    return $null
}

# Función para generar color pastel para pokedex
function Get-PokedexColor($index) {
    if ($index -lt $PastelColors.Count) {
        return $PastelColors[$index]
    }
    
    # Generar color pastel aleatorio (RGB entre 180-255)
    $r = 180 + (Get-Random -Maximum 76)
    $g = 180 + (Get-Random -Maximum 76)
    $b = 180 + (Get-Random -Maximum 76)
    return "#$($r.ToString('X2'))$($g.ToString('X2'))$($b.ToString('X2'))"
}

# Función para verificar si un pokemon es inicial de una región
function Is-StarterPokemon($pokemonName, $regionName) {
    $normalizedRegion = $regionName.ToLower()
    $normalizedPokemon = $pokemonName.ToLower()
    
    if ($RegionStarters.ContainsKey($normalizedRegion)) {
        return $RegionStarters[$normalizedRegion] -contains $normalizedPokemon
    }
    return $false
}

# Función para verificar si un pokemon es variante especial (gmax, mega, primal)
function Is-SpecialVariant($pokemonName) {
    $nameLower = $pokemonName.ToLower()
    return ($nameLower -match 'gmax|mega|primal')
}

# Función para extraer región del nombre de un pokemon
function Get-RegionFromPokemonName($pokemonName, $allRegions) {
    $pokemonNameLower = $pokemonName.ToLower()
    
    foreach ($region in $allRegions) {
        $regionNameLower = $region.Name.ToLower()
        if ($pokemonNameLower -match $regionNameLower) {
            return $region
        }
    }
    
    return $null
}

# Función para procesar y enriquecer datos y generar CSV
function Process-DataForBackup {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "FASE 3: Procesando datos y generando CSV" -ForegroundColor DarkYellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Procesar tipos y asignar colores (para que generar_sql.ps1 los encuentre)
    Write-Host "[INFO] Procesando tipos y asignando colores..." -ForegroundColor DarkCyan
    $typesPath = Join-Path $BaseDir "type"
    if (Test-Path $typesPath) {
        $typeDirs = Get-ChildItem -Path $typesPath -Directory
        foreach ($typeDir in $typeDirs) {
            $dataJson = Join-Path $typeDir.FullName "data.json"
            if (Test-Path $dataJson) {
                $typeData = Get-Content $dataJson -Raw | ConvertFrom-Json
                $typeName = $typeData.name
                $color = Get-TypeColor $typeName
                
                if (-not $typeData.PSObject.Properties['processed_color']) {
                    $typeData | Add-Member -MemberType NoteProperty -Name "processed_color" -Value $color -Force
                }
                else {
                    $typeData.processed_color = $color
                }
                
                $typeData | ConvertTo-Json -Depth 100 | Out-File -FilePath $dataJson -Encoding UTF8
            }
        }
    }
    
    # Procesar pokedexes y asignar colores
    Write-Host "[INFO] Procesando pokedexes y asignando colores..." -ForegroundColor DarkCyan
    $pokedexPath = Join-Path $BaseDir "pokedex"
    if (Test-Path $pokedexPath) {
        $pokedexDirs = Get-ChildItem -Path $pokedexPath -Directory
        $pokedexIndex = 0
        foreach ($pokedexDir in $pokedexDirs) {
            $dataJson = Join-Path $pokedexDir.FullName "data.json"
            if (Test-Path $dataJson) {
                $pokedexData = Get-Content $dataJson -Raw | ConvertFrom-Json
                $color = Get-PokedexColor $pokedexIndex
                
                if (-not $pokedexData.PSObject.Properties['processed_color']) {
                    $pokedexData | Add-Member -MemberType NoteProperty -Name "processed_color" -Value $color -Force
                }
                else {
                    $pokedexData.processed_color = $color
                }
                
                $pokedexData | ConvertTo-Json -Depth 100 | Out-File -FilePath $dataJson -Encoding UTF8
                $pokedexIndex++
            }
        }
    }
    
    # Identificar pokemons iniciales
    Write-Host "[INFO] Identificando pokemons iniciales por región..." -ForegroundColor DarkCyan
    $regionsPath = Join-Path $BaseDir "region"
    if (Test-Path $regionsPath) {
        $regionDirs = Get-ChildItem -Path $regionsPath -Directory
        foreach ($regionDir in $regionDirs) {
            $dataJson = Join-Path $regionDir.FullName "data.json"
            if (Test-Path $dataJson) {
                $regionData = Get-Content $dataJson -Raw | ConvertFrom-Json
                $regionName = $regionData.name
                
                $starters = @()
                if ($RegionStarters.ContainsKey($regionName.ToLower())) {
                    $starters = $RegionStarters[$regionName.ToLower()]
                }
                
                if (-not $regionData.PSObject.Properties['processed_starters']) {
                    $regionData | Add-Member -MemberType NoteProperty -Name "processed_starters" -Value $starters -Force
                }
                else {
                    $regionData.processed_starters = $starters
                }
                
                $regionData | ConvertTo-Json -Depth 100 | Out-File -FilePath $dataJson -Encoding UTF8
            }
        }
    }
    
    # Ejecutar generar_sql.ps1 para generar CSV
    Write-Host "[INFO] Generando CSV desde JSONs..." -ForegroundColor DarkCyan
    
    # Buscar generar_sql.ps1 en la misma carpeta que este script
    $scriptPath = Join-Path $PSScriptRoot "generar_sql.ps1"
    if (-not (Test-Path $scriptPath)) {
        # Si no está en la misma carpeta, buscar en la carpeta scripts relativa
        $possiblePaths = @(
            Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\generar_sql.ps1",
            Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "scripts\generar_sql.ps1",
            "C:\Users\loren\Desktop\proyectos\pokesearch\scripts\generar_sql.ps1"
        )
        $found = $false
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $scriptPath = $path
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Error "No se encontró el script generar_sql.ps1. Asegúrate de que esté en la misma carpeta o en scripts/"
            return
        }
    }
    
    # Calcular rutas de salida (temporales para generar CSV y media)
    $tempOutputDir = Join-Path $env:TEMP "poke_searcher_backup"
    $tempDatabaseDir = Join-Path $tempOutputDir "database"
    $tempMediaDir = Join-Path $tempOutputDir "media"
    
    # Crear directorios temporales
    if (-not (Test-Path $tempDatabaseDir)) {
        New-Item -ItemType Directory -Force -Path $tempDatabaseDir | Out-Null
    }
    if (-not (Test-Path $tempMediaDir)) {
        New-Item -ItemType Directory -Force -Path $tempMediaDir | Out-Null
    }
    
    Write-Host "[INFO] Ejecutando generar_sql.ps1..." -ForegroundColor DarkCyan
    Write-Host "  DataDir: $BaseDir" -ForegroundColor DarkGray
    Write-Host "  OutputDir: $tempDatabaseDir" -ForegroundColor DarkGray
    Write-Host "  MediaDir: $tempMediaDir" -ForegroundColor DarkGray
    
    & $scriptPath -DataDir $BaseDir -OutputDir $tempDatabaseDir -MediaDir $tempMediaDir
    
    # Crear un solo ZIP con todo el contenido
    Write-Host ""
    Write-Host "[INFO] Creando archivo ZIP..." -ForegroundColor DarkCyan
    
    # Directorio base para el ZIP
    $zipBasePath = "C:\Users\loren\Desktop\proyectos\pokesearch"
    $zipPath = Join-Path $zipBasePath "poke_searcher_backup.zip"
    
    # Eliminar ZIP existente si existe
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Write-Host "  Eliminado ZIP existente" -ForegroundColor DarkGray
    }
    
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    Write-Host "  Creando ZIP con database y media..." -ForegroundColor DarkCyan
    
    # Crear ZIP desde el directorio temporal que contiene database y media
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempOutputDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    
    $zipSize = (Get-Item $zipPath).Length
    $zipSizeMB = [Math]::Round($zipSize / 1MB, 2)
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "[COMPLETADO] FASE 3: ZIP generado" -ForegroundColor DarkGreen
    Write-Host "Tamaño del ZIP: $zipSizeMB MB" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "ZIP ubicado en: $zipPath" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Estructura del ZIP:" -ForegroundColor DarkCyan
    Write-Host "  - database/ (todos los CSV)" -ForegroundColor DarkGray
    Write-Host "  - media/ (imágenes y sonidos)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Sube este ZIP a GitHub Releases y proporciona la URL" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Limpiar directorios temporales
    Write-Host "[INFO] Limpiando directorios temporales..." -ForegroundColor DarkCyan
    Remove-Item $tempOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
# INICIO DEL SCRIPT
# ============================================================

Write-Host "=========================================="
Write-Host "Descargador de PokeAPI"
Write-Host "=========================================="
Write-Host "URL Base: $ApiBaseUrl"
Write-Host "Directorio Base: $BaseDir"
Write-Host "Directorio Backup: $BackupDir"
Write-Host ""

# Crear directorio base
if (-not (Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
    Write-Host "[OK] Directorio base creado: $BaseDir" -ForegroundColor DarkGreen
}

# Cargar URLs pendientes desde archivos existentes (para retomar descarga)
Load-PendingUrlsFromFiles

# Procesar URL inicial solo si no existe
$basePath = Get-FileSystemPath $ApiBaseUrl
if ($null -ne $basePath) {
    $baseDataJson = Join-Path $basePath "data.json"
    if (-not (Test-Path $baseDataJson)) {
        Write-Host ""
        Write-Host "Iniciando descarga desde URL base..."
        Write-Host ""
        Process-Url $ApiBaseUrl
    }
    else {
        Write-Host "[SKIP] URL base ya procesada, continuando con URLs pendientes..." -ForegroundColor DarkYellow
        Write-Host ""
    }
}

# FASE 1: Procesar todos los JSONs
Write-Host "=========================================="
Write-Host "FASE 1: Procesando todos los JSONs"
Write-Host "=========================================="
Write-Host ""

$fase1StartTime = Get-Date
$totalProcessed = 0
$maxIterations = 100000

while ($queue.Count -gt 0 -and $totalProcessed -lt $maxIterations) {
    $url = $queue.Dequeue()
    Process-Url $url
    $totalProcessed++
    
    if ($totalProcessed % 50 -eq 0) {
        Write-Host ""
        Write-Host "Progreso: $totalProcessed URLs JSON procesadas, $($queue.Count) pendientes..."
        Write-Host ""
    }
}

if ($queue.Count -gt 0) {
    Write-Warning "[AVISO] Se alcanzo el limite de iteraciones. Quedan $($queue.Count) URLs JSON pendientes."
}

$fase1EndTime = Get-Date
$fase1Duration = $fase1EndTime - $fase1StartTime
$fase1Hours = [Math]::Floor($fase1Duration.TotalHours)
$fase1Minutes = [Math]::Floor($fase1Duration.TotalMinutes) % 60
$fase1Seconds = [Math]::Floor($fase1Duration.TotalSeconds) % 60

Write-Host ""
Write-Host "=========================================="
Write-Host "[COMPLETADO] FASE 1: Todos los JSONs procesados" -ForegroundColor DarkGreen
Write-Host "Total de URLs JSON procesadas: $totalProcessed"
Write-Host "Tiempo transcurrido: $fase1Hours h $fase1Minutes m $fase1Seconds s" -ForegroundColor Cyan
Write-Host "=========================================="
Write-Host ""

# FASE 2: Extraer y descargar archivos multimedia
Write-Host "=========================================="
Write-Host "FASE 2: Descargando archivos multimedia"
Write-Host "=========================================="
Write-Host ""

$fase2StartTime = Get-Date

$mediaUrls = Extract-MediaUrlsFromFiles
Download-MediaFilesInParallel -mediaUrls $mediaUrls -batchSize 10

$fase2EndTime = Get-Date
$fase2Duration = $fase2EndTime - $fase2StartTime
$fase2Hours = [Math]::Floor($fase2Duration.TotalHours)
$fase2Minutes = [Math]::Floor($fase2Duration.TotalMinutes) % 60
$fase2Seconds = [Math]::Floor($fase2Duration.TotalSeconds) % 60

# FASE 3: Procesar datos y generar backup
Process-DataForBackup

$totalStartTime = $fase1StartTime
$totalEndTime = Get-Date
$totalDuration = $totalEndTime - $totalStartTime
$totalHours = [Math]::Floor($totalDuration.TotalHours)
$totalMinutes = [Math]::Floor($totalDuration.TotalMinutes) % 60
$totalSeconds = [Math]::Floor($totalDuration.TotalSeconds) % 60

Write-Host ""
Write-Host "=========================================="
Write-Host "[COMPLETADO] Descarga completa" -ForegroundColor DarkGreen
Write-Host "Total de URLs JSON procesadas: $totalProcessed"
Write-Host "Total de archivos multimedia: $($mediaUrls.Count)"
Write-Host ""
Write-Host "Tiempos:" -ForegroundColor Cyan
Write-Host "  FASE 1 (JSONs): $fase1Hours h $fase1Minutes m $fase1Seconds s" -ForegroundColor Cyan
Write-Host "  FASE 2 (Multimedia): $fase2Hours h $fase2Minutes m $fase2Seconds s" -ForegroundColor Cyan
Write-Host "  FASE 3 (Procesamiento): Completado" -ForegroundColor Cyan
Write-Host "  TOTAL: $totalHours h $totalMinutes m $totalSeconds s" -ForegroundColor Yellow
Write-Host ""
Write-Host "Datos guardados en: $BaseDir"
Write-Host "Backup procesable en: $BackupDir"
Write-Host "=========================================="

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
    [string]$BackupDir = "c:\users\loren\Desktop\pokemon_data\backup",
    [switch]$OnlyPhase3 = $false
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

# Función para extraer solo las URLs esenciales de sprites
# Prioridad: SVG > PNG de mayor resolución
# Extrae: 1 imagen normal (SVG preferido, PNG fallback), 1 imagen shiny (SVG preferido, PNG fallback)
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
    
    # Estrategia: Priorizar SVG, si no hay, usar PNG de mayor resolución
    # Para normal: dream-world SVG > official-artwork PNG > home PNG
    # Para shiny: buscar SVG shiny (poco probable) > official-artwork PNG > home PNG
    
    $normalUrl = $null
    $shinyUrl = $null
    
    if ($sprites.other) {
        # ============================================
        # IMAGEN NORMAL: Priorizar SVG, luego PNG de mayor resolución
        # ============================================
        
        # 1. Intentar SVG desde dream-world (prioridad máxima)
        if ($sprites.other.dream_world) {
            $dreamWorldUrl = $sprites.other.dream_world.front_default
            if ($null -ne $dreamWorldUrl -and $dreamWorldUrl -is [string] -and $dreamWorldUrl.ToLower().EndsWith('.svg')) {
                $normalUrl = $dreamWorldUrl
            }
        }
        
        # 2. Si no hay SVG, usar PNG de official-artwork (mayor resolución que home)
        if ($null -eq $normalUrl -and $sprites.other.'official-artwork') {
            $officialDefault = $sprites.other.'official-artwork'.front_default
            if ($null -ne $officialDefault -and $officialDefault.ToLower().EndsWith('.png')) {
                $normalUrl = $officialDefault
            }
        }
        
        # 3. Si aún no hay, usar PNG de home (fallback)
        if ($null -eq $normalUrl -and $sprites.other.home) {
            $homeDefault = $sprites.other.home.front_default
            if ($null -ne $homeDefault -and $homeDefault.ToLower().EndsWith('.png')) {
                $normalUrl = $homeDefault
            }
        }
        
        # ============================================
        # IMAGEN SHINY: Priorizar SVG, luego PNG de mayor resolución
        # ============================================
        
        # 1. Buscar SVG shiny en todas las ubicaciones posibles (poco probable que exista)
        # Nota: No hay SVG shiny en dream-world, pero buscamos en todas las ubicaciones por si acaso
        $foundSvgShiny = $false
        
        # Buscar SVG shiny en home (si existe)
        if ($sprites.other.home) {
            $homeShinySvg = $sprites.other.home.front_shiny
            if ($null -ne $homeShinySvg -and $homeShinySvg -is [string] -and $homeShinySvg.ToLower().EndsWith('.svg')) {
                $shinyUrl = $homeShinySvg
                $foundSvgShiny = $true
            }
        }
        
        # 2. Si no hay SVG shiny, usar PNG de official-artwork (mayor resolución)
        if (-not $foundSvgShiny -and $sprites.other.'official-artwork') {
            $officialShiny = $sprites.other.'official-artwork'.front_shiny
            if ($null -ne $officialShiny -and $officialShiny.ToLower().EndsWith('.png')) {
                $shinyUrl = $officialShiny
            }
        }
        
        # 3. Si aún no hay, usar PNG shiny de home (fallback)
        if ($null -eq $shinyUrl -and $sprites.other.home) {
            $homeShiny = $sprites.other.home.front_shiny
            if ($null -ne $homeShiny -and $homeShiny.ToLower().EndsWith('.png')) {
                $shinyUrl = $homeShiny
            }
        }
    }
    
    # Añadir URLs encontradas
    if ($null -ne $normalUrl) {
        Add-UrlIfValid $normalUrl
    }
    if ($null -ne $shinyUrl) {
        Add-UrlIfValid $shinyUrl
    }
    
    return $urls
}

# Función para extraer URLs de cry (prioridad: latest, fallback: legacy)
# Devuelve ambas URLs si latest está disponible (para intentar legacy si latest falla)
function Extract-CryUrls($cries) {
    $urls = @()
    if ($null -ne $cries) {
        $hasLatest = $false
        
        # Prioridad 1: cries.latest (OGG)
        if ($null -ne $cries.latest -and $cries.latest -is [string] -and $cries.latest.Length -gt 0 -and $cries.latest.ToLower().EndsWith('.ogg')) {
            $urls += $cries.latest
            $hasLatest = $true
        }
        
        # Si latest está disponible, también añadir legacy como fallback (por si latest falla al descargar)
        if ($hasLatest -and $null -ne $cries.legacy -and $cries.legacy -is [string] -and $cries.legacy.Length -gt 0 -and $cries.legacy.ToLower().EndsWith('.ogg')) {
            # Añadir legacy con un marcador especial para indicar que es fallback
            $urls += @{
                Url = $cries.legacy
                IsFallback = $true
                PrimaryUrl = $cries.latest
            }
        }
        # Si latest no está disponible, usar legacy directamente
        elseif (-not $hasLatest -and $null -ne $cries.legacy -and $cries.legacy -is [string] -and $cries.legacy.Length -gt 0 -and $cries.legacy.ToLower().EndsWith('.ogg')) {
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
    
    Write-Host "Extrayendo URLs multimedia esenciales de todos los urls.txt..." -ForegroundColor DarkYellow
    Write-Host "  Estrategia: SVG preferido > PNG mayor resolución" -ForegroundColor DarkGray
    Write-Host "  Normal: dream-world SVG > official-artwork PNG > home PNG" -ForegroundColor DarkGray
    Write-Host "  Shiny: SVG (si existe) > official-artwork PNG > home PNG" -ForegroundColor DarkGray
    Write-Host "  Sonido: cries.latest OGG > cries.legacy OGG" -ForegroundColor DarkGray
    $allUrlsFiles = Get-ChildItem -Path $BaseDir -Filter "urls.txt" -Recurse -ErrorAction SilentlyContinue
    
    foreach ($urlsFile in $allUrlsFiles) {
        $content = Get-Content $urlsFile.FullName -ErrorAction SilentlyContinue
        if ($null -eq $content) {
            continue
        }
        
        foreach ($line in $content) {
            if ($line -match ':\s*"([^"]+)".*multimedia:\s*si') {
                $foundUrl = $matches[1]
                
                # Filtrar solo las URLs esenciales:
                # 1. SVG o PNG de imagen normal (dream-world SVG > official-artwork PNG > home PNG)
                # 2. SVG o PNG shiny (SVG poco probable, official-artwork PNG > home PNG)
                # 3. OGG de cries (latest preferido, legacy como fallback)
                $isEssential = $false
                $urlLower = $foundUrl.ToLower()
                
                # SVG de dream-world (imagen normal, prioridad máxima)
                if ($urlLower -match 'dream-world.*\.svg$') {
                    $isEssential = $true
                }
                # PNG de official-artwork (imagen normal, fallback si no hay SVG)
                elseif ($urlLower -match 'official-artwork.*front_default.*\.png$' -and -not $urlLower.Contains('shiny')) {
                    $isEssential = $true
                }
                # PNG de home (imagen normal, último fallback)
                elseif ($urlLower -match 'home.*front_default.*\.png$' -and -not $urlLower.Contains('shiny')) {
                    $isEssential = $true
                }
                # PNG shiny de official-artwork (imagen shiny, prioridad)
                elseif ($urlLower -match 'official-artwork.*shiny.*\.png$') {
                    $isEssential = $true
                }
                # PNG shiny de home (imagen shiny, fallback)
                elseif ($urlLower -match 'home.*shiny.*\.png$') {
                    $isEssential = $true
                }
                # SVG shiny (si existe en alguna ubicación, poco probable)
                elseif ($urlLower -match '.*shiny.*\.svg$') {
                    $isEssential = $true
                }
                # OGG de cries.latest (prioridad)
                elseif ($urlLower -match 'cries.*latest.*\.ogg$') {
                    $isEssential = $true
                }
                # OGG de cries.legacy (fallback si no hay latest)
                elseif ($urlLower -match 'cries.*legacy.*\.ogg$') {
                    $isEssential = $true
                }
                
                if (-not $isEssential) {
                    continue
                }
                
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
                
                # Extraer URLs de sprites con nombres específicos que la app espera
                if ($data.sprites) {
                    $sprites = $data.sprites
                    $pokemonApiId = $pokemonDir.Name
                    
                    # ============================================
                    # IMAGEN NORMAL: Priorizar SVG, luego PNG de mayor resolución
                    # ============================================
                    $normalUrl = $null
                    $normalFileName = $null
                    $normalExt = $null
                    
                    # 1. Intentar SVG desde dream-world (prioridad máxima)
                    if ($sprites.other.dream_world.front_default) {
                        $dreamWorldUrl = $sprites.other.dream_world.front_default
                        if ($null -ne $dreamWorldUrl -and $dreamWorldUrl.ToLower().EndsWith('.svg')) {
                            $normalUrl = $dreamWorldUrl
                            $normalExt = "svg"
                            $normalFileName = "sprite_front_default.svg"
                        }
                    }
                    
                    # 2. Si no hay SVG, usar PNG de official-artwork (mayor resolución que home)
                    if ($null -eq $normalUrl -and $sprites.other.'official-artwork'.front_default) {
                        $officialDefault = $sprites.other.'official-artwork'.front_default
                        if ($null -ne $officialDefault -and $officialDefault.ToLower().EndsWith('.png')) {
                            $normalUrl = $officialDefault
                            $normalExt = "png"
                            $normalFileName = "sprite_front_default.png"
                        }
                    }
                    
                    # 3. Si aún no hay, usar PNG de home (fallback)
                    if ($null -eq $normalUrl -and $sprites.other.home.front_default) {
                        $homeDefault = $sprites.other.home.front_default
                        if ($null -ne $homeDefault -and $homeDefault.ToLower().EndsWith('.png')) {
                            $normalUrl = $homeDefault
                            $normalExt = "png"
                            $normalFileName = "sprite_front_default.png"
                        }
                    }
                    
                    # Descargar imagen normal con nombre específico
                    if ($null -ne $normalUrl -and $null -ne $normalFileName) {
                        if (-not $processedUrls.Contains($normalUrl)) {
                            $mediaPath = $pokemonDir.FullName
                            $mediaFilePath = Join-Path $mediaPath $normalFileName
                            
                            if (-not (Test-Path $mediaFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $normalUrl
                                    DestPath = $mediaFilePath
                                    ParentPath = $mediaPath
                                    FileName = $normalFileName
                                })
                                $processedUrls.Add($normalUrl) | Out-Null
                            }
                        }
                        
                        # También crear artwork_official con el mismo archivo (para PokemonImageHelper)
                        $artworkFileName = "artwork_official.$normalExt"
                        $artworkFilePath = Join-Path $mediaPath $artworkFileName
                        if (-not (Test-Path $artworkFilePath)) {
                            $null = $mediaUrls.Add(@{
                                Url = $normalUrl
                                DestPath = $artworkFilePath
                                ParentPath = $mediaPath
                                FileName = $artworkFileName
                                IsCopy = $true  # Marcar como copia del mismo archivo
                                SourceFile = $normalFileName
                            })
                        }
                    }
                    
                    # ============================================
                    # IMAGEN SHINY: Priorizar SVG, luego PNG de mayor resolución
                    # ============================================
                    $shinyUrl = $null
                    $shinyFileName = $null
                    $shinyExt = $null
                    
                    # 1. Buscar SVG shiny (poco probable que exista)
                    if ($sprites.other.home.front_shiny) {
                        $homeShinySvg = $sprites.other.home.front_shiny
                        if ($null -ne $homeShinySvg -and $homeShinySvg.ToLower().EndsWith('.svg')) {
                            $shinyUrl = $homeShinySvg
                            $shinyExt = "svg"
                            $shinyFileName = "sprite_front_shiny.svg"
                        }
                    }
                    
                    # 2. Si no hay SVG shiny, usar PNG de official-artwork (mayor resolución)
                    if ($null -eq $shinyUrl -and $sprites.other.'official-artwork'.front_shiny) {
                        $officialShiny = $sprites.other.'official-artwork'.front_shiny
                        if ($null -ne $officialShiny -and $officialShiny.ToLower().EndsWith('.png')) {
                            $shinyUrl = $officialShiny
                            $shinyExt = "png"
                            $shinyFileName = "sprite_front_shiny.png"
                        }
                    }
                    
                    # 3. Si aún no hay, usar PNG shiny de home (fallback)
                    if ($null -eq $shinyUrl -and $sprites.other.home.front_shiny) {
                        $homeShiny = $sprites.other.home.front_shiny
                        if ($null -ne $homeShiny -and $homeShiny.ToLower().EndsWith('.png')) {
                            $shinyUrl = $homeShiny
                            $shinyExt = "png"
                            $shinyFileName = "sprite_front_shiny.png"
                        }
                    }
                    
                    # Descargar imagen shiny con nombre específico
                    if ($null -ne $shinyUrl -and $null -ne $shinyFileName) {
                        if (-not $processedUrls.Contains($shinyUrl)) {
                            $mediaPath = $pokemonDir.FullName
                            $mediaFilePath = Join-Path $mediaPath $shinyFileName
                            
                            if (-not (Test-Path $mediaFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $shinyUrl
                                    DestPath = $mediaFilePath
                                    ParentPath = $mediaPath
                                    FileName = $shinyFileName
                                })
                                $processedUrls.Add($shinyUrl) | Out-Null
                            }
                        }
                        
                        # También crear artwork_official_shiny con el mismo archivo
                        $artworkShinyFileName = "artwork_official_shiny.$shinyExt"
                        $artworkShinyFilePath = Join-Path $mediaPath $artworkShinyFileName
                        if (-not (Test-Path $artworkShinyFilePath)) {
                            $null = $mediaUrls.Add(@{
                                Url = $shinyUrl
                                DestPath = $artworkShinyFilePath
                                ParentPath = $mediaPath
                                FileName = $artworkShinyFileName
                                IsCopy = $true
                                SourceFile = $shinyFileName
                            })
                        }
                    }
                }
                
                # Extraer URLs de cries con nombres específicos que la app espera
                if ($data.cries) {
                    $cries = $data.cries
                    $pokemonApiId = $pokemonDir.Name
                    $mediaPath = $pokemonDir.FullName
                    
                    # Prioridad: latest, fallback: legacy
                    $cryLatestUrl = $null
                    $cryLegacyUrl = $null
                    
                    if ($null -ne $cries.latest -and $cries.latest -is [string] -and $cries.latest.Length -gt 0 -and $cries.latest.ToLower().EndsWith('.ogg')) {
                        $cryLatestUrl = $cries.latest
                    }
                    
                    if ($null -ne $cries.legacy -and $cries.legacy -is [string] -and $cries.legacy.Length -gt 0 -and $cries.legacy.ToLower().EndsWith('.ogg')) {
                        $cryLegacyUrl = $cries.legacy
                    }
                    
                    # Descargar cry_latest.ogg
                    if ($null -ne $cryLatestUrl) {
                        if (-not $processedUrls.Contains($cryLatestUrl)) {
                            $cryLatestFilePath = Join-Path $mediaPath "cry_latest.ogg"
                            if (-not (Test-Path $cryLatestFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $cryLatestUrl
                                    DestPath = $cryLatestFilePath
                                    ParentPath = $mediaPath
                                    FileName = "cry_latest.ogg"
                                })
                                $processedUrls.Add($cryLatestUrl) | Out-Null
                            }
                        }
                        
                        # Si latest está disponible, también añadir legacy como fallback
                        if ($null -ne $cryLegacyUrl -and -not $processedUrls.Contains($cryLegacyUrl)) {
                            $cryLegacyFilePath = Join-Path $mediaPath "cry_legacy.ogg"
                            if (-not (Test-Path $cryLegacyFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $cryLegacyUrl
                                    DestPath = $cryLegacyFilePath
                                    ParentPath = $mediaPath
                                    FileName = "cry_legacy.ogg"
                                    IsFallback = $true
                                    PrimaryUrl = $cryLatestUrl
                                })
                                $processedUrls.Add($cryLegacyUrl) | Out-Null
                            }
                        }
                    }
                    # Si latest no está disponible, usar legacy directamente
                    elseif ($null -ne $cryLegacyUrl) {
                        if (-not $processedUrls.Contains($cryLegacyUrl)) {
                            $cryLegacyFilePath = Join-Path $mediaPath "cry_legacy.ogg"
                            if (-not (Test-Path $cryLegacyFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $cryLegacyUrl
                                    DestPath = $cryLegacyFilePath
                                    ParentPath = $mediaPath
                                    FileName = "cry_legacy.ogg"
                                })
                                $processedUrls.Add($cryLegacyUrl) | Out-Null
                            }
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
    
    # Extraer URLs multimedia de items
    Write-Host "Extrayendo URLs multimedia de JSONs de items..." -ForegroundColor DarkYellow
    $itemsPath = Join-Path $BaseDir "item"
    if (Test-Path $itemsPath) {
        $itemDirs = Get-ChildItem -Path $itemsPath -Directory -ErrorAction SilentlyContinue
        $processed = 0
        $total = $itemDirs.Count
        
        foreach ($itemDir in $itemDirs) {
            $dataJson = Join-Path $itemDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            $processed++
            if ($processed % 100 -eq 0) {
                Write-Host "  Procesando item $processed/$total..." -ForegroundColor DarkGray
            }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $itemApiId = $itemDir.Name
                $mediaPath = $itemDir.FullName
                
                # Extraer sprites de items (default sprite)
                if ($data.sprites -and $data.sprites.default) {
                    $spriteUrl = $data.sprites.default
                    if ($null -ne $spriteUrl -and $spriteUrl -is [string] -and $spriteUrl.Length -gt 0) {
                        $fileName = Split-Path $spriteUrl -Leaf
                        if ([string]::IsNullOrWhiteSpace($fileName)) {
                            $fileName = "default.png"
                        }
                        $mediaFilePath = Join-Path $mediaPath $fileName
                        
                        if (-not $processedUrls.Contains($spriteUrl) -and -not (Test-Path $mediaFilePath)) {
                            $null = $mediaUrls.Add(@{
                                Url = $spriteUrl
                                DestPath = $mediaFilePath
                                ParentPath = $mediaPath
                                FileName = $fileName
                            })
                            $processedUrls.Add($spriteUrl) | Out-Null
                        }
                    }
                }
                
                $data = $null
            }
            catch {
                Write-Warning "  [AVISO] Error procesando item $($itemDir.Name): $_"
            }
        }
    }
    
    # Extraer URLs multimedia de pokemon-form
    Write-Host "Extrayendo URLs multimedia de JSONs de pokemon-form..." -ForegroundColor DarkYellow
    $pokemonFormPath = Join-Path $BaseDir "pokemon-form"
    if (Test-Path $pokemonFormPath) {
        $pokemonFormDirs = Get-ChildItem -Path $pokemonFormPath -Directory -ErrorAction SilentlyContinue
        $processed = 0
        $total = $pokemonFormDirs.Count
        
        foreach ($formDir in $pokemonFormDirs) {
            $dataJson = Join-Path $formDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            $processed++
            if ($processed % 100 -eq 0) {
                Write-Host "  Procesando pokemon-form $processed/$total..." -ForegroundColor DarkGray
            }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $formApiId = $data.id
                $mediaPath = $formDir.FullName
                
                # Extraer sprites de pokemon-form (front_default)
                if ($data.sprites) {
                    $sprites = $data.sprites
                    
                    # Prioridad: front_default de sprites
                    if ($sprites.front_default) {
                        $spriteUrl = $sprites.front_default
                        if ($null -ne $spriteUrl -and $spriteUrl -is [string] -and $spriteUrl.Length -gt 0) {
                            $fileName = Split-Path $spriteUrl -Leaf
                            if ([string]::IsNullOrWhiteSpace($fileName)) {
                                $fileName = "front_default.png"
                            }
                            $mediaFilePath = Join-Path $mediaPath $fileName
                            
                            if (-not $processedUrls.Contains($spriteUrl) -and -not (Test-Path $mediaFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $spriteUrl
                                    DestPath = $mediaFilePath
                                    ParentPath = $mediaPath
                                    FileName = $fileName
                                })
                                $processedUrls.Add($spriteUrl) | Out-Null
                            }
                        }
                    }
                }
                
                $data = $null
            }
            catch {
                Write-Warning "  [AVISO] Error procesando pokemon-form $($formDir.Name): $_"
            }
        }
    }
    
    # Extraer URLs multimedia de form
    Write-Host "Extrayendo URLs multimedia de JSONs de form..." -ForegroundColor DarkYellow
    $formPath = Join-Path $BaseDir "form"
    if (Test-Path $formPath) {
        $formDirs = Get-ChildItem -Path $formPath -Directory -ErrorAction SilentlyContinue
        $processed = 0
        $total = $formDirs.Count
        
        foreach ($formDir in $formDirs) {
            $dataJson = Join-Path $formDir.FullName "data.json"
            if (-not (Test-Path $dataJson)) { continue }
            
            $processed++
            if ($processed % 100 -eq 0) {
                Write-Host "  Procesando form $processed/$total..." -ForegroundColor DarkGray
            }
            
            try {
                $data = Get-Content $dataJson -Raw | ConvertFrom-Json
                $formApiId = $data.id
                $mediaPath = $formDir.FullName
                
                # Extraer sprites de form (sprites pueden estar en diferentes ubicaciones)
                if ($data.sprites) {
                    $sprites = $data.sprites
                    
                    # Prioridad: front_default de sprites
                    if ($sprites.front_default) {
                        $spriteUrl = $sprites.front_default
                        if ($null -ne $spriteUrl -and $spriteUrl -is [string] -and $spriteUrl.Length -gt 0) {
                            $fileName = Split-Path $spriteUrl -Leaf
                            if ([string]::IsNullOrWhiteSpace($fileName)) {
                                $fileName = "front_default.png"
                            }
                            $mediaFilePath = Join-Path $mediaPath $fileName
                            
                            if (-not $processedUrls.Contains($spriteUrl) -and -not (Test-Path $mediaFilePath)) {
                                $null = $mediaUrls.Add(@{
                                    Url = $spriteUrl
                                    DestPath = $mediaFilePath
                                    ParentPath = $mediaPath
                                    FileName = $fileName
                                })
                                $processedUrls.Add($spriteUrl) | Out-Null
                            }
                        }
                    }
                }
                
                $data = $null
            }
            catch {
                Write-Warning "  [AVISO] Error procesando form $($formDir.Name): $_"
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
    
    # Crear diccionario de fallbacks para búsqueda rápida
    $fallbackMap = @{}
    foreach ($mediaFile in $mediaUrls) {
        if ($mediaFile.IsFallback -and $null -ne $mediaFile.PrimaryUrl) {
            if (-not $fallbackMap.ContainsKey($mediaFile.PrimaryUrl)) {
                $fallbackMap[$mediaFile.PrimaryUrl] = $mediaFile
            }
        }
    }
    
    for ($i = 0; $i -lt $mediaUrls.Count; $i += $batchSize) {
        $batch = $mediaUrls[$i..([Math]::Min($i + $batchSize - 1, $mediaUrls.Count - 1))]
        
        Write-Host "[LOTE] Procesando lote $([Math]::Floor($i / $batchSize) + 1) - Archivos $($i + 1) a $([Math]::Min($i + $batchSize, $totalFiles)) de $totalFiles" -ForegroundColor DarkYellow
        
        # Separar archivos a descargar de archivos a copiar
        $filesToDownload = @()
        $filesToCopy = @()
        
        foreach ($mediaFile in $batch) {
            # Saltar fallbacks en la descarga inicial (solo se descargan si el primary falla)
            if ($mediaFile.IsFallback) {
                continue
            }
            
            # Separar archivos a copiar (mismo archivo, diferente nombre)
            if ($mediaFile.IsCopy -and $null -ne $mediaFile.SourceFile) {
                $filesToCopy += $mediaFile
                continue
            }
            
            if (Test-Path $mediaFile.DestPath) {
                Write-Host "  [SKIP] Ya existe: $($mediaFile.Url)" -ForegroundColor DarkYellow
                $downloaded++
                continue
            }
            
            $filesToDownload += $mediaFile
        }
        
        # Descargar archivos principales
        $jobs = @()
        foreach ($mediaFile in $filesToDownload) {
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
                    # Si latest falla, intentar legacy como fallback
                    $shouldTryFallback = $false
                    $fallbackUrl = $null
                    $fallbackDestPath = $null
                    
                    # Buscar si hay un fallback legacy para esta URL (latest que falló)
                    if ($fallbackMap.ContainsKey($result.Url)) {
                        $fallbackFile = $fallbackMap[$result.Url]
                        $shouldTryFallback = $true
                        $fallbackUrl = $fallbackFile.Url
                        $fallbackDestPath = $fallbackFile.DestPath
                    }
                    
                    if ($shouldTryFallback -and $null -ne $fallbackUrl) {
                        Write-Host "  [FALLBACK] Latest falló, intentando legacy: $fallbackUrl" -ForegroundColor DarkYellow
                        try {
                            $fallbackDestDir = Split-Path $fallbackDestPath -Parent
                            if (-not (Test-Path $fallbackDestDir)) {
                                New-Item -ItemType Directory -Force -Path $fallbackDestDir | Out-Null
                            }
                            Invoke-WebRequest -Uri $fallbackUrl -OutFile $fallbackDestPath -UseBasicParsing -ErrorAction Stop
                            Write-Host "  [OK] Descargado (legacy): $fallbackUrl" -ForegroundColor Green
                            $downloaded++
                        }
                        catch {
                            Write-Warning "  [ERROR] Fallo al descargar legacy: $fallbackUrl -> $_"
                            $failed++
                        }
                    }
                    else {
                        Write-Warning "  [ERROR] Fallo al descargar: $($result.Url) -> $($result.Error)"
                        $failed++
                    }
                }
            }
        }
        
        # Procesar archivos a copiar después de descargar los principales
        foreach ($mediaFile in $filesToCopy) {
            $sourcePath = Join-Path $mediaFile.ParentPath $mediaFile.SourceFile
            if (Test-Path $sourcePath) {
                try {
                    $destDir = Split-Path $mediaFile.DestPath -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    }
                    Copy-Item -Path $sourcePath -Destination $mediaFile.DestPath -Force -ErrorAction Stop
                    Write-Host "  [COPY] Copiado: $($mediaFile.FileName) desde $($mediaFile.SourceFile)" -ForegroundColor DarkCyan
                    $downloaded++
                }
                catch {
                    Write-Warning "  [ERROR] Error copiando $($mediaFile.FileName): $_"
                    $failed++
                }
            } else {
                # Intentar buscar el archivo fuente con diferentes extensiones (svg/png)
                $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($mediaFile.SourceFile)
                $sourceExt = [System.IO.Path]::GetExtension($mediaFile.SourceFile)
                $alternatives = @()
                if ($sourceExt -eq '.svg') {
                    $alternatives = @("$sourceBaseName.png")
                } elseif ($sourceExt -eq '.png') {
                    $alternatives = @("$sourceBaseName.svg")
                }
                
                $found = $false
                foreach ($alt in $alternatives) {
                    $altSourcePath = Join-Path $mediaFile.ParentPath $alt
                    if (Test-Path $altSourcePath) {
                        try {
                            $destDir = Split-Path $mediaFile.DestPath -Parent
                            if (-not (Test-Path $destDir)) {
                                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                            }
                            Copy-Item -Path $altSourcePath -Destination $mediaFile.DestPath -Force -ErrorAction Stop
                            Write-Host "  [COPY] Copiado (alternativo): $($mediaFile.FileName) desde $alt" -ForegroundColor DarkCyan
                            $downloaded++
                            $found = $true
                            break
                        }
                        catch {
                            # Continuar buscando
                        }
                    }
                }
                
                if (-not $found) {
                    Write-Warning "  [AVISO] Archivo fuente no existe para copiar: $sourcePath (se copiará en el siguiente lote si se descarga)"
                }
            }
        }
        
        Write-Host ""
    }
    
    # Pasada final: copiar todos los archivos marcados como copias que no se pudieron copiar antes
    Write-Host "[INFO] Procesando copias pendientes..." -ForegroundColor DarkCyan
    $copiesToProcess = $mediaUrls | Where-Object { $_.IsCopy -and $null -ne $_.SourceFile }
    $copiesProcessed = 0
    $copiesFailed = 0
    foreach ($mediaFile in $copiesToProcess) {
        $sourcePath = Join-Path $mediaFile.ParentPath $mediaFile.SourceFile
        if (Test-Path $sourcePath) {
            if (-not (Test-Path $mediaFile.DestPath)) {
                try {
                    $destDir = Split-Path $mediaFile.DestPath -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    }
                    Copy-Item -Path $sourcePath -Destination $mediaFile.DestPath -Force -ErrorAction Stop
                    Write-Host "  [COPY] Copiado: $($mediaFile.FileName) desde $($mediaFile.SourceFile)" -ForegroundColor DarkCyan
                    $downloaded++
                    $copiesProcessed++
                }
                catch {
                    Write-Warning "  [ERROR] Error copiando $($mediaFile.FileName): $_"
                    $failed++
                    $copiesFailed++
                }
            } else {
                $copiesProcessed++
            }
        } else {
            # Intentar buscar el archivo fuente con diferentes extensiones (svg/png)
            $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($mediaFile.SourceFile)
            $sourceExt = [System.IO.Path]::GetExtension($mediaFile.SourceFile)
            $alternatives = @()
            if ($sourceExt -eq '.svg') {
                $alternatives = @("$sourceBaseName.png")
            } elseif ($sourceExt -eq '.png') {
                $alternatives = @("$sourceBaseName.svg")
            }
            
            $found = $false
            foreach ($alt in $alternatives) {
                $altSourcePath = Join-Path $mediaFile.ParentPath $alt
                if (Test-Path $altSourcePath) {
                    try {
                        $destDir = Split-Path $mediaFile.DestPath -Parent
                        if (-not (Test-Path $destDir)) {
                            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                        }
                        Copy-Item -Path $altSourcePath -Destination $mediaFile.DestPath -Force -ErrorAction Stop
                        Write-Host "  [COPY] Copiado (alternativo): $($mediaFile.FileName) desde $alt" -ForegroundColor DarkCyan
                        $downloaded++
                        $copiesProcessed++
                        $found = $true
                        break
                    }
                    catch {
                        # Continuar buscando
                    }
                }
            }
            
            if (-not $found) {
                Write-Warning "  [AVISO] Archivo fuente no existe: $sourcePath (también buscado: $($alternatives -join ', '))"
                $copiesFailed++
            }
        }
    }
    Write-Host "[INFO] Copias procesadas: $copiesProcessed, fallidas: $copiesFailed" -ForegroundColor DarkCyan
    
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "[COMPLETADO] Descarga de multimedia finalizada" -ForegroundColor DarkGreen
    Write-Host "Descargados: $downloaded" -ForegroundColor DarkYellow
    Write-Host "Fallidos: $failed" -ForegroundColor DarkYellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
}

# ============================================================
# FUNCIONES PARA GENERACIÓN DE CSV (integradas desde generar_sql.ps1)
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

# Función para extraer API ID de una URL
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

# Función para copiar archivos multimedia ya descargados (simplificada - los archivos ya tienen los nombres correctos)
function Copy-PokemonMediaFiles($pokemonApiId, $dataDir, $mediaDir) {
    $pokemonSourceDir = Join-Path $dataDir "pokemon\$pokemonApiId"
    $pokemonMediaDir = Join-Path $mediaDir "pokemon\$pokemonApiId"
    
    if (-not (Test-Path $pokemonSourceDir)) {
        return @{}
    }
    
    if (-not (Test-Path $pokemonMediaDir)) {
        try {
            New-Item -ItemType Directory -Force -Path $pokemonMediaDir | Out-Null
        } catch {
            return @{}
        }
    }
    
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
    
    # Los archivos ya están descargados con los nombres correctos, solo copiarlos
    $expectedFiles = @(
        @{Name="sprite_front_default.svg"; Path="spriteFrontDefaultPath"},
        @{Name="sprite_front_default.png"; Path="spriteFrontDefaultPath"},
        @{Name="sprite_front_shiny.svg"; Path="spriteFrontShinyPath"},
        @{Name="sprite_front_shiny.png"; Path="spriteFrontShinyPath"},
        @{Name="sprite_back_default.png"; Path="spriteBackDefaultPath"},
        @{Name="sprite_back_shiny.png"; Path="spriteBackShinyPath"},
        @{Name="artwork_official.svg"; Path="artworkOfficialPath"},
        @{Name="artwork_official.png"; Path="artworkOfficialPath"},
        @{Name="artwork_official_shiny.svg"; Path="artworkOfficialShinyPath"},
        @{Name="artwork_official_shiny.png"; Path="artworkOfficialShinyPath"},
        @{Name="cry_latest.ogg"; Path="cryLatestPath"},
        @{Name="cry_legacy.ogg"; Path="cryLegacyPath"}
    )
    
    foreach ($expectedFile in $expectedFiles) {
        $sourcePath = Join-Path $pokemonSourceDir $expectedFile.Name
        $targetPath = Join-Path $pokemonMediaDir $expectedFile.Name
        
        if (Test-Path $sourcePath) {
            if (-not (Test-Path $targetPath)) {
                Copy-Item -Path $sourcePath -Destination $targetPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $targetPath) {
                $mediaPaths[$expectedFile.Path] = Get-AssetPath "media/pokemon/$pokemonApiId/$($expectedFile.Name)"
            }
        } else {
            # Si el archivo no existe, intentar buscar variantes (ej: artwork_official.svg vs artwork_official.png)
            # Solo para artwork_official y artwork_official_shiny
            if ($expectedFile.Name -match '^artwork_official') {
                $baseName = $expectedFile.Name -replace '\.(svg|png)$', ''
                $alternatives = @("$baseName.svg", "$baseName.png")
                foreach ($alt in $alternatives) {
                    $altSourcePath = Join-Path $pokemonSourceDir $alt
                    if (Test-Path $altSourcePath) {
                        $targetPath = Join-Path $pokemonMediaDir $expectedFile.Name
                        $targetDir = Split-Path $targetPath -Parent
                        if (-not (Test-Path $targetDir)) {
                            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                        }
                        Copy-Item -Path $altSourcePath -Destination $targetPath -Force -ErrorAction SilentlyContinue
                        if (Test-Path $targetPath) {
                            $mediaPaths[$expectedFile.Path] = Get-AssetPath "media/pokemon/$pokemonApiId/$($expectedFile.Name)"
                            break
                        }
                    }
                }
            }
        }
    }
    
    return $mediaPaths
}

# ============================================================
# FUNCIONES DE GENERACIÓN DE CSV
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
        
        # Copiar multimedia de items (simplificado - solo copiar archivos existentes)
        $itemSourceDir = Join-Path $dataDir "item\$apiId"
        $itemMediaDir = Join-Path $mediaDir "item\$apiId"
        if (Test-Path $itemSourceDir) {
            if (-not (Test-Path $itemMediaDir)) {
                New-Item -ItemType Directory -Force -Path $itemMediaDir | Out-Null
            }
            $itemMediaFiles = Get-ChildItem -Path $itemSourceDir -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -match '\.(svg|png|jpg|jpeg)$'
            }
            foreach ($itemFile in $itemMediaFiles) {
                $targetPath = Join-Path $itemMediaDir $itemFile.Name
                if (-not (Test-Path $targetPath)) {
                    Copy-Item -Path $itemFile.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
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
            
            # Copiar archivos multimedia ya descargados con nombres correctos
            $mediaPaths = Copy-PokemonMediaFiles $apiId $dataDir $mediaDir
            
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
            
            $data = $null
            $jsonContent = $null
            
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
                            $languageDbId = Get-DbId "languages" $languageApiId
                            
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

# Función para crear archivos artwork_official.* como copias de sprite_front_default.*
# Esta función se ejecuta antes de la FASE 3 para asegurar que los archivos existan
function Create-ArtworkOfficialFiles {
    Write-Host "[INFO] Verificando y creando archivos artwork_official.*..." -ForegroundColor DarkCyan
    $pokemonPath = Join-Path $BaseDir "pokemon"
    if (-not (Test-Path $pokemonPath)) {
        Write-Host "[AVISO] Carpeta pokemon no existe, saltando creación de artwork_official" -ForegroundColor Yellow
        return
    }
    
    $pokemonDirs = Get-ChildItem -Path $pokemonPath -Directory -ErrorAction SilentlyContinue
    $processed = 0
    $total = $pokemonDirs.Count
    $created = 0
    $skipped = 0
    
    foreach ($pokemonDir in $pokemonDirs) {
        $processed++
        if ($processed % 100 -eq 0) {
            Write-Host "  Verificando pokemon $processed/$total..." -ForegroundColor DarkGray
        }
        
        try {
            # Verificar y crear artwork_official.svg o .png
            $spriteSvg = Join-Path $pokemonDir.FullName "sprite_front_default.svg"
            $spritePng = Join-Path $pokemonDir.FullName "sprite_front_default.png"
            $artworkSvg = Join-Path $pokemonDir.FullName "artwork_official.svg"
            $artworkPng = Join-Path $pokemonDir.FullName "artwork_official.png"
            
            # Crear artwork_official.svg desde sprite_front_default.svg
            if ((Test-Path $spriteSvg) -and (-not (Test-Path $artworkSvg))) {
                Copy-Item -Path $spriteSvg -Destination $artworkSvg -Force -ErrorAction SilentlyContinue
                if (Test-Path $artworkSvg) {
                    $created++
                }
            } elseif (Test-Path $artworkSvg) {
                $skipped++
            }
            
            # Crear artwork_official.png desde sprite_front_default.png (si no hay SVG)
            if ((-not (Test-Path $artworkSvg)) -and (Test-Path $spritePng) -and (-not (Test-Path $artworkPng))) {
                Copy-Item -Path $spritePng -Destination $artworkPng -Force -ErrorAction SilentlyContinue
                if (Test-Path $artworkPng) {
                    $created++
                }
            } elseif (Test-Path $artworkPng) {
                $skipped++
            }
            
            # Verificar y crear artwork_official_shiny.svg o .png
            $spriteShinySvg = Join-Path $pokemonDir.FullName "sprite_front_shiny.svg"
            $spriteShinyPng = Join-Path $pokemonDir.FullName "sprite_front_shiny.png"
            $artworkShinySvg = Join-Path $pokemonDir.FullName "artwork_official_shiny.svg"
            $artworkShinyPng = Join-Path $pokemonDir.FullName "artwork_official_shiny.png"
            
            # Crear artwork_official_shiny.svg desde sprite_front_shiny.svg
            if ((Test-Path $spriteShinySvg) -and (-not (Test-Path $artworkShinySvg))) {
                Copy-Item -Path $spriteShinySvg -Destination $artworkShinySvg -Force -ErrorAction SilentlyContinue
                if (Test-Path $artworkShinySvg) {
                    $created++
                }
            } elseif (Test-Path $artworkShinySvg) {
                $skipped++
            }
            
            # Crear artwork_official_shiny.png desde sprite_front_shiny.png (si no hay SVG)
            if ((-not (Test-Path $artworkShinySvg)) -and (Test-Path $spriteShinyPng) -and (-not (Test-Path $artworkShinyPng))) {
                Copy-Item -Path $spriteShinyPng -Destination $artworkShinyPng -Force -ErrorAction SilentlyContinue
                if (Test-Path $artworkShinyPng) {
                    $created++
                }
            } elseif (Test-Path $artworkShinyPng) {
                $skipped++
            }
        }
        catch {
            # Continuar con el siguiente pokemon
        }
    }
    
    Write-Host "[OK] Archivos artwork_official.*: $created creados, $skipped ya existían" -ForegroundColor DarkGreen
}

# Función para procesar y enriquecer datos y generar CSV
function Process-DataForBackup {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "FASE 3: Procesando datos y generando CSV" -ForegroundColor DarkYellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Crear archivos artwork_official.* antes de procesar (si no existen)
    Create-ArtworkOfficialFiles
    
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
    
    # Generar CSV directamente (sin usar generar_sql.ps1)
    Write-Host "[INFO] Generando CSV desde JSONs..." -ForegroundColor DarkCyan
    
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
    
    Write-Host "[INFO] Generando CSV y copiando media..." -ForegroundColor DarkCyan
    Write-Host "  DataDir: $BaseDir" -ForegroundColor DarkGray
    Write-Host "  OutputDir: $tempDatabaseDir" -ForegroundColor DarkGray
    Write-Host "  MediaDir: $tempMediaDir" -ForegroundColor DarkGray
    
    # Generar todos los CSV usando las funciones Generate-*
    Write-Host "[INFO] Generando archivos CSV..." -ForegroundColor DarkCyan
    
    # Definir orden de tablas con sus nombres de archivo
    $tables = @(
        @{Name="Languages"; File="01_languages.csv"; Func={Generate-LanguagesCsv $BaseDir}},
        @{Name="Generations"; File="02_generations.csv"; Func={Generate-GenerationsCsv $BaseDir}},
        @{Name="Regions"; File="03_regions.csv"; Func={Generate-RegionsCsv $BaseDir}},
        @{Name="Types"; File="04_types.csv"; Func={Generate-TypesCsv $BaseDir}},
        @{Name="TypeDamageRelations"; File="05_type_damage_relations.csv"; Func={Generate-TypeDamageRelationsCsv $BaseDir}},
        @{Name="Stats"; File="06_stats.csv"; Func={Generate-StatsCsv $BaseDir}},
        @{Name="VersionGroups"; File="07_version_groups.csv"; Func={Generate-VersionGroupsCsv $BaseDir}},
        @{Name="MoveDamageClasses"; File="08_move_damage_classes.csv"; Func={Generate-MoveDamageClassesCsv $BaseDir}},
        @{Name="Abilities"; File="09_abilities.csv"; Func={Generate-AbilitiesCsv $BaseDir}},
        @{Name="Moves"; File="10_moves.csv"; Func={Generate-MovesCsv $BaseDir}},
        @{Name="ItemPockets"; File="11_item_pockets.csv"; Func={Generate-ItemPocketsCsv $BaseDir}},
        @{Name="ItemCategories"; File="12_item_categories.csv"; Func={Generate-ItemCategoriesCsv $BaseDir}},
        @{Name="Items"; File="13_items.csv"; Func={Generate-ItemsCsv $BaseDir $tempMediaDir}},
        @{Name="EggGroups"; File="14_egg_groups.csv"; Func={Generate-EggGroupsCsv $BaseDir}},
        @{Name="GrowthRates"; File="15_growth_rates.csv"; Func={Generate-GrowthRatesCsv $BaseDir}},
        @{Name="Natures"; File="16_natures.csv"; Func={Generate-NaturesCsv $BaseDir}},
        @{Name="PokemonColors"; File="17_pokemon_colors.csv"; Func={Generate-PokemonColorsCsv $BaseDir}},
        @{Name="PokemonShapes"; File="18_pokemon_shapes.csv"; Func={Generate-PokemonShapesCsv $BaseDir}},
        @{Name="PokemonHabitats"; File="19_pokemon_habitats.csv"; Func={Generate-PokemonHabitatsCsv $BaseDir}},
        @{Name="EvolutionChains"; File="20_evolution_chains.csv"; Func={Generate-EvolutionChainsCsv $BaseDir}},
        @{Name="PokemonSpecies"; File="21_pokemon_species.csv"; Func={Generate-PokemonSpeciesCsv $BaseDir}},
        @{Name="Pokedex"; File="22_pokedex.csv"; Func={Generate-PokedexCsv $BaseDir}},
        @{Name="Pokemon"; File="23_pokemon.csv"; Func={Generate-PokemonCsv $BaseDir $tempMediaDir}},
        @{Name="PokemonTypes"; File="24_pokemon_types.csv"; Func={Generate-PokemonTypesCsv $BaseDir}},
        @{Name="PokemonAbilities"; File="25_pokemon_abilities.csv"; Func={Generate-PokemonAbilitiesCsv $BaseDir}},
        @{Name="PokemonMoves"; File="26_pokemon_moves.csv"; Func={Generate-PokemonMovesCsv $BaseDir}},
        @{Name="PokedexEntries"; File="27_pokedex_entries.csv"; Func={Generate-PokedexEntriesCsv $BaseDir}},
        @{Name="PokemonVariants"; File="28_pokemon_variants.csv"; Func={Generate-PokemonVariantsCsv $BaseDir}},
        @{Name="LocalizedNames"; File="29_localized_names.csv"; Func={Generate-LocalizedNamesCsv $BaseDir}}
    )
    
    $tableIndex = 1
    foreach ($table in $tables) {
        $filePath = Join-Path $tempDatabaseDir $table.File
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
    
    # Procesar archivos multimedia de pokemon-form y form
    Write-Host ""
    Write-Host "[INFO] Procesando archivos multimedia de pokemon-form y form..." -ForegroundColor DarkCyan
    
    # Procesar pokemon-form
    $pokemonFormPath = Join-Path $BaseDir "pokemon-form"
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
                
                # Copiar archivos multimedia de pokemon-form
                $formSourceDir = Join-Path $BaseDir "pokemon-form\$apiId"
                $formMediaDir = Join-Path $tempMediaDir "pokemon-form\$apiId"
                
                if (Test-Path $formSourceDir) {
                    if (-not (Test-Path $formMediaDir)) {
                        New-Item -ItemType Directory -Force -Path $formMediaDir | Out-Null
                    }
                    $formMediaFiles = Get-ChildItem -Path $formSourceDir -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.Extension -match '\.(svg|png|jpg|jpeg)$'
                    }
                    foreach ($formFile in $formMediaFiles) {
                        $targetPath = Join-Path $formMediaDir $formFile.Name
                        if (-not (Test-Path $targetPath)) {
                            Copy-Item -Path $formFile.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                
                $data = $null
            } catch {
                Write-Warning "  [AVISO] Error procesando pokemon-form $($formDir.Name): $_"
            }
        }
        Write-Host "[OK] Procesados $processed pokemon-form" -ForegroundColor DarkGreen
    }
    
    # Procesar form
    $formPath = Join-Path $BaseDir "form"
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
                
                # Copiar archivos multimedia de form
                $formSourceDir = Join-Path $BaseDir "form\$apiId"
                $formMediaDir = Join-Path $tempMediaDir "form\$apiId"
                
                if (Test-Path $formSourceDir) {
                    if (-not (Test-Path $formMediaDir)) {
                        New-Item -ItemType Directory -Force -Path $formMediaDir | Out-Null
                    }
                    $formMediaFiles = Get-ChildItem -Path $formSourceDir -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.Extension -match '\.(svg|png|jpg|jpeg)$'
                    }
                    foreach ($formFile in $formMediaFiles) {
                        $targetPath = Join-Path $formMediaDir $formFile.Name
                        if (-not (Test-Path $targetPath)) {
                            Copy-Item -Path $formFile.FullName -Destination $targetPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                
                $data = $null
            } catch {
                Write-Warning "  [AVISO] Error procesando form $($formDir.Name): $_"
            }
        }
        Write-Host "[OK] Procesados $processed form" -ForegroundColor DarkGreen
    }
    
    Write-Host "[OK] Generación de CSV y copia de media completada" -ForegroundColor DarkGreen
    
    # Calcular tamaño total antes de crear ZIPs
    Write-Host ""
    Write-Host "[INFO] Calculando tamaño total de archivos..." -ForegroundColor DarkCyan
    
    $totalSizeBytes = 0
    $databaseSizeBytes = 0
    $mediaSizeBytes = 0
    
    # Calcular tamaño de database
    if (Test-Path $tempDatabaseDir) {
        $csvFiles = Get-ChildItem -Path $tempDatabaseDir -Filter "*.csv" -File -ErrorAction SilentlyContinue
        foreach ($csvFile in $csvFiles) {
            $databaseSizeBytes += $csvFile.Length
        }
    }
    
    # Calcular tamaño de media
    if (Test-Path $tempMediaDir) {
        $mediaFiles = Get-ChildItem -Path $tempMediaDir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($mediaFile in $mediaFiles) {
            $mediaSizeBytes += $mediaFile.Length
        }
    }
    
    $totalSizeBytes = $databaseSizeBytes + $mediaSizeBytes
    $totalSizeMB = [Math]::Round($totalSizeBytes / 1MB, 2)
    $databaseSizeMB = [Math]::Round($databaseSizeBytes / 1MB, 2)
    $mediaSizeMB = [Math]::Round($mediaSizeBytes / 1MB, 2)
    
    Write-Host "  Tamaño database: $databaseSizeMB MB" -ForegroundColor DarkGray
    Write-Host "  Tamaño media: $mediaSizeMB MB" -ForegroundColor DarkGray
    Write-Host "  Tamaño total: $totalSizeMB MB" -ForegroundColor DarkGray
    
    # Directorio base para los ZIPs
    $zipBasePath = "C:\Users\loren\Desktop\proyectos\pokesearch"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    $zipFiles = @()
    $maxZipSizeMB = 600
    
    # Decidir si crear un solo ZIP o múltiples ZIPs
    if ($totalSizeMB -lt $maxZipSizeMB) {
        # Crear un solo ZIP con todo (database + media)
        Write-Host ""
        Write-Host "[INFO] Tamaño total ($totalSizeMB MB) < $maxZipSizeMB MB, creando un solo ZIP..." -ForegroundColor DarkCyan
        
        $singleZipPath = Join-Path $zipBasePath "poke_searcher_backup.zip"
        
        if (Test-Path $singleZipPath) {
            Remove-Item $singleZipPath -Force -ErrorAction SilentlyContinue
        }
        
        # Crear directorio temporal con estructura completa
        $tempSingleZipDir = Join-Path $env:TEMP "poke_searcher_single_zip"
        if (Test-Path $tempSingleZipDir) {
            Remove-Item $tempSingleZipDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Force -Path $tempSingleZipDir | Out-Null
        
        # Copiar database
        if (Test-Path $tempDatabaseDir) {
            $targetDatabaseDir = Join-Path $tempSingleZipDir "database"
            Copy-Item -Path $tempDatabaseDir -Destination $targetDatabaseDir -Recurse -Force
        }
        
        # Copiar media
        if (Test-Path $tempMediaDir) {
            $targetMediaDir = Join-Path $tempSingleZipDir "media"
            Copy-Item -Path $tempMediaDir -Destination $targetMediaDir -Recurse -Force
        }
        
        # Crear ZIP único
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempSingleZipDir, $singleZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        
        # Limpiar directorio temporal
        Remove-Item $tempSingleZipDir -Recurse -Force -ErrorAction SilentlyContinue
        
        $zipSize = (Get-Item $singleZipPath).Length
        $zipSizeMB = [Math]::Round($zipSize / 1MB, 2)
        Write-Host "  ✅ ZIP único creado: $singleZipPath ($zipSizeMB MB)" -ForegroundColor Green
        $zipFiles += @{
            Path = $singleZipPath
            Type = "complete"
            Size = $zipSizeMB
        }
    } else {
        # Crear múltiples ZIPs: uno para database y varios para media
        Write-Host ""
        Write-Host "[INFO] Tamaño total ($totalSizeMB MB) >= $maxZipSizeMB MB, creando múltiples ZIPs..." -ForegroundColor DarkCyan
        
        # 1. Crear ZIP para database (CSV)
        Write-Host ""
        Write-Host "[INFO] Creando ZIP para database (CSV)..." -ForegroundColor DarkCyan
        $databaseZipPath = Join-Path $zipBasePath "poke_searcher_backup_database.zip"
        
        if (Test-Path $databaseZipPath) {
            Remove-Item $databaseZipPath -Force -ErrorAction SilentlyContinue
        }
        
        if (Test-Path $tempDatabaseDir) {
            $csvFiles = Get-ChildItem -Path $tempDatabaseDir -Filter "*.csv" -File
            if ($csvFiles.Count -gt 0) {
                [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDatabaseDir, $databaseZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
                $zipSize = (Get-Item $databaseZipPath).Length
                $zipSizeMB = [Math]::Round($zipSize / 1MB, 2)
                Write-Host "  ✅ ZIP database creado: $databaseZipPath ($zipSizeMB MB, $($csvFiles.Count) CSV)" -ForegroundColor Green
                $zipFiles += @{
                    Path = $databaseZipPath
                    Type = "database"
                    Size = $zipSizeMB
                }
            } else {
                Write-Host "  ⚠️ No hay archivos CSV para comprimir" -ForegroundColor Yellow
            }
        }
        
        # 2. Crear ZIPs para media (uno por carpeta de media)
        Write-Host ""
        Write-Host "[INFO] Creando ZIPs para media..." -ForegroundColor DarkCyan
        
        if (Test-Path $tempMediaDir) {
            $mediaFolders = Get-ChildItem -Path $tempMediaDir -Directory
            $mediaZipIndex = 1
            
            foreach ($mediaFolder in $mediaFolders) {
                $mediaZipPath = Join-Path $zipBasePath "poke_searcher_backup_media_$($mediaFolder.Name).zip"
                
                if (Test-Path $mediaZipPath) {
                    Remove-Item $mediaZipPath -Force -ErrorAction SilentlyContinue
                }
                
                # Verificar que la carpeta tenga archivos
                $mediaFiles = Get-ChildItem -Path $mediaFolder.FullName -Recurse -File
                if ($mediaFiles.Count -gt 0) {
                    # Crear un directorio temporal con la estructura media/folder
                    $tempMediaZipDir = Join-Path $env:TEMP "poke_searcher_media_zip_$($mediaFolder.Name)"
                    if (Test-Path $tempMediaZipDir) {
                        Remove-Item $tempMediaZipDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    New-Item -ItemType Directory -Force -Path $tempMediaZipDir | Out-Null
                    
                    $mediaSubDir = Join-Path $tempMediaZipDir "media"
                    New-Item -ItemType Directory -Force -Path $mediaSubDir | Out-Null
                    
                    $targetFolder = Join-Path $mediaSubDir $mediaFolder.Name
                    Copy-Item -Path $mediaFolder.FullName -Destination $targetFolder -Recurse -Force
                    
                    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempMediaZipDir, $mediaZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
                    
                    # Limpiar directorio temporal
                    Remove-Item $tempMediaZipDir -Recurse -Force -ErrorAction SilentlyContinue
                    
                    $zipSize = (Get-Item $mediaZipPath).Length
                    $zipSizeMB = [Math]::Round($zipSize / 1MB, 2)
                    Write-Host "  ✅ ZIP media creado: $mediaZipPath ($zipSizeMB MB, $($mediaFiles.Count) archivos)" -ForegroundColor Green
                    $zipFiles += @{
                        Path = $mediaZipPath
                        Type = "media"
                        Folder = $mediaFolder.Name
                        Size = $zipSizeMB
                    }
                    $mediaZipIndex++
                } else {
                    Write-Host "  ⚠️ Carpeta $($mediaFolder.Name) está vacía, omitiendo" -ForegroundColor Yellow
                }
            }
        }
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host "[COMPLETADO] FASE 3: ZIPs generados" -ForegroundColor DarkGreen
    Write-Host "Total de ZIPs creados: $($zipFiles.Count)" -ForegroundColor DarkYellow
    Write-Host ""
    foreach ($zip in $zipFiles) {
        if ($zip.Type -eq "complete") {
            Write-Host "  - ZIP completo: $($zip.Path) ($($zip.Size) MB)" -ForegroundColor DarkGray
        } elseif ($zip.Type -eq "database") {
            Write-Host "  - Database: $($zip.Path) ($($zip.Size) MB)" -ForegroundColor DarkGray
        } else {
            Write-Host "  - Media ($($zip.Folder)): $($zip.Path) ($($zip.Size) MB)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "Sube estos ZIPs a GitHub Releases y proporciona las URLs" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Limpiar directorios temporales
    Write-Host "[INFO] Limpiando directorios temporales..." -ForegroundColor DarkCyan
    Remove-Item $tempOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================
# INICIO DEL SCRIPT
# ============================================================
Clear-Host
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

# Si solo se quiere ejecutar la FASE 3, saltar FASES 1 y 2
if ($OnlyPhase3) {
    Write-Host "=========================================="
    Write-Host "Ejecutando solo FASE 3 (procesamiento y generación de ZIPs)" -ForegroundColor Yellow
    Write-Host "=========================================="
    Write-Host ""
    
    # FASE 3: Procesar datos y generar backup
    $fase3StartTime = Get-Date
    Process-DataForBackup
    $fase3EndTime = Get-Date
    $fase3Duration = $fase3EndTime - $fase3StartTime
    $fase3Hours = [Math]::Floor($fase3Duration.TotalHours)
    $fase3Minutes = [Math]::Floor($fase3Duration.TotalMinutes) % 60
    $fase3Seconds = [Math]::Floor($fase3Duration.TotalSeconds) % 60
    
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "[COMPLETADO] FASE 3: Procesamiento completado" -ForegroundColor DarkGreen
    Write-Host "Tiempo transcurrido: $fase3Hours h $fase3Minutes m $fase3Seconds s" -ForegroundColor Cyan
    Write-Host "=========================================="
    Write-Host ""
    exit
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


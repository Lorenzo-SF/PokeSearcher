# ============================================================
# Script de Descarga Recursiva de PokeAPI
# Descarga todos los datos de la API y crea estructura de carpetas
# Compatible con PowerShell 5.1+
# ============================================================

param(
    [string]$BaseUrl = "https://pokeapi.co/api/v2",
    [string]$BaseDir = "c:\users\loren\Desktop\pokemon_data"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# URL base de la API (sin trailing slash)
$ApiBaseUrl = $BaseUrl.TrimEnd('/')

# Cola de URLs pendientes de procesar
$queue = New-Object System.Collections.Queue
$processedUrls = New-Object System.Collections.Generic.HashSet[string]

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
    # Ejemplo: /pokemon?offset=20&limit=20 -> /pokemon
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
    # Ejemplo: /gender/1 -> /gender/1
    if ($relative -match '^(.+)/(\d+)/?$') {
        $basePath = $matches[1]
        $id = $matches[2]
        $relative = "$basePath/$id"
    }
    
    # Si es solo un número (caso especial), mantenerlo
    if ($relative -match '^\d+$') {
        # Esto no debería pasar normalmente, pero por si acaso
        $relative = $relative
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
        # Verificar si la URL ya fue procesada (existe su data.json o archivo multimedia)
        $urlEstado = "pendiente"
        $urlNormalized = $urlInfo.Url
        if ($urlInfo.Url -match '\?') {
            $urlNormalized = $urlInfo.Url.Substring(0, $urlInfo.Url.IndexOf('?'))
        }
        $urlNormalized = $urlNormalized.TrimEnd('/')
        
        # Verificar si es multimedia (por extensión en la URL)
        $isMedia = Is-MediaUrl $urlInfo.Url
        
        $urlPath = Get-FileSystemPath $urlInfo.Url
        
        # Si es multimedia externa (no de la API base), usar la carpeta del urls.txt
        if ($null -eq $urlPath -and $isMedia) {
            $urlPath = Split-Path $filePath -Parent
        }
        
        if ($null -ne $urlPath) {
            if ($isMedia) {
                # Para multimedia, verificar si existe el archivo
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
                # Para JSON, verificar si existe data.json
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
        # Normalizar URL para comparación (sin query string)
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
                # Actualizar el estado de esta URL
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

# Función para buscar y actualizar el estado de una URL en todos los urls.txt del directorio base
function Update-UrlStatusInParentFiles($url) {
    # Buscar todos los urls.txt en el directorio base
    $allUrlsFiles = Get-ChildItem -Path $BaseDir -Filter "urls.txt" -Recurse -ErrorAction SilentlyContinue
    
    foreach ($urlsFile in $allUrlsFiles) {
        Update-UrlStatusInFile $urlsFile.FullName $url "procesado"
        
        # Verificar si todas las URLs de este archivo están procesadas
        if (Are-AllUrlsProcessed $urlsFile.FullName) {
            Update-UrlsFileStatus $urlsFile.FullName "procesado"
        }
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
    
    # Si no hay URLs o todas están procesadas
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
    # Normalizar URL para comparaciones (quitar trailing slash y query string)
    $normalizedForPath = $url
    if ($url -match '\?') {
        $normalizedForPath = $url.Substring(0, $url.IndexOf('?'))
    }
    $normalizedUrl = $normalizedForPath.TrimEnd('/')
    
    # Verificar si ya fue procesada (usando URL sin query string)
    if ($processedUrls.Contains($normalizedUrl)) {
        return
    }
    
    # Verificar si es una URL de la API base
    if ($normalizedUrl -notmatch "^$([regex]::Escape($ApiBaseUrl))") {
        return
    }
    
    # Verificar si es multimedia - si lo es, no procesar aquí (se procesará en segunda tanda)
    if (Is-MediaUrl $url) {
        $processedUrls.Add($normalizedUrl) | Out-Null
        return
    }
    
    # Obtener ruta del sistema de archivos
    $fsPath = Get-FileSystemPath $url
    if ($null -eq $fsPath) {
        Write-Warning "  [AVISO] No se pudo determinar la ruta para: $url"
        return
    }
    
    # Crear directorio si no existe
    if (-not (Test-Path $fsPath)) {
        New-Item -ItemType Directory -Force -Path $fsPath | Out-Null
    }
    
    $dataJsonPath = Join-Path $fsPath "data.json"
    $urlsTxtPath = Join-Path $fsPath "urls.txt"
    
    # Verificar si ya existe el archivo destino - si existe, usar el contenido del archivo
    # PERO siempre procesar el JSON para regenerar urls.txt con todas las URLs (incluyendo multimedia)
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
    
    # Si no existe o hubo error al leer, descargar
    if ($needsDownload) {
        $downloadResult = Download-Json $url
        
        if ($null -eq $downloadResult) {
            return
        }
        
        # Si resultó ser multimedia (por content-type), ignorar (se procesará en segunda tanda)
        if (-not $downloadResult.IsJson) {
            $processedUrls.Add($normalizedUrl) | Out-Null
            return
        }
        
        $json = $downloadResult.Content
        $jsonRaw = $downloadResult.RawContent
        
        # Guardar data.json solo si se descargó nuevo contenido
        try {
            # Guardar JSON formateado (sin comprimir para legibilidad)
            $json | ConvertTo-Json -Depth 100 | Out-File -FilePath $dataJsonPath -Encoding UTF8
        }
        catch {
            # Si falla por profundidad, guardar el raw
            $jsonRaw | Out-File -FilePath $dataJsonPath -Encoding UTF8
        }
    }
    
    # Es un JSON - usar el contenido (del archivo existente o descargado)
    # SIEMPRE procesar para regenerar urls.txt con todas las URLs multimedia
    if ($null -eq $json) {
        $json = $downloadResult.Content
    }
    if ($null -eq $jsonRaw) {
        $jsonRaw = $downloadResult.RawContent
    }
    
    # Extraer todas las URLs del JSON
    $foundUrls = Extract-UrlsFromJson $json
    
    # Filtrar URLs: incluir URLs de la API base Y URLs multimedia (aunque no sean de la API base)
    $apiUrls = $foundUrls | Where-Object { 
        $url = $_.Url
        # Incluir URLs de la API base
        $isApiUrl = $url -match "^$([regex]::Escape($ApiBaseUrl))"
        # O incluir URLs multimedia (aunque no sean de la API base)
        $isMedia = Is-MediaUrl $url
        return ($isApiUrl -or $isMedia)
    }
    
    # Guardar o actualizar urls.txt
    # Siempre reescribir para asegurar que incluye todas las URLs (incluyendo multimedia)
    Write-UrlsFile $urlsTxtPath $url $apiUrls "pendiente"
    
    # Agregar solo URLs JSON a la cola (excluir multimedia - se procesarán en segunda tanda)
    foreach ($urlInfo in $apiUrls) {
        $foundUrl = $urlInfo.Url
        
        # Saltar URLs multimedia
        if (Is-MediaUrl $foundUrl) {
            continue
        }
        
        # Normalizar para verificar duplicados (sin query string)
        $normalizedForCheck = $foundUrl
        if ($foundUrl -match '\?') {
            $normalizedForCheck = $foundUrl.Substring(0, $foundUrl.IndexOf('?'))
        }
        $normalizedForCheck = $normalizedForCheck.TrimEnd('/')
        if (-not $processedUrls.Contains($normalizedForCheck)) {
            $queue.Enqueue($foundUrl)
        }
    }
    
    # NOTA: No actualizamos el estado en archivos padre en tiempo real para evitar ralentización
    # El estado se actualiza automáticamente cuando se verifica si el archivo existe
    
    # Verificar si todas las URLs de este urls.txt están procesadas
    if (Are-AllUrlsProcessed $urlsTxtPath) {
        Update-UrlsFileStatus $urlsTxtPath "procesado"
    }
    
    # Marcar como procesada (usando URL normalizada sin query string)
    $processedUrls.Add($normalizedUrl) | Out-Null
    
    Write-Host "  [OK] Procesado:  $fsPath" -ForegroundColor Green
}

# Función para extraer todas las URLs multimedia de todos los urls.txt
function Extract-MediaUrlsFromFiles {
    $mediaUrls = New-Object System.Collections.ArrayList
    
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
            # Buscar líneas con URLs que sean multimedia
            # El formato es: ruta: "url" | estado: ... | multimedia: si
            if ($line -match ':\s*"([^"]+)".*multimedia:\s*si') {
                $foundUrl = $matches[1]
                
                # Obtener ruta destino
                $mediaPath = Get-FileSystemPath $foundUrl
                
                # Si la URL no es de la API base (es multimedia externa), usar la carpeta del urls.txt
                if ($null -eq $mediaPath) {
                    $mediaPath = Split-Path $urlsFile.FullName -Parent
                }
                
                if ($null -ne $mediaPath) {
                    $fileName = Split-Path $foundUrl -Leaf
                    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -eq '/') {
                        # Si no hay nombre de archivo, generar uno basado en la URL
                        $fileName = "media_file_" + ($foundUrl -replace '[^\w]', '_').Substring(0, [Math]::Min(50, ($foundUrl -replace '[^\w]', '_').Length))
                    }
                    $mediaFilePath = Join-Path $mediaPath $fileName
                    
                    # Verificar si ya existe
                    if (-not (Test-Path $mediaFilePath)) {
                        $null = $mediaUrls.Add(@{
                            Url = $foundUrl
                            DestPath = $mediaFilePath
                            ParentPath = $mediaPath
                        })
                    }
                }
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
    
    # Procesar por lotes
    for ($i = 0; $i -lt $mediaUrls.Count; $i += $batchSize) {
        $batch = $mediaUrls[$i..([Math]::Min($i + $batchSize - 1, $mediaUrls.Count - 1))]
        
        Write-Host "[LOTE] Procesando lote $([Math]::Floor($i / $batchSize) + 1) - Archivos $($i + 1) a $([Math]::Min($i + $batchSize, $totalFiles)) de $totalFiles" -ForegroundColor DarkYellow
        
        # Crear jobs en paralelo para este lote
        $jobs = @()
        foreach ($mediaFile in $batch) {
            # Verificar si ya existe antes de descargar
            if (Test-Path $mediaFile.DestPath) {
                Write-Host "  [SKIP] Ya existe: $($mediaFile.Url)" -ForegroundColor DarkYellow
                $downloaded++
                continue
            }
            
            # Crear job para descargar
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
        
        # Esperar a que terminen todos los jobs del lote
        if ($jobs.Count -gt 0) {
            $jobs | Wait-Job | Out-Null
            
            # Procesar resultados
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
            # Buscar líneas con URLs, estado pendiente y que NO sean multimedia
            if ($line -match '`"([^`"]+)`".*\| estado: pendiente.*multimedia: no') {
                $foundUrl = $matches[1]
                
                # Normalizar para verificar duplicados
                $normalizedUrl = $foundUrl
                if ($foundUrl -match '\?') {
                    $normalizedUrl = $foundUrl.Substring(0, $foundUrl.IndexOf('?'))
                }
                $normalizedUrl = $normalizedUrl.TrimEnd('/')
                
                # Verificar si la URL ya tiene su data.json
                $urlPath = Get-FileSystemPath $foundUrl
                if ($null -ne $urlPath) {
                    $urlDataJson = Join-Path $urlPath "data.json"
                    if (Test-Path $urlDataJson) {
                        # Ya existe, actualizar estado y marcar como procesada
                        Update-UrlStatusInFile $urlsFile.FullName $foundUrl "procesado"
                        $processedUrls.Add($normalizedUrl) | Out-Null
                        continue
                    }
                }
                
                # Si no está procesada, agregar a la cola (solo JSONs)
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
# INICIO DEL SCRIPT
# ============================================================

Write-Host "=========================================="
Write-Host "Descargador de PokeAPI"
Write-Host "=========================================="
Write-Host "URL Base: $ApiBaseUrl"
Write-Host "Directorio Base: $BaseDir"
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
$maxIterations = 100000  # Límite de seguridad

while ($queue.Count -gt 0 -and $totalProcessed -lt $maxIterations) {
    $url = $queue.Dequeue()
    Process-Url $url
    $totalProcessed++
    
    # Mostrar progreso cada 50 URLs
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

# Extraer todas las URLs multimedia de todos los urls.txt
$mediaUrls = Extract-MediaUrlsFromFiles

# Descargar multimedia en paralelo por lotes
Download-MediaFilesInParallel -mediaUrls $mediaUrls -batchSize 10

$fase2EndTime = Get-Date
$fase2Duration = $fase2EndTime - $fase2StartTime
$fase2Hours = [Math]::Floor($fase2Duration.TotalHours)
$fase2Minutes = [Math]::Floor($fase2Duration.TotalMinutes) % 60
$fase2Seconds = [Math]::Floor($fase2Duration.TotalSeconds) % 60

$totalStartTime = $fase1StartTime
$totalEndTime = $fase2EndTime
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
Write-Host "  TOTAL: $totalHours h $totalMinutes m $totalSeconds s" -ForegroundColor Yellow
Write-Host ""
Write-Host "Datos guardados en: $BaseDir"
Write-Host "=========================================="


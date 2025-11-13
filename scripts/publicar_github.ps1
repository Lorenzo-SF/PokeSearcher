# Script para publicar el repositorio en GitHub
# Requiere que hayas creado el repositorio en GitHub primero

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubUsername,
    
    [Parameter(Mandatory=$true)]
    [string]$RepositoryName = "pokesearch"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Publicando repositorio en GitHub" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que estamos en un repositorio git
if (-not (Test-Path .git)) {
    Write-Error "No se encontró un repositorio git. Asegúrate de estar en el directorio raíz del proyecto."
    exit 1
}

# Verificar estado
Write-Host "[1/4] Verificando estado del repositorio..." -ForegroundColor Yellow
$status = git status --porcelain
if ($status) {
    Write-Warning "Hay cambios sin commitear. ¿Deseas continuar? (S/N)"
    $response = Read-Host
    if ($response -ne "S" -and $response -ne "s") {
        Write-Host "Operación cancelada." -ForegroundColor Red
        exit 1
    }
}

# Verificar si ya existe un remoto
Write-Host "[2/4] Verificando remotos existentes..." -ForegroundColor Yellow
$remotes = git remote -v
if ($remotes) {
    Write-Host "Remotos existentes:" -ForegroundColor Cyan
    Write-Host $remotes
    Write-Host ""
    Write-Warning "¿Deseas reemplazar el remoto 'origin'? (S/N)"
    $response = Read-Host
    if ($response -eq "S" -or $response -eq "s") {
        git remote remove origin 2>$null
    } else {
        Write-Host "Operación cancelada." -ForegroundColor Red
        exit 1
    }
}

# Añadir remoto
Write-Host "[3/4] Añadiendo remoto de GitHub..." -ForegroundColor Yellow
$remoteUrl = "https://github.com/$GitHubUsername/$RepositoryName.git"
Write-Host "URL del remoto: $remoteUrl" -ForegroundColor Cyan

try {
    git remote add origin $remoteUrl
    Write-Host "✅ Remoto añadido correctamente" -ForegroundColor Green
} catch {
    Write-Error "Error al añadir el remoto: $_"
    exit 1
}

# Hacer push
Write-Host "[4/4] Subiendo código a GitHub..." -ForegroundColor Yellow
Write-Host "Esto puede tardar unos minutos..." -ForegroundColor Cyan
Write-Host ""

try {
    # Primero intentar push con --set-upstream
    git push -u origin master
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "✅ Repositorio publicado exitosamente!" -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "URL del repositorio: https://github.com/$GitHubUsername/$RepositoryName" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Error "Error al hacer push. Verifica que el repositorio existe en GitHub y que tienes permisos."
        Write-Host ""
        Write-Host "Pasos manuales:" -ForegroundColor Yellow
        Write-Host "1. Ve a https://github.com/new" -ForegroundColor White
        Write-Host "2. Crea un nuevo repositorio llamado '$RepositoryName'" -ForegroundColor White
        Write-Host "3. NO inicialices con README, .gitignore o licencia" -ForegroundColor White
        Write-Host "4. Ejecuta este script nuevamente" -ForegroundColor White
        exit 1
    }
} catch {
    Write-Error "Error al hacer push: $_"
    Write-Host ""
    Write-Host "Si el repositorio no existe en GitHub, créalo primero:" -ForegroundColor Yellow
    Write-Host "1. Ve a https://github.com/new" -ForegroundColor White
    Write-Host "2. Crea un nuevo repositorio llamado '$RepositoryName'" -ForegroundColor White
    Write-Host "3. NO inicialices con README, .gitignore o licencia" -ForegroundColor White
    Write-Host "4. Ejecuta este script nuevamente" -ForegroundColor White
    exit 1
}


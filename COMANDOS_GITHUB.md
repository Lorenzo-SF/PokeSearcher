# Comandos para publicar en GitHub

## Paso 1: Crear el repositorio en GitHub
1. Ve a https://github.com/new
2. Nombre: `pokesearch`
3. Descripción: "Aplicación Flutter para buscar y explorar Pokémon"
4. Elige Público o Privado
5. **NO marques** "Initialize this repository with a README"
6. Clic en "Create repository"

## Paso 2: Ejecutar estos comandos (reemplaza TU_USUARIO con tu nombre de usuario de GitHub)

```powershell
# Añadir el remoto (reemplaza TU_USUARIO con tu usuario de GitHub)
git remote add origin https://github.com/TU_USUARIO/pokesearch.git

# Verificar que se añadió correctamente
git remote -v

# Subir el código
git push -u origin master
```

## Alternativa: Usar el script automático

```powershell
.\publicar_github.ps1 -GitHubUsername TU_USUARIO
```

## Si el remoto ya existe y quieres reemplazarlo

```powershell
git remote remove origin
git remote add origin https://github.com/TU_USUARIO/pokesearch.git
git push -u origin master
```


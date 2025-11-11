# Instrucciones para Configurar el Icono de la App

El icono de la app debe usar `assets/pokeball.svg`, pero **`flutter_launcher_icons` NO soporta SVG directamente**. Necesitas convertir el SVG a PNG primero.

## Pasos Rápidos

### 1. Convertir SVG a PNG

**Opción A: Conversor Online (Más Fácil)**
1. Ve a https://convertio.co/svg-png/
2. Sube `assets/pokeball.svg`
3. Configura el tamaño a **1024x1024 píxeles**
4. Descarga el PNG
5. Guárdalo como `assets/pokeball_icon.png` en tu proyecto

**Opción B: Inkscape (Si está instalado)**
```powershell
inkscape assets/pokeball.svg --export-filename=assets/pokeball_icon.png --export-width=1024 --export-height=1024
```

**Opción C: ImageMagick (Si está instalado)**
```powershell
magick assets/pokeball.svg -resize 1024x1024 assets/pokeball_icon.png
```

### 2. Actualizar pubspec.yaml

Descomenta estas líneas en `pubspec.yaml`:
```yaml
flutter_launcher_icons:
  # ... otras configuraciones ...
  image_path: "assets/pokeball_icon.png"  # Descomenta esta línea
  adaptive_icon_foreground: "assets/pokeball_icon.png"  # Descomenta esta línea
```

### 3. Generar los Iconos

Ejecuta estos comandos:
```powershell
cd poke_searcher
flutter pub get
flutter pub run flutter_launcher_icons
```

### 4. Reconstruir la App

```powershell
flutter clean
flutter run
```

## Verificar que Funcionó

- **Android**: El icono debería aparecer en el launcher
- **iOS**: El icono debería aparecer en el home screen
- **Web**: El favicon debería cambiar
- **Windows**: El icono del ejecutable debería cambiar

## Nota Importante

Si después de seguir estos pasos el icono no cambia:
1. Asegúrate de hacer `flutter clean` antes de `flutter run`
2. En Android, desinstala la app completamente y vuelve a instalar
3. En iOS, limpia el build folder en Xcode
4. Verifica que `assets/pokeball_icon.png` existe y tiene 1024x1024 píxeles


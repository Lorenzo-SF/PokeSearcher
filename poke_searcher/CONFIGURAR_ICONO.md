# Configurar Icono de la App

El icono de la app debe usar `assets/pokeball.svg`, pero `flutter_launcher_icons` no soporta SVG directamente. 

## Opción 1: Convertir SVG a PNG (Recomendado)

1. Convierte `assets/pokeball.svg` a PNG de 1024x1024 píxeles usando:
   - [Convertio](https://convertio.co/svg-png/)
   - [CloudConvert](https://cloudconvert.com/svg-to-png)
   - Inkscape: `inkscape assets/pokeball.svg --export-filename=assets/pokeball_icon.png --export-width=1024 --export-height=1024`
   - ImageMagick: `magick assets/pokeball.svg -resize 1024x1024 assets/pokeball_icon.png`

2. Guarda el PNG como `assets/pokeball_icon.png`

3. Actualiza `pubspec.yaml`:
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  web:
    generate: true
  windows:
    generate: true
  macos:
    generate: true
  linux:
    generate: true
  image_path: "assets/pokeball_icon.png"
  min_sdk_android: 21
  adaptive_icon_background: "#DC143C"
  adaptive_icon_foreground: "assets/pokeball_icon.png"
```

4. Ejecuta:
```bash
flutter pub run flutter_launcher_icons
```

## Opción 2: Configuración Manual (Android)

Si prefieres usar el SVG directamente, puedes configurarlo manualmente en Android:

1. Convierte el SVG a los tamaños necesarios para Android
2. Coloca los archivos en `android/app/src/main/res/mipmap-*/ic_launcher.png`
3. Para adaptive icons, configura en `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`


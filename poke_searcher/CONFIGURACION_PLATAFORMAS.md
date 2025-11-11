# Configuración de Plataformas - PokeSearch

Este documento describe cómo configurar y ejecutar PokeSearch en diferentes plataformas.

## 📱 Android (Móvil y Tablet)

### Requisitos
- Android SDK instalado
- Android Studio o Flutter SDK configurado
- Dispositivo Android o emulador

### Configuración
La aplicación está configurada para:
- **Versión mínima**: Android 4.0.3 (API 15)
- **Versión objetivo**: Android 14 (API 34)
- **Soporte**: Móviles y tablets (portrait y landscape)

### Ejecutar

```bash
# Listar dispositivos disponibles
flutter devices

# Ejecutar en dispositivo/emulador
flutter run

# Ejecutar en modo release
flutter run --release

# Ejecutar en dispositivo específico
flutter run -d <device-id>
```

### Build APK

```bash
# APK de debug
flutter build apk

# APK de release
flutter build apk --release

# APK split por ABI (más pequeño)
flutter build apk --split-per-abi
```

## 🪟 Windows

### Requisitos
- Windows 10 o superior
- Visual Studio 2019 o superior con:
  - Desktop development with C++
  - Windows 10 SDK

### Configuración
La aplicación está lista para ejecutarse en Windows sin configuración adicional.

### Ejecutar

```bash
# Ejecutar en modo debug
flutter run -d windows

# Ejecutar en modo release
flutter run -d windows --release
```

### Build Ejecutable

```bash
# Build de release
flutter build windows --release

# El ejecutable estará en:
# build/windows/runner/Release/poke_searcher.exe
```

## 🌐 Web (Chrome/Edge/Firefox)

### Requisitos
- Chrome, Edge o Firefox actualizado
- Para desarrollo: Flutter SDK con soporte web

### Configuración WebAssembly (Opcional pero Recomendado)

Para usar la base de datos SQLite en web, necesitas archivos WebAssembly:

1. **Descargar archivos necesarios:**
   - `sqlite3.wasm` desde: https://github.com/simolus3/sqlite3.dart/releases
   - `drift_worker.js` desde: https://github.com/simolus3/drift/releases

2. **Colocar archivos en `web/`:**
   ```
   web/
     ├── sqlite3.wasm
     ├── drift_worker.js
     ├── index.html
     └── ...
   ```

3. **Nota**: Si no configuras WebAssembly, la aplicación funcionará pero la base de datos tendrá funcionalidad limitada en web.

### Ejecutar

```bash
# Ejecutar en Chrome (recomendado)
flutter run -d chrome

# Ejecutar con renderer específico
flutter run -d chrome --web-renderer canvaskit

# Ejecutar en modo release
flutter run -d chrome --release
```

### Build Web

```bash
# Build de release para web
flutter build web --release

# Build con renderer específico
flutter build web --release --web-renderer canvaskit

# Los archivos estarán en: build/web/
```

### Desplegar Web

Los archivos en `build/web/` pueden desplegarse en cualquier servidor web estático:
- Firebase Hosting
- GitHub Pages
- Netlify
- Vercel
- Servidor propio

## 🔧 Configuración Común

### Generar código de Drift

Antes de ejecutar en cualquier plataforma, asegúrate de generar el código:

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Verificar configuración

```bash
# Verificar que Flutter detecta todas las plataformas
flutter doctor

# Ver dispositivos disponibles
flutter devices
```

## 🚀 Desarrollo Rápido

### Scripts recomendados (PowerShell)

**Ejecutar en Android:**
```powershell
flutter run
```

**Ejecutar en Windows:**
```powershell
flutter run -d windows
```

**Ejecutar en Web:**
```powershell
flutter run -d chrome
```

**Build para todas las plataformas:**
```powershell
# Android
flutter build apk --release

# Windows
flutter build windows --release

# Web
flutter build web --release
```

## 📝 Notas Importantes

1. **Primera ejecución**: La primera vez que ejecutes en cada plataforma, Flutter descargará dependencias específicas de la plataforma.

2. **Hot Reload**: Funciona en todas las plataformas durante el desarrollo.

3. **Base de datos**: 
   - Android/Windows: SQLite nativo (funciona perfectamente)
   - Web: Requiere WebAssembly para funcionalidad completa

4. **Orientación**: La aplicación soporta portrait y landscape en todas las plataformas.

5. **Tablets**: La aplicación está optimizada para tablets Android y se adapta automáticamente al tamaño de pantalla.

## 🐛 Solución de Problemas

### Android
- Si hay problemas con minSdk, verifica `android/app/build.gradle.kts`
- Para problemas de permisos, revisa `AndroidManifest.xml`

### Windows
- Asegúrate de tener Visual Studio con C++ instalado
- Verifica que Windows SDK esté instalado

### Web
- Si la base de datos no funciona, descarga los archivos WASM
- Usa Chrome para mejor compatibilidad durante desarrollo
- Para producción, considera usar un backend para la base de datos


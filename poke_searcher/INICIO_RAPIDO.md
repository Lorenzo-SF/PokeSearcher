# 🚀 Inicio Rápido - PokeSearch

Guía rápida para empezar a desarrollar PokeSearch.

## ⚡ Inicio en 3 Pasos

### 1. Instalar Dependencias
```powershell
flutter pub get
```

### 2. Generar Código
```powershell
flutter pub run build_runner build --delete-conflicting-outputs
```

### 3. Ejecutar
```powershell
.\ejecutar.ps1
```

¡Listo! La aplicación se ejecutará en la plataforma que selecciones.

## 📱 Plataformas Disponibles

### ✅ Android (Móvil y Tablet)
- **Configuración**: Lista para usar
- **Versión mínima**: Android 4.0.3 (API 15)
- **Ejecutar**: `.\ejecutar.ps1 android` o `flutter run`

### ✅ Windows
- **Configuración**: Lista para usar
- **Requisitos**: Visual Studio con C++ (ya instalado si Flutter funciona)
- **Ejecutar**: `.\ejecutar.ps1 windows` o `flutter run -d windows`

### ✅ Web
- **Configuración**: Básica lista, WebAssembly opcional
- **Ejecutar**: `.\ejecutar.ps1 web` o `flutter run -d chrome`
- **WebAssembly** (opcional): `.\configurar_web.ps1` para funcionalidad completa de BD

## 🛠️ Comandos Útiles

### Desarrollo
```powershell
# Ver dispositivos disponibles
flutter devices

# Hot reload (presiona 'r' en la consola)
# Hot restart (presiona 'R' en la consola)

# Limpiar build
flutter clean
```

### Builds de Producción
```powershell
# Android APK
flutter build apk --release

# Windows ejecutable
flutter build windows --release

# Web
flutter build web --release
```

## 📚 Documentación Completa

- **Configuración detallada**: [CONFIGURACION_PLATAFORMAS.md](CONFIGURACION_PLATAFORMAS.md)
- **README principal**: [README.md](README.md)

## 🐛 Problemas Comunes

### "No se encuentra Flutter"
- Verifica que Flutter esté en el PATH
- Ejecuta `flutter doctor` para diagnosticar

### "Error al generar código"
- Ejecuta: `flutter clean`
- Luego: `flutter pub get`
- Finalmente: `flutter pub run build_runner build --delete-conflicting-outputs`

### "No se puede ejecutar en Windows"
- Instala Visual Studio con "Desktop development with C++"
- Verifica que Windows SDK esté instalado

### "Base de datos no funciona en web"
- Ejecuta `.\configurar_web.ps1` para configurar WebAssembly
- O descarga manualmente los archivos WASM (ver CONFIGURACION_PLATAFORMAS.md)

## 💡 Tips

1. **Primera vez**: La primera ejecución puede tardar más (descarga dependencias)
2. **Hot Reload**: Funciona en todas las plataformas durante desarrollo
3. **Orientación**: La app soporta portrait y landscape automáticamente
4. **Tablets**: Se adapta automáticamente al tamaño de pantalla

## 🎯 Próximos Pasos

1. ✅ Proyecto configurado
2. ⏳ Implementar Splash Screen
3. ⏳ Implementar Pantalla de Regiones
4. ⏳ Implementar Sistema de Descarga
5. ⏳ Implementar UI completa

---

**¿Listo para empezar?** Ejecuta `.\ejecutar.ps1` y selecciona tu plataforma preferida.


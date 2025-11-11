# PokeSearch

Aplicación multiplataforma de Pokédex desarrollada con Flutter y Drift.

## Características

- **Offline First**: Funciona completamente sin conexión a internet después de la descarga inicial
- **Multiplataforma**: Soporta Android, iOS, Web, Windows, macOS y Linux
- **Base de datos local**: Usa Drift (SQLite) para almacenamiento local eficiente
- **Diseño moderno**: Interfaz minimalista inspirada en el diseño de la Pokédex original
- **Responsive**: Adaptado para móviles, tablets y escritorio (portrait y landscape)

## Requisitos

- Flutter SDK 3.9.2 o superior
- Dart 3.9.2 o superior
- Android SDK (para desarrollo Android)
- Xcode (para desarrollo iOS, solo en macOS)

## Instalación

1. Clonar el repositorio (si aplica):
```bash
git clone <repository-url>
cd poke_searcher
```

2. Instalar dependencias:
```bash
flutter pub get
```

3. Generar código de Drift:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. (Opcional) Configurar WebAssembly para web:
```powershell
.\configurar_web.ps1
```

> 💡 **Tip**: Usa `.\ejecutar.ps1` para ejecutar la aplicación fácilmente en cualquier plataforma.

## Ejecución Rápida

### Usando Scripts (Recomendado - Windows)

**Ejecutar en cualquier plataforma:**
```powershell
.\ejecutar.ps1
```

**Ejecutar en plataforma específica:**
```powershell
.\ejecutar.ps1 android
.\ejecutar.ps1 windows
.\ejecutar.ps1 web
```

**Configurar WebAssembly para web:**
```powershell
.\configurar_web.ps1
```

### Ejecución Manual

#### Android (Móvil y Tablet)
```bash
flutter run
# O especificar dispositivo
flutter devices
flutter run -d <device-id>
```

#### Windows
```bash
flutter run -d windows
```

#### Web (Chrome)
**Nota**: Para funcionalidad completa de base de datos en web, configura WebAssembly primero.

1. **Configurar WebAssembly (opcional pero recomendado):**
   ```powershell
   .\configurar_web.ps1
   ```
   O descarga manualmente:
   - `sqlite3.wasm` desde [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases)
   - `drift_worker.js` desde [drift releases](https://github.com/simolus3/drift/releases)
   - Colocar ambos en el directorio `web/`

2. **Ejecutar:**
   ```bash
   flutter run -d chrome
   ```

**Nota**: La aplicación funcionará en web sin WebAssembly, pero la base de datos tendrá funcionalidad limitada.

### Otras Plataformas

#### iOS (solo en macOS)
```bash
flutter run -d ios
```

#### macOS
```bash
flutter run -d macos
```

#### Linux
```bash
flutter run -d linux
```

> 📖 **Documentación detallada**: Ver [CONFIGURACION_PLATAFORMAS.md](CONFIGURACION_PLATAFORMAS.md) para instrucciones completas de configuración y build.

## Estructura del Proyecto

```
lib/
├── database/          # Modelo de datos con Drift
│   ├── tables/       # Definiciones de tablas
│   ├── views/        # Vistas optimizadas
│   └── daos/         # Data Access Objects
├── models/           # Modelos de dominio y mappers
├── services/         # Servicios (descarga, configuración, almacenamiento)
└── main.dart         # Punto de entrada de la aplicación
```

## Desarrollo

### Plataformas Soportadas

La aplicación está configurada para funcionar en todas las plataformas que Flutter soporta:

- ✅ **Android** (API 15+)
- ✅ **iOS** (iOS 12+)
- ✅ **Web** (Chrome, Firefox, Safari, Edge)
- ✅ **Windows** (Windows 10+)
- ✅ **macOS** (macOS 10.14+)
- ✅ **Linux** (Ubuntu 18.04+)

### Base de Datos

- **Plataformas nativas**: Usa SQLite a través de `sqlite3_flutter_libs`
- **Web**: Usa IndexedDB a través de `drift_web`

### Configuración

La aplicación detecta automáticamente la plataforma y configura la base de datos apropiadamente. No se requiere configuración adicional.

## Próximas Funcionalidades

- [ ] Splash screen con animación de Pokéballs
- [ ] Pantalla principal con carrusel de regiones
- [ ] Detalles de región y Pokédex
- [ ] Vista de Pokémon con información completa
- [ ] Búsqueda y filtros
- [ ] Menú lateral de navegación
- [ ] Configuración de tema e idioma

## Licencia

Este proyecto es privado y no está destinado a publicación pública.

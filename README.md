# PokeSearch

Aplicación Flutter para buscar y explorar información sobre Pokémon, con soporte offline y descarga de datos desde Cloudflare.

## Características

- 🔍 Búsqueda de Pokémon por región
- 📱 Interfaz moderna y responsive
- 🌐 Soporte offline completo
- 🎨 Visualización de tipos con colores personalizados
- 🔊 Reproducción de cries de Pokémon
- 🗣️ Text-to-Speech (TTS) para descripciones
- 📊 Información detallada de cada Pokémon
- 🎯 Movimientos, habilidades y estadísticas

## Tecnologías

- **Flutter** - Framework multiplataforma
- **Drift** - ORM para SQLite
- **PokeAPI** - Fuente de datos
- **Cloudflare** - Almacenamiento de backup ZIP

## Estructura del Proyecto

```
pokesearch/
├── poke_searcher/          # Aplicación Flutter principal
│   ├── lib/               # Código fuente Dart
│   ├── assets/            # Recursos (imágenes, sonidos)
│   └── ...
├── scripts/               # Scripts PowerShell
│   ├── descargar_pokeapi.ps1  # Descarga datos de PokeAPI
│   └── generar_sql.ps1        # Genera CSV desde JSONs
└── README.md
```

## Instalación

1. Clonar el repositorio:
```bash
git clone https://github.com/TU_USUARIO/pokesearch.git
cd pokesearch
```

2. Instalar dependencias:
```bash
cd poke_searcher
flutter pub get
```

3. Generar datos iniciales (opcional):
```powershell
.\scripts\descargar_pokeapi.ps1
```

4. Ejecutar la aplicación:
```bash
flutter run
```

## Configuración

### Backup ZIP desde Cloudflare

La aplicación descarga automáticamente un ZIP con todos los datos desde Cloudflare en la primera ejecución.

Para configurar la URL del backup:

1. Editar `poke_searcher/lib/services/backup/backup_processor.dart`
2. Actualizar la constante `_backupZipUrl` con tu URL de Cloudflare

```dart
static const String _backupZipUrl = 'https://tu-dominio.com/poke_searcher_backup.zip';
```

## Scripts

### `descargar_pokeapi.ps1`

Descarga todos los datos de PokeAPI y genera un ZIP con:
- Archivos CSV para la base de datos
- Archivos multimedia (imágenes y sonidos)

```powershell
.\scripts\descargar_pokeapi.ps1
```

El ZIP se genera en: `poke_searcher_backup.zip`

## Requisitos

- Flutter SDK (última versión estable)
- PowerShell 5.1+ (para scripts)
- Git

## Licencia

Este proyecto es de código abierto y está disponible bajo la licencia MIT.

## Autor

Loreno


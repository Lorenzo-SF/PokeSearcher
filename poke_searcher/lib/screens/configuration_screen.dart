import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/language_dao.dart';
import '../database/daos/generation_dao.dart';
import '../database/daos/version_group_dao.dart';

class ConfigurationScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;

  const ConfigurationScreen({
    super.key,
    required this.database,
    required this.appConfig,
  });

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  String _selectedTheme = 'system';
  String? _selectedLanguage;
  List<Language> _availableLanguages = [];
  bool _isLoadingLanguages = true;
  bool _isResettingDatabase = false;
  
  // Configuración de imágenes de tipos
  List<Generation> _availableGenerations = [];
  List<VersionGroup> _availableVersionGroups = [];
  int? _selectedGenerationId;
  int? _selectedVersionGroupId;
  bool _isLoadingGenerations = true;
  bool _isLoadingVersionGroups = false;

  @override
  void initState() {
    super.initState();
    _selectedTheme = widget.appConfig.theme;
    _selectedLanguage = widget.appConfig.language;
    _selectedGenerationId = widget.appConfig.typeImageGenerationId;
    _selectedVersionGroupId = widget.appConfig.typeImageVersionGroupId;
    _loadLanguages();
    _loadGenerations();
  }

  Future<void> _loadLanguages() async {
    try {
      final languageDao = LanguageDao(widget.database);
      final languages = await languageDao.getAllLanguages();
      setState(() {
        _availableLanguages = languages;
        _isLoadingLanguages = false;
      });
    } catch (e) {
      setState(() => _isLoadingLanguages = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar idiomas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _saveTheme(String theme) async {
    await widget.appConfig.setTheme(theme);
    setState(() {
      _selectedTheme = theme;
    });
    // Notificar al MaterialApp para que actualice el tema
    if (mounted) {
      Navigator.of(context).pop();
      // Forzar rebuild del MaterialApp
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ConfigurationScreen(
            database: widget.database,
            appConfig: widget.appConfig,
          ),
        ),
      );
    }
  }

  Future<void> _saveLanguage(String? languageCode) async {
    if (languageCode == null) {
      await widget.appConfig.setLanguage('');
    } else {
      await widget.appConfig.setLanguage(languageCode);
    }
    setState(() {
      _selectedLanguage = languageCode;
    });
  }
  
  Future<void> _loadGenerations() async {
    try {
      final generationDao = GenerationDao(widget.database);
      final generations = await generationDao.getAllGenerations();
      setState(() {
        _availableGenerations = generations;
        _isLoadingGenerations = false;
      });
      
      // Si hay una generación seleccionada, cargar sus version groups
      if (_selectedGenerationId != null) {
        await _loadVersionGroups(_selectedGenerationId!);
      }
    } catch (e) {
      setState(() => _isLoadingGenerations = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar generaciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _loadVersionGroups(int generationId) async {
    setState(() {
      _isLoadingVersionGroups = true;
      _availableVersionGroups = [];
    });
    
    try {
      final versionGroupDao = VersionGroupDao(widget.database);
      final versionGroups = await versionGroupDao.getVersionGroupsByGeneration(generationId);
      setState(() {
        _availableVersionGroups = versionGroups;
        _isLoadingVersionGroups = false;
      });
      
      // Si el version group seleccionado no está en la lista, limpiarlo
      if (_selectedVersionGroupId != null) {
        final exists = versionGroups.any((vg) => vg.id == _selectedVersionGroupId);
        if (!exists) {
          await _saveVersionGroup(null);
        }
      }
    } catch (e) {
      setState(() => _isLoadingVersionGroups = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar versiones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _saveGeneration(int? generationId) async {
    await widget.appConfig.setTypeImageGenerationId(generationId);
    setState(() {
      _selectedGenerationId = generationId;
      _selectedVersionGroupId = null; // Limpiar versión al cambiar generación
    });
    await widget.appConfig.setTypeImageVersionGroupId(null);
    
    // Cargar version groups de la nueva generación
    if (generationId != null) {
      await _loadVersionGroups(generationId);
    } else {
      setState(() {
        _availableVersionGroups = [];
      });
    }
  }
  
  Future<void> _saveVersionGroup(int? versionGroupId) async {
    await widget.appConfig.setTypeImageVersionGroupId(versionGroupId);
    setState(() {
      _selectedVersionGroupId = versionGroupId;
    });
  }

  /// Obtener el nombre del idioma en su propio idioma
  String _getLanguageDisplayName(Language language) {
    // Si tiene officialName, usarlo
    if (language.officialName != null && language.officialName!.isNotEmpty) {
      return language.officialName!;
    }
    
    // Mapa de nombres localizados para idiomas comunes (sin kanji)
    final localizedNames = {
      'ja-Hrkt': 'Japanese',
      'roomaji': 'Romaji',
      'ko': '한국어',
      'zh-Hant': '繁體中文',
      'fr': 'Français',
      'de': 'Deutsch',
      'es': 'Español',
      'it': 'Italiano',
      'en': 'English',
      'ja': 'Japanese',
      'zh-Hans': '简体中文',
      'pt-BR': 'Português',
    };
    
    // Buscar por name o iso639
    final name = language.name;
    final iso639 = language.iso639;
    
    if (localizedNames.containsKey(name)) {
      return localizedNames[name]!;
    }
    if (iso639 != null && localizedNames.containsKey(iso639)) {
      return localizedNames[iso639]!;
    }
    
    // Fallback: capitalizar el nombre
    if (name.isNotEmpty) {
      return name[0].toUpperCase() + name.substring(1);
    }
    
    return language.name;
  }

  /// Forzar recarga de la base de datos: borra la DB y cierra la app
  Future<void> _forceResetDatabase() async {
    if (_isResettingDatabase) return;

    // Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Recargar base de datos?'),
        content: const Text(
          'Esto borrará todos los datos de la base de datos y cerrará la aplicación. '
          'Al reiniciar, la aplicación cargará los datos desde los archivos CSV como si fuera la primera ejecución.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Recargar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isResettingDatabase = true);

    try {
      // Cerrar la conexión de la base de datos
      await widget.database.close();

      // Obtener el path del archivo de la base de datos
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, 'poke_search.db'));

      // Eliminar el archivo de la base de datos si existe
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      // También eliminar archivos relacionados (wal, shm)
      final walFile = File(p.join(dbFolder.path, 'poke_search.db-wal'));
      final shmFile = File(p.join(dbFolder.path, 'poke_search.db-shm'));
      
      if (await walFile.exists()) {
        await walFile.delete();
      }
      if (await shmFile.exists()) {
        await shmFile.delete();
      }

      // Marcar como no completada la descarga inicial
      await widget.appConfig.setInitialDownloadCompleted(false);

      if (mounted) {
        // Cerrar la aplicación
        if (Platform.isAndroid || Platform.isIOS) {
          // En móviles, usar SystemNavigator
          SystemNavigator.pop();
        } else {
          // En desktop, usar exit
          exit(0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResettingDatabase = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al recargar base de datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector de tema
                _buildThemeSection(),
                const SizedBox(height: 32),
                
                // Selector de idioma
                _buildLanguageSection(),
                const SizedBox(height: 32),
                
                // Selector de generación y versión para imágenes de tipos
                _buildTypeImageSection(),
                const SizedBox(height: 32),
                
                // Control de datos
                _buildDataControlSection(),
              ],
            ),
          ),
          // Botón de volver
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tema',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildThemeButton(
                'Claro',
                'light',
                Icons.light_mode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildThemeButton(
                'Oscuro',
                'dark',
                Icons.dark_mode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildThemeButton(
                'Sistema',
                'system',
                Icons.phone_android,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeButton(String label, String value, IconData icon) {
    final isSelected = _selectedTheme == value;
    return ElevatedButton(
      onPressed: () => _saveTheme(value),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        foregroundColor: isSelected
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildLanguageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Idioma',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingLanguages)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Botón "Sistema"
              _buildLanguageButton(
                'Sistema',
                null,
                Icons.language,
              ),
              // Botones de idiomas disponibles
              ..._availableLanguages.map((language) => _buildLanguageButton(
                    _getLanguageDisplayName(language),
                    language.iso639 ?? language.name,
                    Icons.translate,
                  )),
            ],
          ),
      ],
    );
  }

  Widget _buildLanguageButton(String label, String? languageCode, IconData icon) {
    final isSelected = _selectedLanguage == languageCode;
    return ElevatedButton.icon(
      onPressed: () => _saveLanguage(languageCode),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        foregroundColor: isSelected
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Imágenes de Tipos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Selecciona la generación y el juego para las imágenes de tipos de Pokémon',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),
        
        // Dropdown de generación
        DropdownButtonFormField<int>(
          value: _selectedGenerationId,
          decoration: const InputDecoration(
            labelText: 'Generación',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Por defecto'),
            ),
            ..._availableGenerations.map((gen) {
              // Formatear nombre de generación (ej: "generation-i" -> "Generación I")
              final genName = _formatGenerationName(gen.name);
              return DropdownMenuItem<int>(
                value: gen.id,
                child: Text(genName),
              );
            }),
          ],
          onChanged: _isLoadingGenerations ? null : (value) {
            _saveGeneration(value);
          },
        ),
        const SizedBox(height: 16),
        
        // Dropdown de versión (solo visible si hay generación seleccionada)
        if (_selectedGenerationId != null)
          DropdownButtonFormField<int>(
            value: _selectedVersionGroupId,
            decoration: const InputDecoration(
              labelText: 'Juego',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int>(
                value: null,
                child: Text('Ninguno'),
              ),
              ..._availableVersionGroups.map((vg) {
                // Formatear nombre de versión (ej: "red-blue" -> "Red/Blue")
                final vgName = _formatVersionGroupName(vg.name);
                return DropdownMenuItem<int>(
                  value: vg.id,
                  child: Text(vgName),
                );
              }),
            ],
            onChanged: _isLoadingVersionGroups ? null : (value) {
              _saveVersionGroup(value);
            },
          ),
      ],
    );
  }
  
  String _formatGenerationName(String name) {
    // "generation-i" -> "Generación I"
    final parts = name.split('-');
    if (parts.length >= 2 && parts[0] == 'generation') {
      final roman = parts[1].toUpperCase();
      final romanMap = {
        'I': 'I',
        'II': 'II',
        'III': 'III',
        'IV': 'IV',
        'V': 'V',
        'VI': 'VI',
        'VII': 'VII',
        'VIII': 'VIII',
        'IX': 'IX',
      };
      return 'Generación ${romanMap[roman] ?? roman}';
    }
    return name;
  }
  
  String _formatVersionGroupName(String name) {
    // "red-blue" -> "Red / Blue"
    return name
        .split('-')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' / ');
  }
  
  Widget _buildDataControlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Control de Datos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        // Botón para forzar recarga de base de datos
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isResettingDatabase ? null : _forceResetDatabase,
            icon: _isResettingDatabase
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_isResettingDatabase
                ? 'Recargando...'
                : 'Recargar base de datos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Esto borrará todos los datos y cerrará la aplicación. '
          'Al reiniciar, se cargarán los datos desde los archivos CSV.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}



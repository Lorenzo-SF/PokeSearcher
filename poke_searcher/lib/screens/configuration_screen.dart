import 'dart:async';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/language_dao.dart';
import '../database/daos/region_dao.dart';
import '../services/download/download_service.dart';
import '../services/download/download_manager.dart';

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
  List<Region> _regions = [];
  bool _isLoadingLanguages = true;
  bool _isDownloadingEssential = false;
  final Map<int, bool> _isDownloadingRegion = {};

  @override
  void initState() {
    super.initState();
    _selectedTheme = widget.appConfig.theme;
    _selectedLanguage = widget.appConfig.language;
    _loadLanguages();
    _loadRegions();
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

  Future<void> _loadRegions() async {
    try {
      final regionDao = RegionDao(widget.database);
      final regions = await regionDao.getAllRegions();
      setState(() {
        _regions = regions;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar regiones: $e'),
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

  Future<void> _forceDownloadEssential() async {
    if (_isDownloadingEssential) return;

    setState(() => _isDownloadingEssential = true);

    try {
      final downloadService = DownloadService(database: widget.database);

      // Marcar como no completada para forzar descarga
      await widget.appConfig.setInitialDownloadCompleted(false);

      // Mostrar diálogo de progreso
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          onProgress: (progress) {
            // El diálogo se actualiza automáticamente
          },
        ),
      );

      await downloadService.downloadEssentialData(
        onProgress: (progress) {
          // El diálogo se actualiza a través del DownloadManager
        },
      );

      await widget.appConfig.setInitialDownloadCompleted(true);

      if (mounted) {
        Navigator.of(context).pop(); // Cerrar diálogo
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Descarga esencial completada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Cerrar diálogo si está abierto
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingEssential = false);
      }
    }
  }

  Future<void> _forceDownloadRegion(int regionId, String regionName) async {
    if (_isDownloadingRegion[regionId] == true) return;

    setState(() => _isDownloadingRegion[regionId] = true);

    try {
      final downloadService = DownloadService(database: widget.database);

      // Mostrar diálogo de progreso
      if (!mounted) return;
      final controller = _DownloadProgressController();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadProgressDialog(
          onProgress: controller.updateProgress,
        ),
      );

      await downloadService.downloadRegionComplete(
        regionId: regionId,
        onProgress: (progress) {
          controller.updateProgress(progress);
        },
      );

      if (mounted) {
        Navigator.of(context).pop(); // Cerrar diálogo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Región $regionName descargada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Cerrar diálogo si está abierto
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar región: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingRegion[regionId] = false);
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
        
        // Botón para forzar descarga esencial
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isDownloadingEssential ? null : _forceDownloadEssential,
            icon: _isDownloadingEssential
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_isDownloadingEssential
                ? 'Descargando...'
                : 'Forzar descarga de datos esenciales'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Botones por región
        const Text(
          'Forzar descarga por región:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ..._regions.map((region) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloadingRegion[region.id] == true
                      ? null
                      : () => _forceDownloadRegion(region.id, region.name),
                  icon: _isDownloadingRegion[region.id] == true
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.map),
                  label: Text(
                    _isDownloadingRegion[region.id] == true
                        ? 'Descargando ${region.name}...'
                        : 'Forzar descarga: ${region.name}',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

/// Controlador para actualizar el progreso de descarga en el diálogo
class _DownloadProgressController {
  final _progressStream = StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressStream.stream;

  void updateProgress(DownloadProgress progress) {
    _progressStream.add(progress);
  }

  void dispose() {
    _progressStream.close();
  }
}

/// Diálogo de progreso de descarga
class _DownloadProgressDialog extends StatefulWidget {
  final Function(DownloadProgress)? onProgress;

  const _DownloadProgressDialog({this.onProgress});

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  DownloadProgress? _currentProgress;

  @override
  void initState() {
    super.initState();
    // El progreso se actualiza a través del callback onProgress
    if (widget.onProgress != null) {
      // Por ahora, el progreso se actualiza externamente
    }
  }

  void updateProgress(DownloadProgress progress) {
    if (mounted) {
      setState(() {
        _currentProgress = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Descargando...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentProgress != null) ...[
            Text(_currentProgress!.currentEntity),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _currentProgress!.total > 0
                  ? _currentProgress!.completed / _currentProgress!.total
                  : 0.0,
            ),
            const SizedBox(height: 8),
            Text(
              '${_currentProgress!.completed} / ${_currentProgress!.total}',
              style: const TextStyle(fontSize: 12),
            ),
          ] else
            const CircularProgressIndicator(),
        ],
      ),
    );
  }
}


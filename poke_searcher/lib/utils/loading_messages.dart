import 'dart:ui' as ui;

/// Utilidad para obtener mensajes de carga traducidos según el idioma
class LoadingMessages {
  /// Obtener el código de idioma del sistema o el proporcionado
  static String _getLanguageCode(String? configuredLanguage) {
    if (configuredLanguage != null && configuredLanguage.isNotEmpty) {
      return configuredLanguage;
    }
    
    // Usar idioma del sistema
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    return systemLocale.languageCode;
  }
  
  /// Obtener mensaje traducido según el idioma
  static String getMessage(String key, String? languageCode) {
    final lang = _getLanguageCode(languageCode);
    final messages = _getMessagesForLanguage(lang);
    return messages[key] ?? _getMessagesForLanguage('en')[key] ?? key;
  }
  
  /// Obtener mensajes para un idioma específico
  static Map<String, String> _getMessagesForLanguage(String langCode) {
    // Mapa de todos los mensajes por idioma
    final allMessages = {
      'es': {
        'preparing': 'Preparando carga de base de datos...',
        'loading_table': 'Cargando {table}...',
        'parsing': 'Procesando {table}...',
        'executing': 'Registrando {table}...',
        'table_completed': '{table} completado',
        'copying_media': 'Copiando archivos multimedia desde assets...',
        'copying_media_count': 'Copiando {total} archivos multimedia...',
        'copying_media_progress': 'Copiando multimedia: {copied}/{total}',
        'media_copied': 'Archivos multimedia copiados: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} fallos)',
        'completed': 'Base de datos cargada correctamente',
        'error': 'Error procesando backup: {error}',
        'error_loading_file': 'No se pudo cargar el archivo: {path}',
        'error_file_instructions': 'Asegúrate de que:\n1. El archivo existe en assets/database/\n2. El directorio está declarado en pubspec.yaml\n3. Has ejecutado "flutter pub get" y rebuild completo',
        'no_media_paths': 'No se encontraron rutas de multimedia en el SQL',
        'media_warning': 'Advertencia: no se pudieron copiar archivos multimedia',
        'media_error': 'Advertencia: error copiando archivos multimedia',
        'downloading_backup': 'Descargando backup...',
        'extracting_backup': 'Extrayendo backup...',
        'using_existing_data': 'Usando datos existentes...',
      },
      'en': {
        'preparing': 'Preparing database load...',
        'loading_table': 'Loading table: {table} ({current}/{total})',
        'parsing': 'Parsing {table}...',
        'executing': 'Executing {table} ({count} statements)...',
        'table_completed': '{table} completed ({count} statements)',
        'copying_media': 'Copying media files from assets...',
        'copying_media_count': 'Copying {total} media files...',
        'copying_media_progress': 'Copying media: {copied}/{total}',
        'media_copied': 'Media files copied: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} failures)',
        'completed': 'Database loaded successfully',
        'error': 'Error processing backup: {error}',
        'error_loading_file': 'Could not load file: {path}',
        'error_file_instructions': 'Make sure:\n1. File exists in assets/database/\n2. Directory is declared in pubspec.yaml\n3. You ran "flutter pub get" and full rebuild',
        'no_media_paths': 'No media paths found in SQL',
        'media_warning': 'Warning: could not copy media files',
        'media_error': 'Warning: error copying media files',
        'downloading_backup': 'Downloading backup...',
        'extracting_backup': 'Extracting backup...',
        'using_existing_data': 'Using existing data...',
      },
      'fr': {
        'preparing': 'Préparation du chargement de la base de données...',
        'loading_table': 'Chargement de la table: {table} ({current}/{total})',
        'parsing': 'Analyse de {table}...',
        'executing': 'Exécution de {table} ({count} instructions)...',
        'table_completed': '{table} terminé ({count} instructions)',
        'copying_media': 'Copie des fichiers multimédias depuis assets...',
        'copying_media_count': 'Copie de {total} fichiers multimédias...',
        'copying_media_progress': 'Copie des multimédias: {copied}/{total}',
        'media_copied': 'Fichiers multimédias copiés: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} échecs)',
        'completed': 'Base de données chargée avec succès',
        'error': 'Erreur lors du traitement de la sauvegarde: {error}',
        'error_loading_file': 'Impossible de charger le fichier: {path}',
        'error_file_instructions': 'Assurez-vous que:\n1. Le fichier existe dans assets/database/\n2. Le répertoire est déclaré dans pubspec.yaml\n3. Vous avez exécuté "flutter pub get" et une reconstruction complète',
        'no_media_paths': 'Aucun chemin multimédia trouvé dans le SQL',
        'media_warning': 'Avertissement: impossible de copier les fichiers multimédias',
        'media_error': 'Avertissement: erreur lors de la copie des fichiers multimédias',
      },
      'de': {
        'preparing': 'Vorbereitung des Datenbankladens...',
        'loading_table': 'Lade Tabelle: {table} ({current}/{total})',
        'parsing': 'Analysiere {table}...',
        'executing': 'Führe {table} aus ({count} Anweisungen)...',
        'table_completed': '{table} abgeschlossen ({count} Anweisungen)',
        'copying_media': 'Kopiere Mediendateien von assets...',
        'copying_media_count': 'Kopiere {total} Mediendateien...',
        'copying_media_progress': 'Kopiere Medien: {copied}/{total}',
        'media_copied': 'Mediendateien kopiert: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} Fehler)',
        'completed': 'Datenbank erfolgreich geladen',
        'error': 'Fehler beim Verarbeiten des Backups: {error}',
        'error_loading_file': 'Datei konnte nicht geladen werden: {path}',
        'error_file_instructions': 'Stellen Sie sicher:\n1. Die Datei existiert in assets/database/\n2. Das Verzeichnis ist in pubspec.yaml deklariert\n3. Sie haben "flutter pub get" und einen vollständigen Neubau ausgeführt',
        'no_media_paths': 'Keine Medienpfade im SQL gefunden',
        'media_warning': 'Warnung: Mediendateien konnten nicht kopiert werden',
        'media_error': 'Warnung: Fehler beim Kopieren von Mediendateien',
      },
      'it': {
        'preparing': 'Preparazione del caricamento del database...',
        'loading_table': 'Caricamento tabella: {table} ({current}/{total})',
        'parsing': 'Analisi di {table}...',
        'executing': 'Esecuzione di {table} ({count} istruzioni)...',
        'table_completed': '{table} completato ({count} istruzioni)',
        'copying_media': 'Copia file multimediali da assets...',
        'copying_media_count': 'Copia di {total} file multimediali...',
        'copying_media_progress': 'Copia multimediali: {copied}/{total}',
        'media_copied': 'File multimediali copiati: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} errori)',
        'completed': 'Database caricato con successo',
        'error': 'Errore durante l\'elaborazione del backup: {error}',
        'error_loading_file': 'Impossibile caricare il file: {path}',
        'error_file_instructions': 'Assicurati che:\n1. Il file esista in assets/database/\n2. La directory sia dichiarata in pubspec.yaml\n3. Hai eseguito "flutter pub get" e una ricostruzione completa',
        'no_media_paths': 'Nessun percorso multimediale trovato nel SQL',
        'media_warning': 'Avviso: impossibile copiare i file multimediali',
        'media_error': 'Avviso: errore durante la copia dei file multimediali',
      },
      'pt': {
        'preparing': 'Preparando carregamento do banco de dados...',
        'loading_table': 'Carregando tabela: {table} ({current}/{total})',
        'parsing': 'Analisando {table}...',
        'executing': 'Executando {table} ({count} instruções)...',
        'table_completed': '{table} concluído ({count} instruções)',
        'copying_media': 'Copiando arquivos de mídia de assets...',
        'copying_media_count': 'Copiando {total} arquivos de mídia...',
        'copying_media_progress': 'Copiando mídia: {copied}/{total}',
        'media_copied': 'Arquivos de mídia copiados: {copied}/{total}{failures}',
        'media_copied_failures': ' ({failures} falhas)',
        'completed': 'Banco de dados carregado com sucesso',
        'error': 'Erro ao processar backup: {error}',
        'error_loading_file': 'Não foi possível carregar o arquivo: {path}',
        'error_file_instructions': 'Certifique-se de que:\n1. O arquivo existe em assets/database/\n2. O diretório está declarado em pubspec.yaml\n3. Você executou "flutter pub get" e reconstrução completa',
        'no_media_paths': 'Nenhum caminho de mídia encontrado no SQL',
        'media_warning': 'Aviso: não foi possível copiar arquivos de mídia',
        'media_error': 'Aviso: erro ao copiar arquivos de mídia',
      },
    };
    
    // Retornar mensajes del idioma solicitado o inglés como fallback
    return allMessages[langCode] ?? allMessages['en']!;
  }
  
  /// Reemplazar placeholders en un mensaje
  static String _replacePlaceholders(String message, Map<String, String> params) {
    String result = message;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
  
  /// Obtener mensaje con parámetros
  static String getMessageWithParams(
    String key,
    String? languageCode,
    Map<String, String> params,
  ) {
    final message = getMessage(key, languageCode);
    return _replacePlaceholders(message, params);
  }
}


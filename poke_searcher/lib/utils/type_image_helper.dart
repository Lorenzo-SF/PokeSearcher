import 'dart:io';
import 'package:path/path.dart' as path;
import '../services/config/app_config.dart';
import '../database/app_database.dart';
import '../utils/media_path_helper.dart';

/// Helper para obtener la ruta de la imagen de un tipo según la configuración
/// 
/// Los archivos de tipos se guardan con nombres aplanados:
/// - Formato: media_type_{id}_{generation}_{version}_name_icon.{ext}
/// - Ejemplo: media_type_1_generation_iii_ruby_sapphire_name_icon.png
/// 
/// Los archivos se extraen del ZIP directamente en la raíz de poke_searcher_data
class TypeImageHelper {
  /// Obtener la ruta de la imagen de un tipo usando archivos aplanados
  /// 
  /// Busca archivos con formato: media_type_{id}_{generation}_{version}_name_icon.{ext}
  /// Los archivos están en la raíz de poke_searcher_data (aplanados)
  static Future<String?> getTypeImagePath({
    required int typeApiId,
    required String typeName,
    String? generationName,
    String? versionGroupName,
    AppDatabase? database,
  }) async {
    // Normalizar nombres: generation-i -> generation_i, red-blue -> red_blue
    String? genNameNormalized;
    String? vgNameNormalized;
    
    if (generationName != null) {
      genNameNormalized = generationName.replaceAll('-', '_');
    }
    if (versionGroupName != null) {
      vgNameNormalized = versionGroupName.replaceAll('-', '_');
    }
    
    final dataDir = await MediaPathHelper.getAppDataDirectory();
    
    // PRIORIDAD 1: Si tenemos generación y versión, buscar archivo específico
    if (genNameNormalized != null && vgNameNormalized != null) {
      for (final ext in ['png', 'svg']) {
        final flattenedName = 'media_type_${typeApiId}_${genNameNormalized}_${vgNameNormalized}_name_icon.$ext';
        final file = File(path.join(dataDir.path, flattenedName));
        if (await file.exists()) {
          // Retornar ruta relativa para que MediaPathHelper la procese correctamente
          return 'media/type/$typeApiId/$genNameNormalized/$vgNameNormalized/name_icon.$ext';
        }
      }
    }
    
    // PRIORIDAD 2: Si solo tenemos generación, buscar cualquier versión de esa generación
    if (genNameNormalized != null) {
      // Buscar archivos que coincidan con la generación (cualquier versión)
      try {
        await for (final entity in dataDir.list()) {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            // Formato: media_type_{id}_{generation}_{version}_name_icon.{ext}
            if (fileName.startsWith('media_type_${typeApiId}_${genNameNormalized}_') &&
                (fileName.endsWith('_name_icon.png') || fileName.endsWith('_name_icon.svg'))) {
              // Extraer versión del nombre
              final match = RegExp(r'media_type_\d+_([^_]+)_([^_]+)_name_icon\.(png|svg)').firstMatch(fileName);
              if (match != null) {
                final foundGen = match.group(1);
                final foundVg = match.group(2);
                if (foundGen == genNameNormalized) {
                  return 'media/type/$typeApiId/$foundGen/$foundVg/name_icon.${match.group(3)}';
                }
              }
            }
          }
        }
      } catch (e) {
        // Error buscando, continuar con fallback
      }
    }
    
    // PRIORIDAD 3: Buscar cualquier archivo del tipo (sin generación/versión específica)
    try {
      await for (final entity in dataDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          // Buscar cualquier archivo del tipo que tenga name_icon
          if (fileName.startsWith('media_type_${typeApiId}_') &&
              (fileName.endsWith('_name_icon.png') || fileName.endsWith('_name_icon.svg'))) {
            // Extraer generación y versión del nombre
            final match = RegExp(r'media_type_\d+_([^_]+)_([^_]+)_name_icon\.(png|svg)').firstMatch(fileName);
            if (match != null) {
              final foundGen = match.group(1);
              final foundVg = match.group(2);
              return 'media/type/$typeApiId/$foundGen/$foundVg/name_icon.${match.group(3)}';
            }
          }
        }
      }
    } catch (e) {
      // Error buscando, retornar null
    }
    
    // Fallback: retornar null (no se encontró archivo)
    return null;
  }
  
  /// Obtener la ruta de la imagen de un tipo usando la configuración de la app
  /// 
  /// Busca archivos aplanados en poke_searcher_data usando MediaPathHelper
  static Future<String?> getTypeImagePathFromConfig({
    required int typeApiId,
    required String typeName,
    required AppConfig appConfig,
    required AppDatabase database,
  }) async {
    final generationId = appConfig.typeImageGenerationId;
    final versionGroupId = appConfig.typeImageVersionGroupId;
    
    String? generationName;
    String? versionGroupName;
    
    // Obtener nombre de generación si está configurada
    if (generationId != null) {
      final generation = await database.generationDao.getGenerationById(generationId);
      if (generation != null) {
        generationName = generation.name;
      }
    }
    
    // Obtener nombre de version group si está configurado
    if (versionGroupId != null) {
      final versionGroup = await database.versionGroupDao.getVersionGroupById(versionGroupId);
      if (versionGroup != null) {
        versionGroupName = versionGroup.name;
      }
    }
    
    return await getTypeImagePath(
      typeApiId: typeApiId,
      typeName: typeName,
      generationName: generationName,
      versionGroupName: versionGroupName,
      database: database,
    );
  }
}


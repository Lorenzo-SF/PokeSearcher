import 'dart:io';
import 'package:path/path.dart' as path;
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../utils/media_path_helper.dart';

/// Helper para obtener la mejor imagen disponible de un pokemon.
/// 
/// Implementa una estrategia de priorización para seleccionar la mejor imagen
/// disponible según el formato y la calidad:
/// - Prioridad 1: SVG (vectorial, mejor calidad)
/// - Prioridad 2: PNG de mayor resolución (official-artwork)
/// - Prioridad 3: PNG de menor resolución (sprites)
/// 
/// Soporta tanto imágenes normales como shiny.
/// 
/// Si hay configuración de generación/juego, usa sprites.versions (front_transparent).
/// Si no hay configuración, usa la lógica por defecto (artwork_official).
class PokemonImageHelper {
  /// Obtener la mejor imagen disponible para un pokemon.
  /// 
  /// [pokemon] - Datos del pokemon que contiene las rutas de las imágenes
  /// [appConfig] - Configuración de la app (para verificar generación/juego)
  /// [database] - Base de datos (para obtener nombres de generación/juego)
  /// [preferShiny] - Si es true, prioriza imágenes shiny sobre normales
  /// [imageType] - Tipo de imagen: 'front_transparent', 'front_shiny_transparent', 'front_gray', o null para automático
  /// 
  /// Retorna la ruta de la mejor imagen disponible, o null si no hay ninguna.
  /// 
  /// Estrategia:
  /// - Si hay generación/juego configurado: usar sprites.versions (front_transparent)
  /// - Si no hay configuración: usar lógica por defecto (artwork_official)
  static Future<String?> getBestImagePath(
    PokemonData? pokemon, {
    AppConfig? appConfig,
    AppDatabase? database,
    bool preferShiny = false,
    String? imageType,
  }) async {
    if (pokemon == null) {
      return null;
    }
    
    // Si hay configuración de generación/juego, usar sprites.versions
    if (appConfig != null && database != null) {
      final generationId = appConfig.typeImageGenerationId;
      final versionGroupId = appConfig.typeImageVersionGroupId;
      
      if (generationId != null && versionGroupId != null) {
        // Obtener nombres de generación y versión
        final generation = await database.generationDao.getGenerationById(generationId);
        final versionGroup = await database.versionGroupDao.getVersionGroupById(versionGroupId);
        
        if (generation != null && versionGroup != null) {
          // Construir nombre de archivo según tipo de imagen
          String fileName;
          if (imageType != null) {
            fileName = imageType;
          } else if (preferShiny) {
            fileName = 'front_shiny_transparent';
          } else {
            fileName = 'front_transparent';
          }
          
          // Normalizar nombres: generation-i -> generation_i, red-blue -> red_blue
          final genName = generation.name.replaceAll('-', '_');
          final vgName = versionGroup.name.replaceAll('-', '_');
          
          // El formato aplanado es: media_pokemon_{id}_{generation}_{version}_{filename}.{ext}
          // Los archivos se extraen del ZIP directamente en la raíz de poke_searcher_data
          final dataDir = await MediaPathHelper.getAppDataDirectory();
          
          // PRIORIDAD 1: Buscar directamente en la raíz de poke_searcher_data
          // (los archivos se extraen aquí desde el ZIP)
          for (final ext in ['png', 'svg']) {
            final flattenedName = 'media_pokemon_${pokemon.apiId}_${genName}_${vgName}_$fileName.$ext';
            final file = File(path.join(dataDir.path, flattenedName));
            if (await file.exists()) {
              // Retornar ruta relativa para que MediaPathHelper la procese correctamente
              return 'media/pokemon/${pokemon.apiId}/$genName/$vgName/$fileName.$ext';
            }
          }
          
          // PRIORIDAD 2: Buscar en media/pokemon (por si los archivos están organizados en subdirectorios)
          final mediaDir = Directory(path.join(dataDir.path, 'media', 'pokemon'));
          if (await mediaDir.exists()) {
            for (final ext in ['png', 'svg']) {
              final flattenedName = 'media_pokemon_${pokemon.apiId}_${genName}_${vgName}_$fileName.$ext';
              final file = File(path.join(mediaDir.path, flattenedName));
              if (await file.exists()) {
                // Retornar ruta relativa para que MediaPathHelper la procese correctamente
                return 'media/pokemon/${pokemon.apiId}/$genName/$vgName/$fileName.$ext';
              }
            }
          }
        }
      }
    }
    
    // LÓGICA POR DEFECTO (sin generación/juego configurado)
    // Si se prefiere shiny, buscar shiny primero
    if (preferShiny) {
      // Buscar SVG shiny (poco probable que exista)
      if (pokemon.artworkOfficialShinyPath != null && 
          pokemon.artworkOfficialShinyPath!.isNotEmpty &&
          pokemon.artworkOfficialShinyPath!.toLowerCase().endsWith('.svg')) {
        return pokemon.artworkOfficialShinyPath;
      }
      
      // PNG shiny de official-artwork (mayor resolución)
      if (pokemon.artworkOfficialShinyPath != null && 
          pokemon.artworkOfficialShinyPath!.isNotEmpty &&
          pokemon.artworkOfficialShinyPath!.toLowerCase().endsWith('.png')) {
        return pokemon.artworkOfficialShinyPath;
      }
      
      // PNG shiny de home (fallback)
      if (pokemon.spriteFrontShinyPath != null && 
          pokemon.spriteFrontShinyPath!.isNotEmpty &&
          pokemon.spriteFrontShinyPath!.toLowerCase().endsWith('.png')) {
        return pokemon.spriteFrontShinyPath;
      }
    }
    
    // Prioridad 1: SVG normal desde dream-world (artworkOfficialPath si es SVG)
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.isNotEmpty &&
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.artworkOfficialPath;
    }
    
    // Prioridad 2: SVG desde spriteFrontDefaultPath
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.isNotEmpty &&
        pokemon.spriteFrontDefaultPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontDefaultPath;
    }
    
    // Prioridad 3: PNG de official-artwork (mayor resolución)
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.isNotEmpty &&
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.png')) {
      return pokemon.artworkOfficialPath;
    }
    
    // Prioridad 4: PNG de spriteFrontDefaultPath (fallback)
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.isNotEmpty) {
      return pokemon.spriteFrontDefaultPath;
    }
    
    // Si no hay nada, intentar shiny como último recurso
    if (pokemon.artworkOfficialShinyPath != null && 
        pokemon.artworkOfficialShinyPath!.isNotEmpty) {
      return pokemon.artworkOfficialShinyPath;
    }
    if (pokemon.spriteFrontShinyPath != null && 
        pokemon.spriteFrontShinyPath!.isNotEmpty) {
      return pokemon.spriteFrontShinyPath;
    }
    
    return null;
  }
  
  /// Verificar si un pokemon tiene imagen shiny disponible.
  /// 
  /// [pokemon] - Datos del pokemon a verificar
  /// 
  /// Retorna true si el pokemon tiene al menos una imagen shiny disponible
  /// (artworkOfficialShinyPath o spriteFrontShinyPath).
  static bool hasShinyImage(PokemonData? pokemon) {
    if (pokemon == null) return false;
    return (pokemon.artworkOfficialShinyPath != null && 
            pokemon.artworkOfficialShinyPath!.isNotEmpty) ||
           (pokemon.spriteFrontShinyPath != null && 
            pokemon.spriteFrontShinyPath!.isNotEmpty);
  }
}


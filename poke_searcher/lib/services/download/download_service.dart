import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../../database/daos/region_dao.dart';
import '../../database/daos/pokedex_dao.dart';
import '../../database/daos/pokemon_dao.dart';
import 'api_client.dart';
import 'download_manager.dart';
import 'download_phases.dart';
import '../../models/mappers/language_mapper.dart';
import '../../models/mappers/region_mapper.dart';
import '../../models/mappers/type_mapper.dart';
import '../../utils/color_generator.dart';

/// Servicio principal de descarga de datos
class DownloadService {
  final AppDatabase database;
  final ApiClient apiClient;
  final DownloadManager downloadManager;
  
  DownloadService({
    required this.database,
    ApiClient? apiClient,
    DownloadManager? downloadManager,
  }) : apiClient = apiClient ?? ApiClient(),
       downloadManager = downloadManager ?? DownloadManager(
         database: database,
         onProgress: null,
       );
  
  /// Descargar fase esencial (Fase 0)
  /// Optimizado: primero descarga todos los JSON, luego inserta en batch
  Future<void> downloadEssentialData({
    ProgressCallback? onProgress,
  }) async {
    final phase = DownloadPhase.essential;
    final phaseInfo = PhaseInfo.getInfo(phase);
    
    int totalItems = 0;
    int totalSizeBytes = 0;
    
    // FASE 1: Calcular total y descargar todos los JSON en memoria
    onProgress?.call(DownloadProgress(
      phase: phase,
      currentEntity: 'Preparando descarga...',
      completed: 0,
      total: 0,
      totalSizeBytes: 0,
    ));
    
    // Estructura para almacenar todos los datos descargados
    final Map<String, List<Map<String, dynamic>>> downloadedData = {};
    
    // FASE 1.1: Calcular total de items primero
    final Map<String, int> entityTypeCounts = {};
    for (final entityType in phaseInfo.entityTypes) {
      try {
        final list = await apiClient.getResourceList(endpoint: entityType);
        final count = list['count'] as int;
        entityTypeCounts[entityType] = count;
        totalItems += count;
        totalSizeBytes += count * 2048;
      } catch (e) {
        print('Error al calcular total para $entityType: $e');
        entityTypeCounts[entityType] = 0;
      }
    }
    
    // FASE 1.2: Descargar todos los JSON en memoria
    int downloadedCount = 0;
    for (final entityType in phaseInfo.entityTypes) {
      try {
        final list = await apiClient.getResourceList(endpoint: entityType);
        final results = list['results'] as List;
        final count = results.length;
        
        // Descargar todos los JSON de este tipo
        final List<Map<String, dynamic>> entityData = [];
        for (final result in results) {
          final resource = result as Map<String, dynamic>;
          final url = resource['url'] as String;
          
          try {
            final data = await apiClient.getResourceByUrl(url);
            entityData.add(data);
            downloadedCount++;
            
            // Actualizar progreso de descarga
            onProgress?.call(DownloadProgress(
              phase: phase,
              currentEntity: 'Descargando $entityType... (${entityData.length}/$count)',
              completed: downloadedCount,
              total: totalItems,
              totalSizeBytes: totalSizeBytes,
            ));
            
            // Delay para evitar rate limiting
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (e) {
            print('Error al descargar $url: $e');
            // Continuar con el siguiente
          }
        }
        
        downloadedData[entityType] = entityData;
        
        // Delay entre tipos
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('Error al descargar tipo $entityType: $e');
        downloadedData[entityType] = []; // Lista vacía si falla
      }
    }
    
    // FASE 2: Insertar todos los datos descargados en batch
    int insertedCount = 0;
    for (final entityType in phaseInfo.entityTypes) {
      final entityDataList = downloadedData[entityType] ?? [];
      
      if (entityDataList.isEmpty) {
        // Marcar como completado aunque esté vacío
        await downloadManager.markDownloadCompleted(
          phase: phase,
          entityType: entityType,
        );
        continue;
      }
      
      // Insertar todos los datos de este tipo
      for (final data in entityDataList) {
        try {
          await _saveEntityData(entityType, data);
          insertedCount++;
          
          // Actualizar progreso de inserción (mostrar como parte del total)
          onProgress?.call(DownloadProgress(
            phase: phase,
            currentEntity: 'Guardando $entityType... ($insertedCount/$downloadedCount)',
            completed: downloadedCount + insertedCount,
            total: totalItems * 2, // Descarga (totalItems) + Inserción (totalItems)
            totalSizeBytes: totalSizeBytes,
          ));
        } catch (e) {
          print('Error al guardar datos de $entityType: $e');
        }
      }
      
      // Marcar como completado
      await downloadManager.markDownloadCompleted(
        phase: phase,
        entityType: entityType,
      );
    }
    
    // Notificar finalización
    onProgress?.call(DownloadProgress(
      phase: phase,
      currentEntity: 'Descarga completada',
      completed: totalItems * 2,
      total: totalItems * 2,
      totalSizeBytes: totalSizeBytes,
    ));
  }
  
  /// Descargar un tipo de entidad específico (SECUENCIAL - un recurso a la vez)
  Future<void> _downloadEntityType({
    required DownloadPhase phase,
    required String entityType,
    int progressOffset = 0, // Offset para acumular progreso total
    ProgressCallback? onProgress,
  }) async {
    // Verificar si ya fue descargado
    final isDownloaded = await downloadManager.isDownloaded(
      phase: phase,
      entityType: entityType,
    );
    
    if (isDownloaded) {
      return;
    }
    
    await downloadManager.markDownloadStarted(
      phase: phase,
      entityType: entityType,
    );
    
    try {
      // Obtener lista de recursos
      final list = await apiClient.getResourceList(endpoint: entityType);
      final results = list['results'] as List;
      final count = results.length;
      
      int completed = 0;
      
      // Descargar cada recurso SECUENCIALMENTE con delay entre peticiones
      for (final result in results) {
        final resource = result as Map<String, dynamic>;
        final url = resource['url'] as String;
        
        try {
          final data = await apiClient.getResourceByUrl(url);
          
          // Guardar en base de datos según el tipo
          await _saveEntityData(entityType, data);
          
          completed++;
          onProgress?.call(DownloadProgress(
            phase: phase,
            currentEntity: entityType,
            completed: completed,
            total: count,
            totalSizeBytes: null, // Se pasa desde el nivel superior
          ));
          
          // Delay adicional entre recursos para evitar rate limiting
          // Aumentado a 300ms para ser más conservador
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          // Si es "too many requests", esperar más tiempo y actualizar estado
          if (e.toString().contains('429') || 
              e.toString().contains('too many requests') ||
              e.toString().contains('Too many requests')) {
            // Actualizar estado para informar al usuario
            onProgress?.call(DownloadProgress(
              phase: phase,
              currentEntity: '$entityType (esperando por rate limit...)',
              completed: completed,
              total: count,
            ));
            
            // Esperar más tiempo antes de reintentar
            await Future.delayed(const Duration(seconds: 10));
            
            // Reintentar este recurso
            try {
              final data = await apiClient.getResourceByUrl(url);
              await _saveEntityData(entityType, data);
              completed++;
              onProgress?.call(DownloadProgress(
                phase: phase,
                currentEntity: entityType,
                completed: completed,
                total: count,
                totalSizeBytes: null, // Se pasa desde el nivel superior
              ));
            } catch (retryError) {
              print('Error al reintentar descargar $url: $retryError');
              // Si sigue fallando, saltar este recurso y continuar
            }
          } else {
            // Continuar con el siguiente aunque falle uno
            print('Error al descargar $url: $e');
          }
        }
      }
      
      await downloadManager.markDownloadCompleted(
        phase: phase,
        entityType: entityType,
      );
    } catch (e) {
      await downloadManager.markDownloadError(
        phase: phase,
        entityType: entityType,
        error: e.toString(),
      );
      rethrow;
    }
  }
  
  /// Guardar datos de entidad en base de datos
  Future<void> _saveEntityData(String entityType, Map<String, dynamic> data) async {
    switch (entityType) {
      case 'language':
        await _saveLanguage(data);
        break;
      case 'region':
        await _saveRegion(data);
        break;
      case 'type':
        await _saveType(data);
        break;
      // Agregar más casos según se necesiten
      default:
        // Por ahora, solo guardamos los tipos implementados
        break;
    }
  }
  
  /// Guardar idioma
  Future<void> _saveLanguage(Map<String, dynamic> data) async {
    final companion = LanguageMapper.fromApiJson(data);
    await database.into(database.languages).insert(
      companion,
      mode: InsertMode.replace,
    );
  }
  
  /// Guardar región
  Future<void> _saveRegion(Map<String, dynamic> data) async {
    final companion = RegionMapper.fromApiJson(data);
    final regionId = await database.into(database.regions).insert(
      companion,
      mode: InsertMode.replace,
    );
    
    // Guardar nombres localizados
    // TODO: Implementar guardado de nombres localizados cuando se resuelva languageId
    // final localizedNames = RegionMapper.extractLocalizedNames(data, regionId);
  }
  
  /// Guardar tipo
  Future<void> _saveType(Map<String, dynamic> data) async {
    final companion = TypeMapper.fromApiJson(data);
    final typeId = await database.into(database.types).insert(
      companion,
      mode: InsertMode.replace,
    );
    
    // Guardar relaciones de daño
    final damageRelations = TypeMapper.extractDamageRelations(data, typeId);
    if (damageRelations.isNotEmpty) {
      for (final relation in damageRelations) {
        await database.into(database.typeDamageRelations).insert(
          relation,
          mode: InsertMode.replace,
        );
      }
    }
  }
  
  /// Verificar si una región está completamente descargada
  /// Retorna true si la región tiene todas sus pokedex descargadas
  /// y todas las pokedex tienen todos sus pokemon-species y pokemon descargados
  Future<bool> isRegionFullyDownloaded(int regionId) async {
    try {
      final incompletePokedexes = await getIncompletePokedexes(regionId);
      final isComplete = incompletePokedexes.isEmpty;
      print('isRegionFullyDownloaded($regionId): ${isComplete ? "COMPLETA" : "INCOMPLETA"} (${incompletePokedexes.length} pokedexes incompletas)');
      return isComplete;
    } catch (e) {
      print('Error al verificar región completa: $e');
      return false;
    }
  }
  
  /// Obtener lista de pokedexes incompletas de una región
  /// Retorna lista de URLs de pokedexes que faltan o están incompletas
  /// Una pokedex está incompleta si:
  /// - No existe en la DB
  /// - No tiene entradas
  /// - Alguna entrada no tiene su pokemon-species descargado
  /// - Alguna entrada no tiene al menos un pokemon descargado
  Future<List<String>> getIncompletePokedexes(int regionId) async {
    try {
      final regionDao = RegionDao(database);
      final pokedexDao = PokedexDao(database);
      final pokemonDao = PokemonDao(database);
      
      // Obtener la región
      final region = await regionDao.getRegionById(regionId);
      if (region == null) {
        return [];
      }
      
      // Obtener todas las pokedex de la región desde la API usando apiId
      final regionData = await apiClient.getResourceByUrl(
        '${ApiClient.baseUrl}/region/${region.apiId}',
      );
      final pokedexes = regionData['pokedexes'] as List?;
      
      if (pokedexes == null || pokedexes.isEmpty) {
        return []; // Región sin pokedex, todas están "completas"
      }
      
      final List<String> incompleteUrls = [];
      
      // Verificar que todas las pokedex estén descargadas completamente
      for (final pokedexRef in pokedexes) {
        final pokedexUrl = pokedexRef['url'] as String;
        final pokedexApiId = _extractApiIdFromUrl(pokedexUrl);
        
        // Verificar si la pokedex existe en la DB
        final pokedex = await pokedexDao.getPokedexByApiId(pokedexApiId);
        if (pokedex == null) {
          incompleteUrls.add(pokedexUrl); // Falta esta pokedex
          continue;
        }
        
        // Verificar que la pokedex tenga entradas
        final entries = await pokedexDao.getPokedexEntries(pokedex.id);
        if (entries.isEmpty) {
          incompleteUrls.add(pokedexUrl); // La pokedex no tiene entradas
          continue;
        }
        
        // Verificar que cada entrada tenga su pokemon-species y al menos un pokemon
        // Verificación simplificada: solo comprobar que existan
        for (final entry in entries) {
          // Verificar que existe el pokemon-species
          final species = await (database.select(database.pokemonSpecies)
            ..where((t) => t.id.equals(entry.pokemonSpeciesId)))
            .getSingleOrNull();
          
          if (species == null) {
            incompleteUrls.add(pokedexUrl);
            break; // Esta pokedex está incompleta
          }
          
          // Verificar que existe al menos un pokemon de esta especie
          final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
          if (pokemons.isEmpty) {
            incompleteUrls.add(pokedexUrl);
            break; // Esta pokedex está incompleta
          }
        }
      }
      
      return incompleteUrls;
    } catch (e) {
      print('Error al obtener pokedexes incompletas: $e');
      return [];
    }
  }
  
  /// Convertir valor dinámico a int? de forma segura
  int? _safeIntFromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        return null;
      }
    }
    if (value is bool) {
      // Si es bool, convertir a int (true = 1, false = 0)
      return value ? 1 : 0;
    }
    return null;
  }
  
  /// Extraer ID de API desde una URL
  int _extractApiIdFromUrl(String url) {
    if (url.isEmpty) {
      throw FormatException('URL vacía');
    }
    
    // Limpiar la URL (eliminar espacios, saltos de línea, etc.)
    final cleanUrl = url.trim();
    
    // Dividir por '/'
    final parts = cleanUrl.split('/');
    
    // Buscar el último segmento que sea un número
    for (int i = parts.length - 1; i >= 0; i--) {
      final segment = parts[i].trim();
      if (segment.isEmpty) continue;
      
      // Intentar parsear como int
      try {
        // Eliminar cualquier query string o fragmento
        final cleanSegment = segment.split('?').first.split('#').first;
        return int.parse(cleanSegment);
      } catch (e) {
        // Si no es un número, continuar con el siguiente segmento
        continue;
      }
    }
    
    throw FormatException('No se pudo extraer ID de la URL: $url');
  }
  
  /// Descargar solo las pokedexes incompletas de una región
  /// Si una pokedex está incompleta, se elimina y se descarga de nuevo
  Future<void> downloadIncompletePokedexes({
    required int regionId,
    ProgressCallback? onProgress,
  }) async {
    try {
      final regionDao = RegionDao(database);
      final pokedexDao = PokedexDao(database);
      
      // Obtener la región
      final region = await regionDao.getRegionById(regionId);
      if (region == null) {
        throw Exception('Región no encontrada');
      }
      
      // Obtener pokedexes incompletas
      final incompleteUrls = await getIncompletePokedexes(regionId);
      
      if (incompleteUrls.isEmpty) {
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Todas las pokedexes están completas',
          completed: 1,
          total: 1,
        ));
        return;
      }
      
      // Obtener datos de la región desde la API para obtener nombres
      final regionData = await apiClient.getResourceByUrl(
        '${ApiClient.baseUrl}/region/${region.apiId}',
      );
      final allPokedexes = regionData['pokedexes'] as List?;
      
      // Crear mapa de URLs a nombres
      final Map<String, String> urlToName = {};
      if (allPokedexes != null) {
        for (final pokedexRef in allPokedexes) {
          final url = pokedexRef['url'] as String;
          final name = pokedexRef['name'] as String? ?? 'Pokedex';
          urlToName[url] = name;
        }
      }
      
      // Calcular total de items a descargar
      int totalItems = 0;
      final List<Map<String, dynamic>> pokedexInfoList = [];
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Calculando total de datos a descargar...',
        completed: 0,
        total: 0,
      ));
      
      // Pre-calcular totales solo para pokedexes incompletas
      for (final pokedexUrl in incompleteUrls) {
        try {
          // Si la pokedex existe pero está incompleta, eliminarla primero
          final pokedexApiId = _extractApiIdFromUrl(pokedexUrl);
          final existingPokedex = await pokedexDao.getPokedexByApiId(pokedexApiId);
          if (existingPokedex != null) {
            // Eliminar entradas y la pokedex
            await (database.delete(database.pokedexEntries)
              ..where((t) => t.pokedexId.equals(existingPokedex.id)))
              .go();
            await (database.delete(database.pokedex)
              ..where((t) => t.id.equals(existingPokedex.id)))
              .go();
          }
          
          final pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
          final pokemonEntries = pokedexData['pokemon_entries'] as List?;
          final entryCount = pokemonEntries?.length ?? 0;
          
          pokedexInfoList.add({
            'url': pokedexUrl,
            'name': urlToName[pokedexUrl] ?? pokedexData['name'] as String? ?? 'Pokedex',
            'entryCount': entryCount,
          });
          
          totalItems += 1 + entryCount; // 1 pokedex + N pokemon-species
        } catch (e) {
          print('Error al pre-calcular pokedex: $e');
        }
      }
      
      int totalPokedex = pokedexInfoList.length;
      int completedItems = 0;
      int itemsBeforeCurrentPokedex = 0; // Items completados antes del pokedex actual
      
      // Descargar cada pokedex y todo lo que cuelga de ella
      for (int pokedexIndex = 0; pokedexIndex < pokedexInfoList.length; pokedexIndex++) {
        final pokedexInfo = pokedexInfoList[pokedexIndex];
        final pokedexUrl = pokedexInfo['url'] as String;
        final pokedexName = pokedexInfo['name'] as String;
        final entryCount = pokedexInfo['entryCount'] as int;
        
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Descargando pokedex "${pokedexName}" (${pokedexIndex + 1}/$totalPokedex)',
          completed: itemsBeforeCurrentPokedex,
          total: totalItems,
        ));
        
        // Incrementar por la pokedex misma
        completedItems = itemsBeforeCurrentPokedex + 1;
        
        // Descargar pokedex completa con callback de progreso detallado
        await _downloadPokedexComplete(
          pokedexUrl,
          onProgress: (speciesIndex, totalSpecies) {
            // Calcular items completados: items anteriores + pokedex (1) + especies descargadas
            completedItems = itemsBeforeCurrentPokedex + 1 + (speciesIndex + 1);
            onProgress?.call(DownloadProgress(
              phase: DownloadPhase.regionData,
              currentEntity: 'Descargando pokedex "${pokedexName}": Pokémon ${speciesIndex + 1}/$totalSpecies',
              completed: completedItems,
              total: totalItems,
            ));
          },
        );
        
        // Actualizar items completados antes del siguiente pokedex
        itemsBeforeCurrentPokedex += 1 + entryCount; // Pokedex + todas sus especies
        completedItems = itemsBeforeCurrentPokedex;
        
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Pokedexes incompletas descargadas',
        completed: totalItems,
        total: totalItems,
      ));
    } catch (e) {
      print('Error al descargar pokedexes incompletas: $e');
      rethrow;
    }
  }
  
  /// Descargar toda una región en transacción
  /// Si la región está a medias, se elimina todo y se descarga de nuevo
  /// (Método original mantenido por compatibilidad)
  Future<void> downloadRegionComplete({
    required int regionId,
    ProgressCallback? onProgress,
  }) async {
    try {
      final regionDao = RegionDao(database);
      
      // Obtener la región
      final region = await regionDao.getRegionById(regionId);
      if (region == null) {
        throw Exception('Región no encontrada');
      }
      
      // Verificar si está completa
      final isComplete = await isRegionFullyDownloaded(regionId);
      if (isComplete) {
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Región ya está completa',
          completed: 1,
          total: 1,
        ));
        return;
      }
      
      // Si está a medias, eliminar todos los datos de la región (en transacción)
      await database.transaction(() async {
        await _deleteRegionData(regionId);
      });
      
      // Obtener datos de la región desde la API usando apiId
      final regionData = await apiClient.getResourceByUrl(
        '${ApiClient.baseUrl}/region/${region.apiId}',
      );
      
      final pokedexes = regionData['pokedexes'] as List?;
      if (pokedexes == null || pokedexes.isEmpty) {
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Región sin pokedex',
          completed: 1,
          total: 1,
        ));
        return; // Región sin pokedex
      }
      
      // Calcular total de items a descargar (pokedex + pokemon-species + pokemon)
      int totalItems = 0;
      final List<Map<String, dynamic>> pokedexInfoList = [];
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Calculando total de datos a descargar...',
        completed: 0,
        total: 0,
      ));
      
      // Pre-calcular totales
      for (final pokedexRef in pokedexes) {
        final pokedexUrl = pokedexRef['url'] as String;
        try {
          final pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
          final pokemonEntries = pokedexData['pokemon_entries'] as List?;
          final entryCount = pokemonEntries?.length ?? 0;
          
          pokedexInfoList.add({
            'url': pokedexUrl,
            'name': pokedexData['name'] as String? ?? 'Pokedex',
            'entryCount': entryCount,
          });
          
          totalItems += 1 + entryCount; // 1 pokedex + N pokemon-species
        } catch (e) {
          print('Error al pre-calcular pokedex: $e');
        }
      }
      
      int totalPokedex = pokedexInfoList.length;
      int completedItems = 0;
      int itemsBeforeCurrentPokedex = 0; // Items completados antes del pokedex actual
      
      // Descargar cada pokedex y todo lo que cuelga de ella
      for (int pokedexIndex = 0; pokedexIndex < pokedexInfoList.length; pokedexIndex++) {
        final pokedexInfo = pokedexInfoList[pokedexIndex];
        final pokedexUrl = pokedexInfo['url'] as String;
        final pokedexName = pokedexInfo['name'] as String;
        final entryCount = pokedexInfo['entryCount'] as int;
        
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Descargando pokedex "${pokedexName}" (${pokedexIndex + 1}/$totalPokedex)',
          completed: itemsBeforeCurrentPokedex,
          total: totalItems,
        ));
        
        // Incrementar por la pokedex misma
        completedItems = itemsBeforeCurrentPokedex + 1;
        
        // Descargar pokedex completa con callback de progreso detallado
        await _downloadPokedexComplete(
          pokedexUrl,
          onProgress: (speciesIndex, totalSpecies) {
            // Calcular items completados: items anteriores + pokedex (1) + especies descargadas
            completedItems = itemsBeforeCurrentPokedex + 1 + (speciesIndex + 1);
            onProgress?.call(DownloadProgress(
              phase: DownloadPhase.regionData,
              currentEntity: 'Descargando pokedex "${pokedexName}": Pokémon ${speciesIndex + 1}/$totalSpecies',
              completed: completedItems,
              total: totalItems,
            ));
          },
        );
        
        // Actualizar items completados antes del siguiente pokedex
        itemsBeforeCurrentPokedex += 1 + entryCount; // Pokedex + todas sus especies
        completedItems = itemsBeforeCurrentPokedex;
        
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Región descargada completamente',
        completed: totalItems,
        total: totalItems,
      ));
    } catch (e) {
      print('Error al descargar región completa: $e');
      rethrow;
    }
  }
  
  /// Eliminar todos los datos de una región (para re-descargar)
  Future<void> _deleteRegionData(int regionId) async {
    final pokedexDao = PokedexDao(database);
    
    // Obtener todas las pokedex de la región
    final pokedexes = await pokedexDao.getPokedexByRegion(regionId);
    
    for (final pokedex in pokedexes) {
      // Eliminar entradas de pokedex
      await (database.delete(database.pokedexEntries)
        ..where((t) => t.pokedexId.equals(pokedex.id)))
        .go();
      
      // Eliminar la pokedex
      await (database.delete(database.pokedex)
        ..where((t) => t.id.equals(pokedex.id)))
        .go();
    }
  }
  
  /// Descargar una pokedex completa y todo lo que cuelga de ella
  Future<void> _downloadPokedexComplete(
    String pokedexUrl, {
    void Function(int speciesIndex, int totalSpecies)? onProgress,
  }) async {
    // Descargar datos de la pokedex desde la API
    final pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
    
    // Guardar pokedex y todo lo que cuelga en una transacción
    await database.transaction(() async {
      // Guardar pokedex
      await _savePokedex(pokedexData);
    });
    
    // Obtener entradas de pokemon
    final pokemonEntries = pokedexData['pokemon_entries'] as List?;
    if (pokemonEntries == null || pokemonEntries.isEmpty) {
      return;
    }
    
    final totalSpecies = pokemonEntries.length;
    
    // Descargar cada pokemon-species y sus datos (fuera de transacción para llamadas API)
    for (int speciesIndex = 0; speciesIndex < pokemonEntries.length; speciesIndex++) {
      final entry = pokemonEntries[speciesIndex];
      final pokemonSpecies = entry['pokemon_species'] as Map<String, dynamic>?;
      if (pokemonSpecies == null) continue;
      
      final speciesUrl = pokemonSpecies['url'] as String;
      
      // Notificar progreso
      onProgress?.call(speciesIndex, totalSpecies);
      
      // Descargar pokemon-species (esto también usa transacciones internamente)
      await _downloadPokemonSpeciesComplete(speciesUrl);
      
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
  
  /// Guardar pokedex
  Future<void> _savePokedex(Map<String, dynamic> data) async {
    // TODO: Implementar mapper para pokedex
    // Por ahora, guardar datos básicos
    final apiId = data['id'] as int;
    final name = data['name'] as String;
    final isMainSeries = data['is_main_series'] as bool? ?? false;
    
    // Obtener regionId desde la URL de region
    int? regionId;
    final regionUrl = data['region']?['url'] as String?;
    if (regionUrl != null && regionUrl.isNotEmpty) {
      try {
        final regionApiId = _extractApiIdFromUrl(regionUrl);
        final regionDao = RegionDao(database);
        final region = await regionDao.getRegionByApiId(regionApiId);
        regionId = region?.id;
      } catch (e) {
        print('Error al extraer regionId de URL $regionUrl: $e');
        // Continuar sin regionId
      }
    }
    
    // Generar color único para esta pokedex
    String? color;
    if (regionId != null) {
      // Contar cuántas pokedexes hay en esta región para asignar índice único
      final pokedexDao = PokedexDao(database);
      final existingPokedexes = await pokedexDao.getPokedexByRegion(regionId);
      // El índice será el número de pokedexes existentes (antes de añadir esta)
      final colorIndex = existingPokedexes.length;
      color = ColorGenerator.generatePastelColor(colorIndex);
    } else {
      // Si no hay región, usar el apiId como índice
      color = ColorGenerator.generatePastelColor(apiId);
    }
    
    // Guardar pokedex
    final companion = PokedexCompanion(
      apiId: Value(apiId),
      name: Value(name),
      isMainSeries: Value(isMainSeries),
      regionId: Value(regionId),
      color: Value(color),
      descriptionsJson: Value(_jsonEncode(data['descriptions'])),
      pokemonEntriesJson: Value(_jsonEncode(data['pokemon_entries'])),
    );
    
    await database.into(database.pokedex).insert(
      companion,
      mode: InsertMode.replace,
    );
    
    // Guardar entradas de pokedex
    final pokemonEntries = data['pokemon_entries'] as List?;
    if (pokemonEntries != null) {
      final pokedex = await (database.select(database.pokedex)
        ..where((t) => t.apiId.equals(apiId)))
        .getSingle();
      
      for (final entry in pokemonEntries) {
        final entryNumber = _safeIntFromDynamic(entry['entry_number']);
        if (entryNumber == null) {
          print('Advertencia: entrada sin entry_number válido, saltando...');
          continue;
        }
        
        final pokemonSpecies = entry['pokemon_species'] as Map<String, dynamic>?;
        if (pokemonSpecies == null) {
          print('Advertencia: entrada sin pokemon_species, saltando...');
          continue;
        }
        
        final speciesUrl = pokemonSpecies['url'] as String?;
        if (speciesUrl == null || speciesUrl.isEmpty) {
          print('Advertencia: pokemon_species sin URL, saltando...');
          continue;
        }
        
        int speciesApiId;
        try {
          speciesApiId = _extractApiIdFromUrl(speciesUrl);
        } catch (e) {
          print('Error al extraer ID de URL $speciesUrl: $e');
          continue; // Saltar esta entrada y continuar con la siguiente
        }
        
        // Obtener o crear pokemon species
        final species = await (database.select(database.pokemonSpecies)
          ..where((t) => t.apiId.equals(speciesApiId)))
          .getSingleOrNull();
        
        if (species != null) {
          final entryCompanion = PokedexEntriesCompanion(
            pokedexId: Value(pokedex.id),
            pokemonSpeciesId: Value(species.id),
            entryNumber: Value(entryNumber),
          );
          
          await database.into(database.pokedexEntries).insert(
            entryCompanion,
            mode: InsertMode.replace,
          );
        }
      }
    }
  }
  
  /// Descargar pokemon-species completo y todo lo que cuelga
  Future<void> _downloadPokemonSpeciesComplete(String speciesUrl) async {
    // Descargar datos desde la API
    final speciesData = await apiClient.getResourceByUrl(speciesUrl);
    
    // Guardar pokemon-species en transacción
    await database.transaction(() async {
      await _savePokemonSpecies(speciesData);
    });
    
    // Descargar evolution chain si existe
    final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
    if (evolutionChainUrl != null) {
      await _downloadEvolutionChain(evolutionChainUrl);
    }
    
    // Descargar todas las variedades (pokemon)
    final varieties = speciesData['varieties'] as List?;
    if (varieties != null) {
      for (final variety in varieties) {
        final pokemon = variety['pokemon'] as Map<String, dynamic>?;
        if (pokemon == null) continue;
        
        final pokemonUrl = pokemon['url'] as String;
        await _downloadPokemonComplete(pokemonUrl);
        
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }
  
  /// Guardar pokemon-species
  Future<void> _savePokemonSpecies(Map<String, dynamic> data) async {
    // TODO: Implementar mapper completo para pokemon-species
    // Por ahora, guardar datos básicos
    final apiId = data['id'] as int;
    final name = data['name'] as String;
    
    final companion = PokemonSpeciesCompanion(
      apiId: Value(apiId),
      name: Value(name),
      order: Value(_safeIntFromDynamic(data['order'])),
      genderRate: Value(_safeIntFromDynamic(data['gender_rate'])),
      captureRate: Value(_safeIntFromDynamic(data['capture_rate'])),
      baseHappiness: Value(_safeIntFromDynamic(data['base_happiness'])),
      isBaby: Value(data['is_baby'] as bool? ?? false),
      isLegendary: Value(data['is_legendary'] as bool? ?? false),
      isMythical: Value(data['is_mythical'] as bool? ?? false),
      hatchCounter: Value(_safeIntFromDynamic(data['hatch_counter'])),
      hasGenderDifferences: Value(data['has_gender_differences'] as bool? ?? false),
      formsSwitchable: Value(_safeIntFromDynamic(data['forms_switchable'])),
      eggGroupsJson: Value(_jsonEncode(data['egg_groups'])),
      flavorTextEntriesJson: Value(_jsonEncode(data['flavor_text_entries'])),
      formDescriptionsJson: Value(_jsonEncode(data['form_descriptions'])),
      varietiesJson: Value(_jsonEncode(data['varieties'])),
    );
    
    await database.into(database.pokemonSpecies).insert(
      companion,
      mode: InsertMode.replace,
    );
  }
  
  /// Descargar evolution chain
  Future<void> _downloadEvolutionChain(String chainUrl) async {
    // Descargar datos desde la API
    final chainData = await apiClient.getResourceByUrl(chainUrl);
    
    // Guardar en transacción
    await database.transaction(() async {
      final apiId = chainData['id'] as int;
      
      final companion = EvolutionChainsCompanion(
        apiId: Value(apiId),
        chainJson: Value(_jsonEncode(chainData['chain'])),
      );
      
      await database.into(database.evolutionChains).insert(
        companion,
        mode: InsertMode.replace,
      );
    });
  }
  
  /// Descargar pokemon completo con multimedia
  Future<void> _downloadPokemonComplete(String pokemonUrl) async {
    // Descargar datos desde la API
    final pokemonData = await apiClient.getResourceByUrl(pokemonUrl);
    
    // Guardar pokemon con URLs de multimedia en transacción
    await database.transaction(() async {
      await _savePokemonWithMedia(pokemonData);
    });
    
    // Descargar multimedia (sprites, cries, artwork) - esto actualiza la DB después
    await _downloadPokemonMedia(pokemonData);
  }
  
  /// Guardar pokemon con URLs de multimedia
  Future<void> _savePokemonWithMedia(Map<String, dynamic> data) async {
    final apiId = data['id'] as int;
    final name = data['name'] as String;
    
    // Obtener speciesId
    final species = data['species'] as Map<String, dynamic>?;
    int? speciesId;
    if (species != null) {
      final speciesUrl = species['url'] as String?;
      if (speciesUrl != null && speciesUrl.isNotEmpty) {
        try {
          final speciesApiId = _extractApiIdFromUrl(speciesUrl);
          final speciesData = await (database.select(database.pokemonSpecies)
            ..where((t) => t.apiId.equals(speciesApiId)))
            .getSingleOrNull();
          speciesId = speciesData?.id;
        } catch (e) {
          print('Error al extraer speciesId de URL $speciesUrl: $e');
          // Continuar sin speciesId (se usará 0 como fallback)
        }
      }
    }
    
    // Extraer URLs de sprites
    final sprites = data['sprites'] as Map<String, dynamic>?;
    String? spriteFrontDefaultUrl;
    String? spriteFrontShinyUrl;
    String? spriteBackDefaultUrl;
    String? spriteBackShinyUrl;
    
    if (sprites != null) {
      spriteFrontDefaultUrl = sprites['front_default'] as String?;
      spriteFrontShinyUrl = sprites['front_shiny'] as String?;
      spriteBackDefaultUrl = sprites['back_default'] as String?;
      spriteBackShinyUrl = sprites['back_shiny'] as String?;
    }
    
    // Extraer URLs de artwork oficial
    String? artworkOfficialUrl;
    String? artworkOfficialShinyUrl;
    if (sprites != null) {
      final other = sprites['other'] as Map<String, dynamic>?;
      if (other != null) {
        final officialArtwork = other['official-artwork'] as Map<String, dynamic>?;
        if (officialArtwork != null) {
          artworkOfficialUrl = officialArtwork['front_default'] as String?;
          artworkOfficialShinyUrl = officialArtwork['front_shiny'] as String?;
        }
      }
    }
    
    // Extraer URLs de cries
    final cries = data['cries'] as Map<String, dynamic>?;
    String? cryLatestUrl;
    String? cryLegacyUrl;
    if (cries != null) {
      cryLatestUrl = cries['latest'] as String?;
      cryLegacyUrl = cries['legacy'] as String?;
    }
    
    final companion = PokemonCompanion(
      apiId: Value(apiId),
      name: Value(name),
      speciesId: Value(speciesId ?? 0), // Requerido, usar 0 si no se encuentra
      baseExperience: Value(_safeIntFromDynamic(data['base_experience'])),
      height: Value(_safeIntFromDynamic(data['height'])),
      weight: Value(_safeIntFromDynamic(data['weight'])),
      isDefault: Value(data['is_default'] as bool? ?? false),
      order: Value(_safeIntFromDynamic(data['order'])),
      // URLs de multimedia
      spriteFrontDefaultUrl: Value(spriteFrontDefaultUrl),
      spriteFrontShinyUrl: Value(spriteFrontShinyUrl),
      spriteBackDefaultUrl: Value(spriteBackDefaultUrl),
      spriteBackShinyUrl: Value(spriteBackShinyUrl),
      artworkOfficialUrl: Value(artworkOfficialUrl),
      artworkOfficialShinyUrl: Value(artworkOfficialShinyUrl),
      cryLatestUrl: Value(cryLatestUrl),
      cryLegacyUrl: Value(cryLegacyUrl),
      // JSON
      spritesJson: Value(_jsonEncode(sprites)),
      criesJson: Value(_jsonEncode(cries)),
      abilitiesJson: Value(_jsonEncode(data['abilities'])),
      formsJson: Value(_jsonEncode(data['forms'])),
      gameIndicesJson: Value(_jsonEncode(data['game_indices'])),
      heldItemsJson: Value(_jsonEncode(data['held_items'])),
      movesJson: Value(_jsonEncode(data['moves'])),
      statsJson: Value(_jsonEncode(data['stats'])),
      typesJson: Value(_jsonEncode(data['types'])),
    );
    
    await database.into(database.pokemon).insert(
      companion,
      mode: InsertMode.replace,
    );
  }
  
  /// Descargar multimedia de pokemon
  Future<void> _downloadPokemonMedia(Map<String, dynamic> pokemonData) async {
    final apiId = pokemonData['id'] as int;
    
    // Obtener pokemon de la DB
    final pokemon = await (database.select(database.pokemon)
      ..where((t) => t.apiId.equals(apiId)))
      .getSingleOrNull();
    
    if (pokemon == null) return;
    
    // Descargar cada tipo de multimedia si existe la URL
    final updates = <String, String?>{};
    
    // Sprites
    if (pokemon.spriteFrontDefaultUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.spriteFrontDefaultUrl!,
          'pokemon/$apiId/sprite_front_default.png',
        );
        updates['spriteFrontDefaultPath'] = path;
      } catch (e) {
        print('Error al descargar sprite front default: $e');
        // No actualizar path, pero mantener URL para reintentar después
      }
    }
    
    if (pokemon.spriteFrontShinyUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.spriteFrontShinyUrl!,
          'pokemon/$apiId/sprite_front_shiny.png',
        );
        updates['spriteFrontShinyPath'] = path;
      } catch (e) {
        print('Error al descargar sprite front shiny: $e');
      }
    }
    
    if (pokemon.spriteBackDefaultUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.spriteBackDefaultUrl!,
          'pokemon/$apiId/sprite_back_default.png',
        );
        updates['spriteBackDefaultPath'] = path;
      } catch (e) {
        print('Error al descargar sprite back default: $e');
      }
    }
    
    if (pokemon.spriteBackShinyUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.spriteBackShinyUrl!,
          'pokemon/$apiId/sprite_back_shiny.png',
        );
        updates['spriteBackShinyPath'] = path;
      } catch (e) {
        print('Error al descargar sprite back shiny: $e');
      }
    }
    
    // Artwork oficial
    if (pokemon.artworkOfficialUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.artworkOfficialUrl!,
          'pokemon/$apiId/artwork_official.png',
        );
        updates['artworkOfficialPath'] = path;
      } catch (e) {
        print('Error al descargar artwork oficial: $e');
      }
    }
    
    if (pokemon.artworkOfficialShinyUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.artworkOfficialShinyUrl!,
          'pokemon/$apiId/artwork_official_shiny.png',
        );
        updates['artworkOfficialShinyPath'] = path;
      } catch (e) {
        print('Error al descargar artwork oficial shiny: $e');
      }
    }
    
    // Cries
    if (pokemon.cryLatestUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.cryLatestUrl!,
          'pokemon/$apiId/cry_latest.ogg',
        );
        updates['cryLatestPath'] = path;
      } catch (e) {
        print('Error al descargar cry latest: $e');
      }
    }
    
    if (pokemon.cryLegacyUrl != null) {
      try {
        final path = await _downloadMediaFile(
          pokemon.cryLegacyUrl!,
          'pokemon/$apiId/cry_legacy.ogg',
        );
        updates['cryLegacyPath'] = path;
      } catch (e) {
        print('Error al descargar cry legacy: $e');
      }
    }
    
    // Actualizar paths en la DB en transacción
    if (updates.isNotEmpty) {
      await database.transaction(() async {
        final companion = PokemonCompanion(
          id: Value(pokemon.id),
          spriteFrontDefaultPath: Value(updates['spriteFrontDefaultPath']),
          spriteFrontShinyPath: Value(updates['spriteFrontShinyPath']),
          spriteBackDefaultPath: Value(updates['spriteBackDefaultPath']),
          spriteBackShinyPath: Value(updates['spriteBackShinyPath']),
          artworkOfficialPath: Value(updates['artworkOfficialPath']),
          artworkOfficialShinyPath: Value(updates['artworkOfficialShinyPath']),
          cryLatestPath: Value(updates['cryLatestPath']),
          cryLegacyPath: Value(updates['cryLegacyPath']),
        );
        
        await (database.update(database.pokemon)..where((t) => t.id.equals(pokemon.id)))
          .write(companion);
      });
    }
  }
  
  /// Descargar archivo multimedia y retornar path local
  Future<String?> _downloadMediaFile(String url, String relativePath) async {
    try {
      // TODO: Implementar descarga real de archivos multimedia
      // Por ahora, retornar null (se implementará con path_provider y storage)
      return null;
    } catch (e) {
      print('Error al descargar archivo multimedia $url: $e');
      return null;
    }
  }
  
  /// Helper para codificar JSON
  String? _jsonEncode(dynamic data) {
    if (data == null) return null;
    try {
      return jsonEncode(data);
    } catch (e) {
      return null;
    }
  }
  
  void dispose() {
    apiClient.dispose();
  }
}


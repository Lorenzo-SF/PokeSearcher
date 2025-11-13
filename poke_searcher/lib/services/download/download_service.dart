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
import '../../utils/logger.dart';

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
    
    // FASE 1: Calcular total y descargar todos los JSON en memoria
    onProgress?.call(DownloadProgress(
      phase: phase,
      currentEntity: 'Preparando descarga...',
      completed: 0,
      total: 0,
    ));
    
    // Estructura para almacenar todos los datos descargados
    final Map<String, List<Map<String, dynamic>>> downloadedData = {};
    
    // FASE 1.1: Calcular total de items
    final Map<String, int> entityTypeCounts = {};
    
    // Obtener el conteo de cada tipo
    for (final entityType in phaseInfo.entityTypes) {
      try {
        final list = await apiClient.getResourceList(endpoint: entityType);
        final count = list['count'] as int;
        entityTypeCounts[entityType] = count;
        totalItems += count;
      } catch (e) {
        Logger.error('Error al calcular total para $entityType', error: e);
        entityTypeCounts[entityType] = 0;
      }
    }
    
    // Notificar inicio de descarga
    onProgress?.call(DownloadProgress(
      phase: phase,
      currentEntity: 'Iniciando descarga...',
      completed: 0,
      total: totalItems,
    ));
    
    // FASE 1.2: Descargar todos los JSON en memoria (sin delays adicionales, el api_client ya maneja rate limiting)
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
            
            // Actualizar progreso de descarga (cada 10 items para no saturar)
            if (downloadedCount % 10 == 0 || entityData.length == count) {
              onProgress?.call(DownloadProgress(
                phase: phase,
                currentEntity: 'Descargando $entityType... (${entityData.length}/$count)',
                completed: downloadedCount,
                total: totalItems,
              ));
            }
            
            // NO añadir delay adicional - el api_client ya maneja rate limiting (300ms)
          } catch (e) {
            // Error silencioso para no saturar logs - solo errores críticos
          }
        }
        
        downloadedData[entityType] = entityData;
      } catch (e) {
        Logger.error('Error al descargar tipo $entityType', context: LogContext.essential, error: e);
        downloadedData[entityType] = []; // Lista vacía si falla
      }
    }
    
    // FASE 2: Insertar todos los datos descargados en batch (usando transacciones por tipo)
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
      
      // Insertar todos los datos de este tipo en una sola transacción
      try {
        await database.transaction(() async {
          for (final data in entityDataList) {
            try {
              await _saveEntityData(entityType, data);
              insertedCount++;
            } catch (e) {
              Logger.error('Error al guardar datos de $entityType', context: LogContext.essential, error: e);
            }
          }
        });
        
        // Actualizar progreso después de insertar todo el tipo
        onProgress?.call(DownloadProgress(
          phase: phase,
          currentEntity: 'Guardando $entityType... ($insertedCount/$downloadedCount)',
          completed: downloadedCount + insertedCount,
          total: totalItems * 2, // Descarga (totalItems) + Inserción (totalItems)
        ));
      } catch (e) {
        Logger.error('Error en transacción al guardar $entityType', context: LogContext.essential, error: e);
        // Intentar guardar uno por uno si falla la transacción
        for (final data in entityDataList) {
          try {
            await _saveEntityData(entityType, data);
            insertedCount++;
          } catch (e2) {
            Logger.error('Error al guardar datos de $entityType', context: LogContext.essential, error: e2);
          }
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
    ));
  }
  
  /// Descargar un tipo de entidad específico (SECUENCIAL - un recurso a la vez)
  Future<void> _downloadEntityType({
    required DownloadPhase phase,
    required String entityType, // Offset para acumular progreso total
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
        } catch (e) {
          // Si hay error, esperar 2 segundos y reintentar
          Logger.error('Error al descargar recurso, reintentando...', context: LogContext.essential, error: e);
          
          // Actualizar estado para informar al usuario
          onProgress?.call(DownloadProgress(
            phase: phase,
            currentEntity: '$entityType (reintentando...)',
            completed: completed,
            total: count,
          ));
          
          // Esperar 2 segundos antes de reintentar
          await Future.delayed(const Duration(seconds: 2));
          
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
            Logger.error('Error al reintentar descargar recurso, saltando...', context: LogContext.essential, error: retryError);
            // Si sigue fallando, saltar este recurso y continuar
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
      final regionDao = RegionDao(database);
      final region = await regionDao.getRegionById(regionId);
      final regionName = region?.name ?? 'Región $regionId';
      
      final incompletePokedexes = await getIncompletePokedexes(regionId);
      final isComplete = incompletePokedexes.isEmpty;
      
      if (isComplete) {
        Logger.region('Completamente descargada', regionName: regionName);
      } else {
        Logger.region('Incompleta (${incompletePokedexes.length} pokedexes faltantes)', regionName: regionName);
        // Log detallado para depuración
        for (final url in incompletePokedexes) {
          final apiId = _extractApiIdFromUrl(url);
          Logger.pokedex('Pokedex incompleta', pokedexName: 'ID: $apiId');
        }
      }
      
      return isComplete;
    } catch (e) {
      Logger.error('Error al verificar región completa', context: LogContext.region, error: e);
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
        bool isIncomplete = false;
        for (final entry in entries) {
          // Verificar que existe el pokemon-species
          final species = await (database.select(database.pokemonSpecies)
            ..where((t) => t.id.equals(entry.pokemonSpeciesId)))
            .getSingleOrNull();
          
          if (species == null) {
            isIncomplete = true;
            break; // Esta pokedex está incompleta
          }
          
          // Verificar que existe al menos un pokemon de esta especie
          final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
          if (pokemons.isEmpty) {
            isIncomplete = true;
            break; // Esta pokedex está incompleta
          }
        }
        
        if (isIncomplete) {
          incompleteUrls.add(pokedexUrl);
        }
      }
      
      return incompleteUrls;
    } catch (e) {
      Logger.error('Error al obtener pokedexes incompletas', context: LogContext.pokedex, error: e);
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
      
      // FASE 1: Descargar todas las pokedexes (solo datos, sin entradas)
      // Recopilar pokemon-species únicas con sus entry_numbers por pokedex
      final Map<String, Set<Map<String, dynamic>>> speciesToPokedexEntries = {}; // speciesUrl -> Set de {pokedexApiId, entryNumber}
      final List<Map<String, dynamic>> pokedexInfoList = [];
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando info de las pokedexes. Registrándolas en base de datos...',
        completed: 0,
        total: 0,
      ));
      
      // Descargar todas las pokedexes y recopilar especies
      int pokedexIndex = 0;
      for (final pokedexUrl in incompleteUrls) {
        pokedexIndex++;
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
          
          // Guardar pokedex (sin entradas todavía)
          await database.transaction(() async {
            await _savePokedexOnly(pokedexData);
          });
          
          // Recopilar especies únicas con sus entry_numbers por pokedex
          if (pokemonEntries != null) {
            for (final entry in pokemonEntries) {
              final pokemonSpecies = entry['pokemon_species'] as Map<String, dynamic>?;
              if (pokemonSpecies != null) {
                final speciesUrl = pokemonSpecies['url'] as String?;
                final entryNumber = _safeIntFromDynamic(entry['entry_number']);
                if (speciesUrl != null && entryNumber != null) {
                  if (!speciesToPokedexEntries.containsKey(speciesUrl)) {
                    speciesToPokedexEntries[speciesUrl] = {};
                  }
                  speciesToPokedexEntries[speciesUrl]!.add({
                    'pokedexApiId': pokedexApiId,
                    'entryNumber': entryNumber,
                  });
                }
              }
            }
          }
          
          pokedexInfoList.add({
            'url': pokedexUrl,
            'name': urlToName[pokedexUrl] ?? pokedexData['name'] as String? ?? 'Pokedex',
            'apiId': pokedexApiId,
            'data': pokedexData,
          });
          
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokedex $pokedexIndex/${incompleteUrls.length}: ${urlToName[pokedexUrl] ?? pokedexData['name'] as String? ?? 'Pokedex'}',
            completed: pokedexIndex,
            total: incompleteUrls.length,
          ));
        } catch (e) {
          Logger.error('Error al descargar pokedex', context: LogContext.pokedex, error: e);
        }
      }
      
      // Obtener lista de pokemon-species únicas
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Obteniendo lista de pokemon-species únicas...',
        completed: pokedexInfoList.length,
        total: pokedexInfoList.length,
      ));
      
      final uniqueSpeciesUrls = speciesToPokedexEntries.keys.toList();
      final totalItems = pokedexInfoList.length + uniqueSpeciesUrls.length;
      
      // FASE 2: Descargar todas las especies únicas en batch
      int completedItems = pokedexInfoList.length; // Ya descargamos las pokedexes
      final Map<String, Map<String, dynamic>> downloadedSpeciesData = {}; // speciesUrl -> speciesData
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando todas las pokemon-species y sus datos relacionados (tipos, versiones, traducciones, etc.)...',
        completed: completedItems,
        total: totalItems,
      ));
      
      for (int i = 0; i < uniqueSpeciesUrls.length; i++) {
        final speciesUrl = uniqueSpeciesUrls[i];
        try {
          final speciesData = await apiClient.getResourceByUrl(speciesUrl);
          downloadedSpeciesData[speciesUrl] = speciesData;
          
          // Guardar especie
          await database.transaction(() async {
            await _savePokemonSpecies(speciesData);
          });
          
          // Descargar evolution chain si existe
          final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
          if (evolutionChainUrl != null) {
            try {
              await _downloadEvolutionChain(evolutionChainUrl);
            } catch (e) {
              Logger.error('Error al descargar evolution chain, reintentando...', context: LogContext.pokemon, error: e);
              await Future.delayed(const Duration(seconds: 2));
              await _downloadEvolutionChain(evolutionChainUrl);
            }
          }
          
          completedItems++;
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokemon-species ${i + 1}/${uniqueSpeciesUrls.length} (incluye tipos, versiones, traducciones, etc.)',
            completed: completedItems,
            total: totalItems,
          ));
        } catch (e) {
          Logger.error('Error al descargar especie, reintentando...', context: LogContext.pokemon, error: e);
          await Future.delayed(const Duration(seconds: 2));
          final speciesData = await apiClient.getResourceByUrl(speciesUrl);
          downloadedSpeciesData[speciesUrl] = speciesData;
          await database.transaction(() async {
            await _savePokemonSpecies(speciesData);
          });
          
          // Descargar evolution chain si existe
          final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
          if (evolutionChainUrl != null) {
            try {
              await _downloadEvolutionChain(evolutionChainUrl);
            } catch (e) {
              await Future.delayed(const Duration(seconds: 2));
              await _downloadEvolutionChain(evolutionChainUrl);
            }
          }
          
          completedItems++;
        }
      }
      
      // FASE 3: Procesar variantes y descargar todos los pokemon únicos
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Procesando variantes y obteniendo lista de pokemon únicos...',
        completed: completedItems,
        total: totalItems,
      ));
      
      final Set<String> uniquePokemonUrls = {};
      for (final speciesData in downloadedSpeciesData.values) {
        final variantInfo = await _processPokemonVariants(speciesData);
        final defaultPokemon = variantInfo['default'] as Map<String, dynamic>?;
        final regionalVariants = variantInfo['regional'] as List? ?? [];
        final specialVariants = variantInfo['special'] as List? ?? [];
        
        if (defaultPokemon != null) {
          uniquePokemonUrls.add(defaultPokemon['url'] as String);
        }
        for (final variant in regionalVariants) {
          final pokemon = variant['pokemon'] as Map<String, dynamic>?;
          if (pokemon != null) {
            uniquePokemonUrls.add(pokemon['url'] as String);
          }
        }
        for (final pokemon in specialVariants) {
          uniquePokemonUrls.add(pokemon['url'] as String);
        }
      }
      
      // Actualizar total para incluir pokemon
      final totalItemsWithPokemon = totalItems + uniquePokemonUrls.length;
      
      // Descargar todos los pokemon únicos
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando todos los pokemon únicos (incluye stats, abilities, moves, sprites, etc.)...',
        completed: completedItems,
        total: totalItemsWithPokemon,
      ));
      
      final List<String> pokemonUrlsList = uniquePokemonUrls.toList();
      for (int i = 0; i < pokemonUrlsList.length; i++) {
        final pokemonUrl = pokemonUrlsList[i];
        try {
          await _downloadPokemonComplete(pokemonUrl);
          completedItems++;
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokemon ${i + 1}/${pokemonUrlsList.length} (stats, abilities, moves, sprites, etc.)',
            completed: completedItems,
            total: totalItemsWithPokemon,
          ));
        } catch (e) {
          Logger.error('Error al descargar pokemon, reintentando...', context: LogContext.pokemon, error: e);
          await Future.delayed(const Duration(seconds: 2));
          await _downloadPokemonComplete(pokemonUrl);
          completedItems++;
        }
      }
      
      // FASE 4: Procesar variantes y asignar pokedex
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Guardando relaciones con pokedexes y procesando variantes...',
        completed: completedItems,
        total: totalItemsWithPokemon,
      ));
      
      int speciesProcessed = 0;
      final totalSpeciesToProcess = downloadedSpeciesData.length;
      
      for (final entry in downloadedSpeciesData.entries) {
        final speciesUrl = entry.key;
        final speciesData = entry.value;
        speciesProcessed++;
        
        // Procesar variantes
        final variantInfo = await _processPokemonVariants(speciesData);
        
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Guardando relaciones: $speciesProcessed/$totalSpeciesToProcess especies procesadas',
          completed: completedItems,
          total: totalItemsWithPokemon,
        ));
        final defaultPokemon = variantInfo['default'] as Map<String, dynamic>?;
        final regionalVariants = variantInfo['regional'] as List? ?? [];
        final specialVariants = variantInfo['special'] as List? ?? [];
        
        // Obtener entry_numbers para esta especie de todas las pokedexes
        final pokedexEntries = speciesToPokedexEntries[speciesUrl] ?? {};
        
        // Obtener especie de la DB
        final speciesApiId = speciesData['id'] as int;
        final species = await (database.select(database.pokemonSpecies)
          ..where((t) => t.apiId.equals(speciesApiId)))
          .getSingleOrNull();
        
        if (species == null) continue;
        
        // Obtener pokemon default
        if (defaultPokemon == null) continue;
        
        final defaultPokemonApiId = _extractApiIdFromUrl(defaultPokemon['url'] as String);
        final defaultPokemonData = await (database.select(database.pokemon)
          ..where((t) => t.apiId.equals(defaultPokemonApiId)))
          .getSingleOrNull();
        
        if (defaultPokemonData == null) continue;
        
        // Identificar pokedexes de variantes regionales para excluirlas del default
        final regionalPokedexApiIds = <int>{};
        for (final variant in regionalVariants) {
          final variantRegionId = variant['regionId'] as int?;
          if (variantRegionId != null) {
            final regionPokedexes = await pokedexDao.getPokedexByRegion(variantRegionId);
            for (final pokedex in regionPokedexes) {
              regionalPokedexApiIds.add(pokedex.apiId);
            }
          }
        }
        
        // Asignar entradas de pokedex para el pokemon default
        // (todas las pokedexes donde aparece la especie, excepto las de variantes regionales)
        for (final entryInfo in pokedexEntries) {
          final pokedexApiId = entryInfo['pokedexApiId'] as int;
          final entryNumber = entryInfo['entryNumber'] as int;
          
          // Excluir pokedexes de variantes regionales y la nacional (se añade después)
          if (regionalPokedexApiIds.contains(pokedexApiId)) continue;
          
          final pokedex = await pokedexDao.getPokedexByApiId(pokedexApiId);
          if (pokedex != null && pokedex.name != 'national') {
            try {
              await database.transaction(() async {
                final entryCompanion = PokedexEntriesCompanion.insert(
                  pokedexId: pokedex.id,
                  pokemonSpeciesId: species.id,
                  entryNumber: entryNumber,
                );
                await database.into(database.pokedexEntries).insert(
                  entryCompanion,
                  mode: InsertMode.replace,
                );
              });
            } catch (e) {
              Logger.error('Error al guardar entrada de pokedex', context: LogContext.pokedex, error: e);
            }
          }
        }
        
        // Asignar variantes regionales a sus pokedexes correspondientes
        for (final variant in regionalVariants) {
          final pokemon = variant['pokemon'] as Map<String, dynamic>?;
          final variantRegionId = variant['regionId'] as int?;
          if (pokemon == null || variantRegionId == null) continue;
          
          final variantPokemonApiId = _extractApiIdFromUrl(pokemon['url'] as String);
          final variantPokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(variantPokemonApiId)))
            .getSingleOrNull();
          
          if (variantPokemonData != null) {
            // Obtener pokedexes de la región de la variante
            final regionPokedexes = await pokedexDao.getPokedexByRegion(variantRegionId);
            
            // Asignar a las pokedexes de esa región (solo las que están en pokedexEntries)
            for (final entryInfo in pokedexEntries) {
              final pokedexApiId = entryInfo['pokedexApiId'] as int;
              final entryNumber = entryInfo['entryNumber'] as int;
              
              // Verificar si esta pokedex pertenece a la región de la variante
              for (final regionPokedex in regionPokedexes) {
                if (regionPokedex.apiId == pokedexApiId && regionPokedex.name != 'national') {
                  try {
                    await database.transaction(() async {
                      final entryCompanion = PokedexEntriesCompanion.insert(
                        pokedexId: regionPokedex.id,
                        pokemonSpeciesId: species.id,
                        entryNumber: entryNumber,
                      );
                      await database.into(database.pokedexEntries).insert(
                        entryCompanion,
                        mode: InsertMode.replace,
                      );
                    });
                  } catch (e) {
                    Logger.error('Error al guardar entrada de pokedex para variante', context: LogContext.pokedex, error: e);
                  }
                  break;
                }
              }
            }
            
            // Guardar relación de variante
            await database.pokemonVariantsDao.insertVariant(
              pokemonId: defaultPokemonData.id,
              variantPokemonId: variantPokemonData.id,
            );
          }
        }
        
        // Asignar variantes especiales (solo relación, sin pokedex)
        for (final pokemon in specialVariants) {
          final variantPokemonApiId = _extractApiIdFromUrl(pokemon['url'] as String);
          final variantPokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(variantPokemonApiId)))
            .getSingleOrNull();
          
          if (variantPokemonData != null) {
            await database.pokemonVariantsDao.insertVariant(
              pokemonId: defaultPokemonData.id,
              variantPokemonId: variantPokemonData.id,
            );
          }
        }
        
        // Asignar pokedex nacional a todos (default y variantes regionales comparten el mismo entry_number)
        final nationalEntryNumber = _getNationalEntryNumber(speciesData);
        if (nationalEntryNumber != null) {
          final nationalPokedex = await (database.select(database.pokedex)
            ..where((t) => t.name.equals('national')))
            .getSingleOrNull();
          
          if (nationalPokedex != null) {
            try {
              await database.transaction(() async {
                final entryCompanion = PokedexEntriesCompanion.insert(
                  pokedexId: nationalPokedex.id,
                  pokemonSpeciesId: species.id,
                  entryNumber: nationalEntryNumber,
                );
                await database.into(database.pokedexEntries).insert(
                  entryCompanion,
                  mode: InsertMode.replace,
                );
              });
            } catch (e) {
              Logger.error('Error al guardar entrada de pokedex nacional', context: LogContext.pokedex, error: e);
            }
          }
        }
      }
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descarga completada. Todas las relaciones guardadas.',
        completed: totalItemsWithPokemon,
        total: totalItemsWithPokemon,
      ));
    } catch (e) {
      Logger.error('Error al descargar pokedexes incompletas', context: LogContext.pokedex, error: e);
      rethrow;
    }
  }
  
  /// Descargar toda una región en transacción
  /// Si la región está a medias, se elimina todo y se descarga de nuevo
  /// Usa el mismo flujo optimizado que downloadIncompletePokedexes
  Future<void> downloadRegionComplete({
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
      final allPokedexes = regionData['pokedexes'] as List?;
      
      if (allPokedexes == null || allPokedexes.isEmpty) {
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Región sin pokedex',
          completed: 1,
          total: 1,
        ));
        return; // Región sin pokedex
      }
      
      // Crear lista de URLs de todas las pokedexes (simular incompletas para usar el mismo flujo)
      final List<String> allPokedexUrls = [];
      final Map<String, String> urlToName = {};
      
      for (final pokedexRef in allPokedexes) {
        final url = pokedexRef['url'] as String;
        final name = pokedexRef['name'] as String? ?? 'Pokedex';
        allPokedexUrls.add(url);
        urlToName[url] = name;
      }
      
      // Usar el mismo flujo optimizado que downloadIncompletePokedexes
      // FASE 1: Descargar todas las pokedexes (solo datos, sin entradas)
      final Map<String, Set<Map<String, dynamic>>> speciesToPokedexEntries = {};
      final List<Map<String, dynamic>> pokedexInfoList = [];
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando info de las pokedexes. Registrándolas en base de datos...',
        completed: 0,
        total: 0,
      ));
      
      int pokedexIndex = 0;
      for (final pokedexUrl in allPokedexUrls) {
        pokedexIndex++;
        try {
          final pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
          final pokemonEntries = pokedexData['pokemon_entries'] as List?;
          final pokedexApiId = _extractApiIdFromUrl(pokedexUrl);
          
          // Guardar pokedex (sin entradas todavía)
          await database.transaction(() async {
            await _savePokedexOnly(pokedexData);
          });
          
          // Recopilar especies únicas con sus entry_numbers por pokedex
          if (pokemonEntries != null) {
            for (final entry in pokemonEntries) {
              final pokemonSpecies = entry['pokemon_species'] as Map<String, dynamic>?;
              if (pokemonSpecies != null) {
                final speciesUrl = pokemonSpecies['url'] as String?;
                final entryNumber = _safeIntFromDynamic(entry['entry_number']);
                if (speciesUrl != null && entryNumber != null) {
                  if (!speciesToPokedexEntries.containsKey(speciesUrl)) {
                    speciesToPokedexEntries[speciesUrl] = {};
                  }
                  speciesToPokedexEntries[speciesUrl]!.add({
                    'pokedexApiId': pokedexApiId,
                    'entryNumber': entryNumber,
                  });
                }
              }
            }
          }
          
          pokedexInfoList.add({
            'url': pokedexUrl,
            'name': urlToName[pokedexUrl] ?? pokedexData['name'] as String? ?? 'Pokedex',
            'apiId': pokedexApiId,
            'data': pokedexData,
          });
          
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokedex $pokedexIndex/${allPokedexUrls.length}: ${urlToName[pokedexUrl] ?? pokedexData['name'] as String? ?? 'Pokedex'}',
            completed: pokedexIndex,
            total: allPokedexUrls.length,
          ));
        } catch (e) {
          Logger.error('Error al descargar pokedex', context: LogContext.pokedex, error: e);
        }
      }
      
      // Obtener lista de pokemon-species únicas
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Obteniendo lista de pokemon-species únicas...',
        completed: pokedexInfoList.length,
        total: pokedexInfoList.length,
      ));
      
      final uniqueSpeciesUrls = speciesToPokedexEntries.keys.toList();
      final totalItems = pokedexInfoList.length + uniqueSpeciesUrls.length;
      
      // FASE 2: Descargar todas las especies únicas en batch
      int completedItems = pokedexInfoList.length;
      final Map<String, Map<String, dynamic>> downloadedSpeciesData = {};
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando todas las pokemon-species y sus datos relacionados (tipos, versiones, traducciones, etc.)...',
        completed: completedItems,
        total: totalItems,
      ));
      
      for (int i = 0; i < uniqueSpeciesUrls.length; i++) {
        final speciesUrl = uniqueSpeciesUrls[i];
        try {
          final speciesData = await apiClient.getResourceByUrl(speciesUrl);
          downloadedSpeciesData[speciesUrl] = speciesData;
          
          await database.transaction(() async {
            await _savePokemonSpecies(speciesData);
          });
          
          final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
          if (evolutionChainUrl != null) {
            try {
              await _downloadEvolutionChain(evolutionChainUrl);
            } catch (e) {
              Logger.error('Error al descargar evolution chain, reintentando...', context: LogContext.pokemon, error: e);
              await Future.delayed(const Duration(seconds: 2));
              await _downloadEvolutionChain(evolutionChainUrl);
            }
          }
          
          completedItems++;
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokemon-species ${i + 1}/${uniqueSpeciesUrls.length} (incluye tipos, versiones, traducciones, etc.)',
            completed: completedItems,
            total: totalItems,
          ));
        } catch (e) {
          Logger.error('Error al descargar especie, reintentando...', context: LogContext.pokemon, error: e);
          await Future.delayed(const Duration(seconds: 2));
          final speciesData = await apiClient.getResourceByUrl(speciesUrl);
          downloadedSpeciesData[speciesUrl] = speciesData;
          await database.transaction(() async {
            await _savePokemonSpecies(speciesData);
          });
          
          final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
          if (evolutionChainUrl != null) {
            try {
              await _downloadEvolutionChain(evolutionChainUrl);
            } catch (e) {
              await Future.delayed(const Duration(seconds: 2));
              await _downloadEvolutionChain(evolutionChainUrl);
            }
          }
          
          completedItems++;
        }
      }
      
      // FASE 3: Procesar variantes y descargar todos los pokemon únicos
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Procesando variantes y obteniendo lista de pokemon únicos...',
        completed: completedItems,
        total: totalItems,
      ));
      
      final Set<String> uniquePokemonUrls = {};
      for (final speciesData in downloadedSpeciesData.values) {
        final variantInfo = await _processPokemonVariants(speciesData);
        final defaultPokemon = variantInfo['default'] as Map<String, dynamic>?;
        final regionalVariants = variantInfo['regional'] as List? ?? [];
        final specialVariants = variantInfo['special'] as List? ?? [];
        
        if (defaultPokemon != null) {
          uniquePokemonUrls.add(defaultPokemon['url'] as String);
        }
        for (final variant in regionalVariants) {
          final pokemon = variant['pokemon'] as Map<String, dynamic>?;
          if (pokemon != null) {
            uniquePokemonUrls.add(pokemon['url'] as String);
          }
        }
        for (final pokemon in specialVariants) {
          uniquePokemonUrls.add(pokemon['url'] as String);
        }
      }
      
      final totalItemsWithPokemon = totalItems + uniquePokemonUrls.length;
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descargando todos los pokemon únicos (incluye stats, abilities, moves, sprites, etc.)...',
        completed: completedItems,
        total: totalItemsWithPokemon,
      ));
      
      final List<String> pokemonUrlsList = uniquePokemonUrls.toList();
      for (int i = 0; i < pokemonUrlsList.length; i++) {
        final pokemonUrl = pokemonUrlsList[i];
        try {
          await _downloadPokemonComplete(pokemonUrl);
          completedItems++;
          onProgress?.call(DownloadProgress(
            phase: DownloadPhase.regionData,
            currentEntity: 'Descargando pokemon ${i + 1}/${pokemonUrlsList.length} (stats, abilities, moves, sprites, etc.)',
            completed: completedItems,
            total: totalItemsWithPokemon,
          ));
        } catch (e) {
          Logger.error('Error al descargar pokemon, reintentando...', context: LogContext.pokemon, error: e);
          await Future.delayed(const Duration(seconds: 2));
          await _downloadPokemonComplete(pokemonUrl);
          completedItems++;
        }
      }
      
      // FASE 4: Procesar variantes y asignar pokedex
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Guardando relaciones con pokedexes y procesando variantes...',
        completed: completedItems,
        total: totalItemsWithPokemon,
      ));
      
      int speciesProcessed = 0;
      final totalSpeciesToProcess = downloadedSpeciesData.length;
      
      for (final entry in downloadedSpeciesData.entries) {
        final speciesUrl = entry.key;
        final speciesData = entry.value;
        speciesProcessed++;
        
        final variantInfo = await _processPokemonVariants(speciesData);
        
        onProgress?.call(DownloadProgress(
          phase: DownloadPhase.regionData,
          currentEntity: 'Guardando relaciones: $speciesProcessed/$totalSpeciesToProcess especies procesadas',
          completed: completedItems,
          total: totalItemsWithPokemon,
        ));
        
        final defaultPokemon = variantInfo['default'] as Map<String, dynamic>?;
        final regionalVariants = variantInfo['regional'] as List? ?? [];
        final specialVariants = variantInfo['special'] as List? ?? [];
        
        final pokedexEntries = speciesToPokedexEntries[speciesUrl] ?? {};
        
        final speciesApiId = speciesData['id'] as int;
        final species = await (database.select(database.pokemonSpecies)
          ..where((t) => t.apiId.equals(speciesApiId)))
          .getSingleOrNull();
        
        if (species == null) continue;
        
        if (defaultPokemon == null) continue;
        
        final defaultPokemonApiId = _extractApiIdFromUrl(defaultPokemon['url'] as String);
        final defaultPokemonData = await (database.select(database.pokemon)
          ..where((t) => t.apiId.equals(defaultPokemonApiId)))
          .getSingleOrNull();
        
        if (defaultPokemonData == null) continue;
        
        final regionalPokedexApiIds = <int>{};
        for (final variant in regionalVariants) {
          final variantRegionId = variant['regionId'] as int?;
          if (variantRegionId != null) {
            final regionPokedexes = await pokedexDao.getPokedexByRegion(variantRegionId);
            for (final pokedex in regionPokedexes) {
              regionalPokedexApiIds.add(pokedex.apiId);
            }
          }
        }
        
        // Asignar entradas de pokedex para el pokemon default
        for (final entryInfo in pokedexEntries) {
          final pokedexApiId = entryInfo['pokedexApiId'] as int;
          final entryNumber = entryInfo['entryNumber'] as int;
          
          if (regionalPokedexApiIds.contains(pokedexApiId)) continue;
          
          final pokedex = await pokedexDao.getPokedexByApiId(pokedexApiId);
          if (pokedex != null && pokedex.name != 'national') {
            try {
              await database.transaction(() async {
                final entryCompanion = PokedexEntriesCompanion.insert(
                  pokedexId: pokedex.id,
                  pokemonSpeciesId: species.id,
                  entryNumber: entryNumber,
                );
                await database.into(database.pokedexEntries).insert(
                  entryCompanion,
                  mode: InsertMode.replace,
                );
              });
            } catch (e) {
              Logger.error('Error al guardar entrada de pokedex', context: LogContext.pokedex, error: e);
            }
          }
        }
        
        // Asignar variantes regionales
        for (final variant in regionalVariants) {
          final pokemon = variant['pokemon'] as Map<String, dynamic>?;
          final variantRegionId = variant['regionId'] as int?;
          if (pokemon == null || variantRegionId == null) continue;
          
          final variantPokemonApiId = _extractApiIdFromUrl(pokemon['url'] as String);
          final variantPokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(variantPokemonApiId)))
            .getSingleOrNull();
          
          if (variantPokemonData != null) {
            final regionPokedexes = await pokedexDao.getPokedexByRegion(variantRegionId);
            
            for (final entryInfo in pokedexEntries) {
              final pokedexApiId = entryInfo['pokedexApiId'] as int;
              final entryNumber = entryInfo['entryNumber'] as int;
              
              for (final regionPokedex in regionPokedexes) {
                if (regionPokedex.apiId == pokedexApiId && regionPokedex.name != 'national') {
                  try {
                    await database.transaction(() async {
                      final entryCompanion = PokedexEntriesCompanion.insert(
                        pokedexId: regionPokedex.id,
                        pokemonSpeciesId: species.id,
                        entryNumber: entryNumber,
                      );
                      await database.into(database.pokedexEntries).insert(
                        entryCompanion,
                        mode: InsertMode.replace,
                      );
                    });
                  } catch (e) {
                    Logger.error('Error al guardar entrada de pokedex para variante', context: LogContext.pokedex, error: e);
                  }
                  break;
                }
              }
            }
            
            await database.pokemonVariantsDao.insertVariant(
              pokemonId: defaultPokemonData.id,
              variantPokemonId: variantPokemonData.id,
            );
          }
        }
        
        // Asignar variantes especiales
        for (final pokemon in specialVariants) {
          final variantPokemonApiId = _extractApiIdFromUrl(pokemon['url'] as String);
          final variantPokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(variantPokemonApiId)))
            .getSingleOrNull();
          
          if (variantPokemonData != null) {
            await database.pokemonVariantsDao.insertVariant(
              pokemonId: defaultPokemonData.id,
              variantPokemonId: variantPokemonData.id,
            );
          }
        }
        
        // Asignar pokedex nacional
        final nationalEntryNumber = _getNationalEntryNumber(speciesData);
        if (nationalEntryNumber != null) {
          final nationalPokedex = await (database.select(database.pokedex)
            ..where((t) => t.name.equals('national')))
            .getSingleOrNull();
          
          if (nationalPokedex != null) {
            try {
              await database.transaction(() async {
                final entryCompanion = PokedexEntriesCompanion.insert(
                  pokedexId: nationalPokedex.id,
                  pokemonSpeciesId: species.id,
                  entryNumber: nationalEntryNumber,
                );
                await database.into(database.pokedexEntries).insert(
                  entryCompanion,
                  mode: InsertMode.replace,
                );
              });
            } catch (e) {
              Logger.error('Error al guardar entrada de pokedex nacional', context: LogContext.pokedex, error: e);
            }
          }
        }
      }
      
      onProgress?.call(DownloadProgress(
        phase: DownloadPhase.regionData,
        currentEntity: 'Descarga completada. Todas las relaciones guardadas.',
        completed: totalItemsWithPokemon,
        total: totalItemsWithPokemon,
      ));
    } catch (e) {
      Logger.error('Error al descargar región completa', context: LogContext.region, error: e);
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
    void Function(String speciesUrl)? onSpeciesDownloaded,
  }) async {
    // Descargar datos de la pokedex desde la API con reintento
    Map<String, dynamic> pokedexData;
    try {
      pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
    } catch (e) {
      Logger.error('Error al descargar pokedex, reintentando...', context: LogContext.pokedex, error: e);
      await Future.delayed(const Duration(seconds: 2));
      pokedexData = await apiClient.getResourceByUrl(pokedexUrl);
    }
    
    final pokedexName = pokedexData['name'] as String? ?? 'Pokedex';
    Logger.pokedex('Iniciando descarga', pokedexName: pokedexName);
    
    // Guardar pokedex (sin entradas todavía, se guardarán después)
    await database.transaction(() async {
      await _savePokedexOnly(pokedexData);
    });
    
    // Obtener entradas de pokemon
    final pokemonEntries = pokedexData['pokemon_entries'] as List?;
    if (pokemonEntries == null || pokemonEntries.isEmpty) {
      return;
    }
    
    final totalSpecies = pokemonEntries.length;
    
    // Obtener el ID de la pokedex guardada
    final pokedexApiId = pokedexData['id'] as int;
    final pokedex = await (database.select(database.pokedex)
      ..where((t) => t.apiId.equals(pokedexApiId)))
      .getSingle();
    
    // Descargar cada pokemon-species y sus datos, y guardar la entrada de pokedex
    for (int speciesIndex = 0; speciesIndex < pokemonEntries.length; speciesIndex++) {
      final entry = pokemonEntries[speciesIndex];
      final pokemonSpecies = entry['pokemon_species'] as Map<String, dynamic>?;
      if (pokemonSpecies == null) continue;
      
      final speciesUrl = pokemonSpecies['url'] as String;
      final entryNumber = _safeIntFromDynamic(entry['entry_number']);
      
      // Notificar progreso
      onProgress?.call(speciesIndex, totalSpecies);
      
      // Descargar pokemon-species (esto también usa transacciones internamente)
      try {
        await _downloadPokemonSpeciesComplete(speciesUrl);
        // Notificar que esta especie fue descargada
        onSpeciesDownloaded?.call(speciesUrl);
      } catch (e) {
        Logger.error('Error al descargar pokemon-species, reintentando...', context: LogContext.pokemon, error: e);
        await Future.delayed(const Duration(seconds: 2));
        await _downloadPokemonSpeciesComplete(speciesUrl);
        // Notificar que esta especie fue descargada (después del reintento)
        onSpeciesDownloaded?.call(speciesUrl);
      }
      
      // Ahora que el pokemon-species está descargado, guardar la entrada de pokedex
      if (entryNumber != null) {
        try {
          final speciesApiId = _extractApiIdFromUrl(speciesUrl);
          final species = await (database.select(database.pokemonSpecies)
            ..where((t) => t.apiId.equals(speciesApiId)))
            .getSingleOrNull();
          
          if (species != null) {
            await database.transaction(() async {
              final entryCompanion = PokedexEntriesCompanion(
                pokedexId: Value(pokedex.id),
                pokemonSpeciesId: Value(species.id),
                entryNumber: Value(entryNumber),
              );
              
              await database.into(database.pokedexEntries).insert(
                entryCompanion,
                mode: InsertMode.replace,
              );
            });
          }
        } catch (e) {
          Logger.error('Error al guardar entrada de pokedex', context: LogContext.pokedex, error: e);
        }
      }
    }
    
    Logger.pokedex('Descarga completada', pokedexName: pokedexName);
  }
  
  /// Guardar solo la pokedex (sin entradas, se guardarán después de descargar pokemon-species)
  Future<void> _savePokedexOnly(Map<String, dynamic> data) async {
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
        Logger.error('Error al extraer regionId de URL', context: LogContext.region, error: e);
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
    
    // Guardar pokedex (sin entradas todavía)
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
  }
  
  /// Descargar pokemon-species completo y todo lo que cuelga
  /// Ahora procesa variantes y asigna pokedex según las reglas
  Future<void> _downloadPokemonSpeciesComplete(String speciesUrl) async {
    // Asegurar que existe la región Nacional
    await _ensureNationalRegionExists();
    
    // Descargar datos desde la API con reintento
    Map<String, dynamic> speciesData;
    try {
      speciesData = await apiClient.getResourceByUrl(speciesUrl);
    } catch (e) {
      Logger.error('Error al descargar species, reintentando...', context: LogContext.pokemon, error: e);
      await Future.delayed(const Duration(seconds: 2));
      speciesData = await apiClient.getResourceByUrl(speciesUrl);
    }
    
    // Guardar pokemon-species en transacción
    await database.transaction(() async {
      await _savePokemonSpecies(speciesData);
    });
    
    // Descargar evolution chain si existe
    final evolutionChainUrl = speciesData['evolution_chain']?['url'] as String?;
    if (evolutionChainUrl != null) {
      try {
        await _downloadEvolutionChain(evolutionChainUrl);
      } catch (e) {
        Logger.error('Error al descargar evolution chain, reintentando...', context: LogContext.pokemon, error: e);
        await Future.delayed(const Duration(seconds: 2));
        await _downloadEvolutionChain(evolutionChainUrl);
      }
    }
    
    // Procesar variantes
    final variantInfo = await _processPokemonVariants(speciesData);
    final defaultPokemon = variantInfo['default'] as Map<String, dynamic>?;
    final regionalVariants = variantInfo['regional'] as List? ?? [];
    final specialVariants = variantInfo['special'] as List? ?? [];
    
    // Descargar pokemon default
    if (defaultPokemon != null) {
      final pokemonUrl = defaultPokemon['url'] as String;
      try {
        await _downloadPokemonComplete(pokemonUrl);
        
        // Obtener pokemon de la DB para asignar pokedex
        final pokemonApiId = _extractApiIdFromUrl(pokemonUrl);
        final pokemon = await (database.select(database.pokemon)
          ..where((t) => t.apiId.equals(pokemonApiId)))
          .getSingleOrNull();
        
        if (pokemon != null) {
          await _assignPokedexToPokemon(
            speciesData: speciesData,
            variantInfo: variantInfo,
            isDefault: true,
            regionId: null,
          );
        }
      } catch (e) {
        Logger.error('Error al descargar pokemon default, reintentando...', context: LogContext.pokemon, error: e);
        await Future.delayed(const Duration(seconds: 2));
        await _downloadPokemonComplete(pokemonUrl);
      }
    }
    
    // Descargar variantes regionales
    for (final variant in regionalVariants) {
      final pokemon = variant['pokemon'] as Map<String, dynamic>?;
      final regionId = variant['regionId'] as int?;
      if (pokemon == null || regionId == null) continue;
      
      final pokemonUrl = pokemon['url'] as String;
      try {
        await _downloadPokemonComplete(pokemonUrl);
        
        // Obtener pokemon de la DB para asignar pokedex
        final pokemonApiId = _extractApiIdFromUrl(pokemonUrl);
        final pokemonData = await (database.select(database.pokemon)
          ..where((t) => t.apiId.equals(pokemonApiId)))
          .getSingleOrNull();
        
        if (pokemonData != null) {
          await _assignPokedexToPokemon(
            speciesData: speciesData,
            variantInfo: variantInfo,
            isDefault: false,
            regionId: regionId,
          );
          
          // Guardar relación de variante con pokemon default
          if (defaultPokemon != null) {
            final defaultPokemonApiId = _extractApiIdFromUrl(defaultPokemon['url'] as String);
            final defaultPokemonData = await (database.select(database.pokemon)
              ..where((t) => t.apiId.equals(defaultPokemonApiId)))
              .getSingleOrNull();
            
            if (defaultPokemonData != null) {
              await database.pokemonVariantsDao.insertVariant(
                pokemonId: defaultPokemonData.id,
                variantPokemonId: pokemonData.id,
              );
            }
          }
        }
      } catch (e) {
        Logger.error('Error al descargar variante regional, reintentando...', context: LogContext.pokemon, error: e);
        await Future.delayed(const Duration(seconds: 2));
        await _downloadPokemonComplete(pokemonUrl);
      }
    }
    
    // Descargar variantes especiales (gmax, mega, primal)
    for (final pokemon in specialVariants) {
      final pokemonUrl = pokemon['url'] as String;
      try {
        await _downloadPokemonComplete(pokemonUrl);
        
        // Guardar relación de variante con pokemon default (sin asignar pokedex)
        if (defaultPokemon != null) {
          final pokemonApiId = _extractApiIdFromUrl(pokemonUrl);
          final pokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(pokemonApiId)))
            .getSingleOrNull();
          
          final defaultPokemonApiId = _extractApiIdFromUrl(defaultPokemon['url'] as String);
          final defaultPokemonData = await (database.select(database.pokemon)
            ..where((t) => t.apiId.equals(defaultPokemonApiId)))
            .getSingleOrNull();
          
          if (pokemonData != null && defaultPokemonData != null) {
            await database.pokemonVariantsDao.insertVariant(
              pokemonId: defaultPokemonData.id,
              variantPokemonId: pokemonData.id,
            );
          }
        }
      } catch (e) {
        Logger.error('Error al descargar variante especial, reintentando...', context: LogContext.pokemon, error: e);
        await Future.delayed(const Duration(seconds: 2));
        await _downloadPokemonComplete(pokemonUrl);
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
      generaJson: Value(_jsonEncode(data['genera'])),
    );
    
    await database.into(database.pokemonSpecies).insert(
      companion,
      mode: InsertMode.replace,
    );
  }
  
  /// Descargar evolution chain
  Future<void> _downloadEvolutionChain(String chainUrl) async {
    // Descargar datos desde la API con reintento
    Map<String, dynamic> chainData;
    try {
      chainData = await apiClient.getResourceByUrl(chainUrl);
    } catch (e) {
      Logger.error('Error al descargar evolution chain, reintentando...', context: LogContext.pokemon, error: e);
      await Future.delayed(const Duration(seconds: 2));
      chainData = await apiClient.getResourceByUrl(chainUrl);
    }
    
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
    // Descargar datos desde la API con reintento
    Map<String, dynamic> pokemonData;
    try {
      pokemonData = await apiClient.getResourceByUrl(pokemonUrl);
    } catch (e) {
      Logger.error('Error al descargar pokemon, reintentando...', context: LogContext.pokemon, error: e);
      await Future.delayed(const Duration(seconds: 2));
      pokemonData = await apiClient.getResourceByUrl(pokemonUrl);
    }
    
    final pokemonName = pokemonData['name'] as String? ?? 'Pokemon';
    Logger.pokemon('Descargando pokemon', pokemonName: pokemonName);
    
    // Guardar pokemon con URLs de multimedia en transacción
    await database.transaction(() async {
      await _savePokemonWithMedia(pokemonData);
    });
    
    // Descargar multimedia (sprites, cries, artwork) - esto actualiza la DB después
    await _downloadPokemonMedia(pokemonData);
  }
  
  /// Seleccionar el PNG de mayor resolución de una lista de URLs
  /// Prioriza: official-artwork > home > otros
  String _selectHighestResolutionPng(List<String> urls) {
    if (urls.isEmpty) throw ArgumentError('Lista de URLs vacía');
    if (urls.length == 1) return urls.first;
    
    // Prioridad por fuente
    String? officialArtwork;
    String? home;
    String? other;
    
    for (final url in urls) {
      final lowerUrl = url.toLowerCase();
      if (lowerUrl.contains('official-artwork')) {
        officialArtwork = url;
      } else if (lowerUrl.contains('home')) {
        home = url;
      } else {
        other = url;
      }
    }
    
    // Retornar según prioridad
    if (officialArtwork != null) return officialArtwork;
    if (home != null) return home;
    if (other != null) return other;
    
    // Si no hay ninguna categorizada, retornar la primera
    return urls.first;
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
          Logger.error('Error al extraer speciesId de URL', context: LogContext.pokemon, error: e);
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
    // Para normal: SVG de dream-world, o si no hay, PNG de official-artwork/front_default
    // Para shiny: siempre PNG de official-artwork/front_shiny
    String? artworkOfficialUrl;
    String? artworkOfficialShinyUrl;
    if (sprites != null) {
      final other = sprites['other'] as Map<String, dynamic>?;
      if (other != null) {
        // Buscar SVG para imagen normal (prioridad: dream-world)
        final dreamWorld = other['dream-world'] as Map<String, dynamic>?;
        if (dreamWorld != null) {
          final frontDefault = dreamWorld['front_default'] as String?;
          if (frontDefault != null && frontDefault.toLowerCase().endsWith('.svg')) {
            artworkOfficialUrl = frontDefault;
          }
        }
        
        // Si no hay dream-world SVG, usar PNG de official-artwork/front_default
        if (artworkOfficialUrl == null) {
          final officialArtwork = other['official-artwork'] as Map<String, dynamic>?;
          if (officialArtwork != null) {
            final frontDefault = officialArtwork['front_default'] as String?;
            if (frontDefault != null) {
              artworkOfficialUrl = frontDefault;
            }
          }
        }
        
        // Para shiny: siempre usar official-artwork/front_shiny
        final officialArtwork = other['official-artwork'] as Map<String, dynamic>?;
        if (officialArtwork != null) {
          final frontShiny = officialArtwork['front_shiny'] as String?;
          if (frontShiny != null) {
            artworkOfficialShinyUrl = frontShiny;
          }
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
    
    // Guardar relaciones de tipos
    await _savePokemonTypes(data);
  }
  
  /// Guardar relaciones de tipos del pokemon
  Future<void> _savePokemonTypes(Map<String, dynamic> data) async {
    final types = data['types'] as List?;
    if (types == null || types.isEmpty) return;
    
    // Obtener el pokemon de la DB para obtener su ID real
    final apiId = data['id'] as int;
    final pokemon = await (database.select(database.pokemon)
      ..where((t) => t.apiId.equals(apiId)))
      .getSingleOrNull();
    
    if (pokemon == null) return;
    
    // Eliminar tipos existentes de este pokemon
    await (database.delete(database.pokemonTypes)
      ..where((t) => t.pokemonId.equals(pokemon.id)))
      .go();
    
    // Guardar nuevos tipos
    for (final typeEntry in types) {
      final typeData = typeEntry as Map<String, dynamic>;
      final typeInfo = typeData['type'] as Map<String, dynamic>?;
      final slot = typeData['slot'] as int?;
      
      if (typeInfo != null && slot != null) {
        final typeUrl = typeInfo['url'] as String?;
        if (typeUrl != null && typeUrl.isNotEmpty) {
          final typeApiId = _extractApiIdFromUrl(typeUrl);
          // Buscar el tipo en la DB
          final type = await (database.select(database.types)
            ..where((t) => t.apiId.equals(typeApiId)))
            .getSingleOrNull();
          
          if (type != null) {
            await database.into(database.pokemonTypes).insert(
              PokemonTypesCompanion.insert(
                pokemonId: pokemon.id,
                typeId: type.id,
                slot: slot,
              ),
              mode: InsertMode.replace,
            );
          }
        }
      }
    }
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
        final extension = pokemon.spriteFrontDefaultUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.spriteFrontDefaultUrl!,
          'pokemon/$apiId/sprite_front_default$extension',
        );
        updates['spriteFrontDefaultPath'] = path;
      } catch (e) {
        // Error silencioso - multimedia puede fallar sin afectar funcionalidad
      }
    }
    
    if (pokemon.spriteFrontShinyUrl != null) {
      try {
        final extension = pokemon.spriteFrontShinyUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.spriteFrontShinyUrl!,
          'pokemon/$apiId/sprite_front_shiny$extension',
        );
        updates['spriteFrontShinyPath'] = path;
      } catch (e) {
        // Error silencioso
      }
    }
    
    if (pokemon.spriteBackDefaultUrl != null) {
      try {
        final extension = pokemon.spriteBackDefaultUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.spriteBackDefaultUrl!,
          'pokemon/$apiId/sprite_back_default$extension',
        );
        updates['spriteBackDefaultPath'] = path;
      } catch (e) {
        // Error silencioso
      }
    }
    
    if (pokemon.spriteBackShinyUrl != null) {
      try {
        final extension = pokemon.spriteBackShinyUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.spriteBackShinyUrl!,
          'pokemon/$apiId/sprite_back_shiny$extension',
        );
        updates['spriteBackShinyPath'] = path;
      } catch (e) {
        // Error silencioso
      }
    }
    
    // Artwork oficial
    if (pokemon.artworkOfficialUrl != null) {
      try {
        final extension = pokemon.artworkOfficialUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.artworkOfficialUrl!,
          'pokemon/$apiId/artwork_official$extension',
        );
        updates['artworkOfficialPath'] = path;
      } catch (e) {
        // Error silencioso
      }
    }
    
    if (pokemon.artworkOfficialShinyUrl != null) {
      try {
        final extension = pokemon.artworkOfficialShinyUrl!.toLowerCase().endsWith('.svg') ? '.svg' : '.png';
        final path = await _downloadMediaFile(
          pokemon.artworkOfficialShinyUrl!,
          'pokemon/$apiId/artwork_official_shiny$extension',
        );
        updates['artworkOfficialShinyPath'] = path;
      } catch (e) {
        // Error silencioso
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
        // Error silencioso
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
        // Error silencioso
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
      // Error silencioso - multimedia puede fallar sin afectar funcionalidad
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
  
  /// Asegurar que existe la región Nacional y su pokedex
  /// La región Nacional es especial: no tiene apiId de la API, se crea manualmente
  Future<void> _ensureNationalRegionExists() async {
    final regionDao = RegionDao(database);
    final pokedexDao = PokedexDao(database);
    
    // Verificar si existe la región Nacional
    var nationalRegion = await regionDao.getRegionByName('Nacional');
    
    if (nationalRegion == null) {
      // Crear región Nacional (apiId especial: 9999)
      final regionCompanion = RegionsCompanion.insert(
        apiId: 9999, // ID especial para región Nacional
        name: 'Nacional',
        mainGenerationId: const Value.absent(),
        locationsJson: const Value.absent(),
        pokedexesJson: const Value.absent(),
        versionGroupsJson: const Value.absent(),
      );
      
      final regionId = await database.into(database.regions).insert(regionCompanion);
      nationalRegion = await regionDao.getRegionById(regionId);
      Logger.region('Región Nacional creada', regionName: 'Nacional');
    }
    
    if (nationalRegion == null) return;
    
    // Verificar si existe la pokedex Nacional (name == "national")
    final nationalPokedex = await (database.select(database.pokedex)
      ..where((t) => t.name.equals('national')))
      .getSingleOrNull();
    
    if (nationalPokedex == null) {
      // Descargar datos de la pokedex nacional desde la API
      try {
        final pokedexData = await apiClient.getResourceByUrl(
          '${ApiClient.baseUrl}/pokedex/1', // La pokedex nacional tiene ID 1
        );
        
        final apiId = pokedexData['id'] as int;
        final name = pokedexData['name'] as String;
        final isMainSeries = pokedexData['is_main_series'] as bool? ?? false;
        
        // Generar color para la pokedex nacional
        final color = ColorGenerator.generatePastelColor(0);
        
        final pokedexCompanion = PokedexCompanion.insert(
          apiId: apiId,
          name: name,
          isMainSeries: Value(isMainSeries),
          regionId: Value(nationalRegion.id),
          color: Value(color),
          descriptionsJson: Value(_jsonEncode(pokedexData['descriptions'])),
          pokemonEntriesJson: Value(_jsonEncode(pokedexData['pokemon_entries'])),
        );
        
        await database.into(database.pokedex).insert(
          pokedexCompanion,
          mode: InsertMode.replace,
        );
        
        Logger.pokedex('Pokedex Nacional creada', pokedexName: 'national');
      } catch (e) {
        Logger.error('Error al crear pokedex Nacional', context: LogContext.pokedex, error: e);
      }
    }
  }
  
  /// Extraer región del nombre de un pokemon
  /// Busca nombres de regiones en el nombre del pokemon (case-insensitive)
  /// Retorna la región encontrada o null
  Future<int?> _extractRegionFromPokemonName(String pokemonName) async {
    final regionDao = RegionDao(database);
    final allRegions = await regionDao.getAllRegions();
    
    // Buscar nombres de región en el nombre del pokemon
    final pokemonNameLower = pokemonName.toLowerCase();
    
    for (final region in allRegions) {
      final regionNameLower = region.name.toLowerCase();
      
      // Buscar coincidencias exactas o con guión (ej: "ponyta-galar" contiene "galar")
      if (pokemonNameLower.contains(regionNameLower)) {
        return region.id;
      }
    }
    
    return null;
  }
  
  /// Verificar si un pokemon es una variante especial (gmax, mega, primal)
  bool _isSpecialVariant(String pokemonName) {
    final nameLower = pokemonName.toLowerCase();
    return nameLower.contains('gmax') || 
           nameLower.contains('mega') || 
           nameLower.contains('primal');
  }
  
  /// Procesar variantes de una pokemon-species y clasificarlas
  /// Retorna un mapa con:
  /// - 'default': pokemon default (si existe)
  /// - 'regional': lista de variantes regionales con su región
  /// - 'special': lista de variantes especiales (gmax, mega, primal)
  Future<Map<String, dynamic>> _processPokemonVariants(
    Map<String, dynamic> speciesData,
  ) async {
    final varieties = speciesData['varieties'] as List? ?? [];
    final pokedexNumbers = speciesData['pokedex_numbers'] as List? ?? [];
    
    // Obtener todas las pokedex donde aparece esta especie
    final speciesPokedexNames = <String>{};
    for (final entry in pokedexNumbers) {
      final pokedex = entry['pokedex'] as Map<String, dynamic>?;
      if (pokedex != null) {
        final pokedexName = pokedex['name'] as String?;
        if (pokedexName != null) {
          speciesPokedexNames.add(pokedexName);
        }
      }
    }
    
    // Identificar pokemon default
    Map<String, dynamic>? defaultPokemon;
    final List<Map<String, dynamic>> regionalVariants = [];
    final List<Map<String, dynamic>> specialVariants = [];
    
    for (final variety in varieties) {
      final isDefault = variety['is_default'] as bool? ?? false;
      final pokemon = variety['pokemon'] as Map<String, dynamic>?;
      if (pokemon == null) continue;
      
      final pokemonName = pokemon['name'] as String;
      
      if (isDefault) {
        defaultPokemon = pokemon;
      } else {
        // Verificar si es variante especial
        if (_isSpecialVariant(pokemonName)) {
          specialVariants.add(pokemon);
        } else {
          // Verificar si es variante regional
          final regionId = await _extractRegionFromPokemonName(pokemonName);
          if (regionId != null) {
            regionalVariants.add({
              'pokemon': pokemon,
              'regionId': regionId,
            });
          } else {
            // Si no es regional ni especial, tratarlo como variante especial
            specialVariants.add(pokemon);
          }
        }
      }
    }
    
    return {
      'default': defaultPokemon,
      'regional': regionalVariants,
      'special': specialVariants,
      'speciesPokedexNames': speciesPokedexNames,
    };
  }
  
  /// Obtener entry_number de la pokedex nacional para una especie
  int? _getNationalEntryNumber(Map<String, dynamic> speciesData) {
    final pokedexNumbers = speciesData['pokedex_numbers'] as List? ?? [];
    for (final entry in pokedexNumbers) {
      final pokedex = entry['pokedex'] as Map<String, dynamic>?;
      if (pokedex != null && pokedex['name'] == 'national') {
        return _safeIntFromDynamic(entry['entry_number']);
      }
    }
    return null;
  }
  
  /// Asignar pokedex a un pokemon-species según las reglas
  /// - Pokemon default: todas las pokedex de la especie (excepto las de variantes regionales) + nacional
  /// - Variantes regionales: solo pokedex de esa región + nacional
  /// - Variantes especiales: sin pokedex asignada
  /// Nota: Las entradas de pokedex se relacionan con pokemon-species, no con pokemon individuales
  Future<void> _assignPokedexToPokemon({
    required Map<String, dynamic> speciesData,
    required Map<String, dynamic> variantInfo,
    required bool isDefault,
    int? regionId, // Solo para variantes regionales
  }) async {
    final pokedexDao = PokedexDao(database);
    final pokedexNumbers = speciesData['pokedex_numbers'] as List? ?? [];
    
    // Obtener entry_number para la pokedex nacional
    int? nationalEntryNumber;
    for (final entry in pokedexNumbers) {
      final pokedex = entry['pokedex'] as Map<String, dynamic>?;
      if (pokedex != null && pokedex['name'] == 'national') {
        nationalEntryNumber = entry['entry_number'] as int?;
        break;
      }
    }
    
    // Obtener pokemon-species de la DB
    final speciesApiId = speciesData['id'] as int;
    final species = await (database.select(database.pokemonSpecies)
      ..where((t) => t.apiId.equals(speciesApiId)))
      .getSingleOrNull();
    
    if (species == null) return;
    
    // Lista de pokedex a asignar
    final List<Map<String, int>> pokedexToAssign = [];
    
    if (isDefault) {
      // Pokemon default: todas las pokedex donde aparece la especie (excepto las de variantes regionales)
      final speciesPokedexNames = variantInfo['speciesPokedexNames'] as Set<String>? ?? {};
      final regionalVariants = variantInfo['regional'] as List? ?? [];
      
      // Obtener nombres de pokedex de variantes regionales para excluirlas
      final regionalPokedexNames = <String>{};
      for (final variant in regionalVariants) {
        final variantRegionId = variant['regionId'] as int?;
        if (variantRegionId != null) {
          final regionPokedexes = await pokedexDao.getPokedexByRegion(variantRegionId);
          for (final pokedex in regionPokedexes) {
            regionalPokedexNames.add(pokedex.name);
          }
        }
      }
      
      // Asignar a todas las pokedex de la especie excepto las regionales
      for (final entry in pokedexNumbers) {
        final pokedex = entry['pokedex'] as Map<String, dynamic>?;
        if (pokedex == null) continue;
        
        final pokedexName = pokedex['name'] as String;
        final entryNumber = entry['entry_number'] as int?;
        
        // Excluir pokedex de variantes regionales
        if (!regionalPokedexNames.contains(pokedexName) && pokedexName != 'national') {
          final pokedexData = await pokedexDao.getPokedexByApiId(
            _extractApiIdFromUrl(pokedex['url'] as String? ?? ''),
          );
          if (pokedexData != null && entryNumber != null) {
            pokedexToAssign.add({
              'pokedexId': pokedexData.id,
              'entryNumber': entryNumber,
            });
          }
        }
      }
      
      // Añadir pokedex nacional
      if (nationalEntryNumber != null) {
        final nationalPokedex = await (database.select(database.pokedex)
          ..where((t) => t.name.equals('national')))
          .getSingleOrNull();
        if (nationalPokedex != null) {
          pokedexToAssign.add({
            'pokedexId': nationalPokedex.id,
            'entryNumber': nationalEntryNumber,
          });
        }
      }
    } else if (regionId != null) {
      // Variante regional: solo pokedex de esa región + nacional
      final regionPokedexes = await pokedexDao.getPokedexByRegion(regionId);
      
      // Obtener entry_number para las pokedex de la región
      for (final entry in pokedexNumbers) {
        final pokedex = entry['pokedex'] as Map<String, dynamic>?;
        if (pokedex == null) continue;
        
        final pokedexName = pokedex['name'] as String;
        final entryNumber = entry['entry_number'] as int?;
        
        // Buscar si esta pokedex pertenece a la región
        for (final regionPokedex in regionPokedexes) {
          if (regionPokedex.name == pokedexName && entryNumber != null) {
            pokedexToAssign.add({
              'pokedexId': regionPokedex.id,
              'entryNumber': entryNumber,
            });
            break;
          }
        }
      }
      
      // Añadir pokedex nacional
      if (nationalEntryNumber != null) {
        final nationalPokedex = await (database.select(database.pokedex)
          ..where((t) => t.name.equals('national')))
          .getSingleOrNull();
        if (nationalPokedex != null) {
          pokedexToAssign.add({
            'pokedexId': nationalPokedex.id,
            'entryNumber': nationalEntryNumber,
          });
        }
      }
    }
    // Variantes especiales: no se asignan pokedex
    
    // Guardar entradas de pokedex
    for (final entry in pokedexToAssign) {
      final companion = PokedexEntriesCompanion.insert(
        pokedexId: entry['pokedexId']!,
        pokemonSpeciesId: species.id,
        entryNumber: entry['entryNumber']!,
      );
      
      await database.into(database.pokedexEntries).insert(
        companion,
        mode: InsertMode.replace,
      );
    }
  }
  
  void dispose() {
    apiClient.dispose();
  }
}


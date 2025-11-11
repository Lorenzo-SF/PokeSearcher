import 'dart:async';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'download_phases.dart';

/// Estado de progreso de descarga
class DownloadProgress {
  final DownloadPhase phase;
  final String currentEntity;
  final int completed;
  final int total;
  final int? totalSizeBytes; // Tamaño total estimado en bytes
  final String? error;
  
  DownloadProgress({
    required this.phase,
    required this.currentEntity,
    required this.completed,
    required this.total,
    this.totalSizeBytes,
    this.error,
  });
  
  double get percentage => total > 0 ? completed / total : 0.0;
  
  bool get isComplete => completed >= total && error == null;
  
  /// Formatear tamaño en formato legible (KB, MB)
  String get formattedSize {
    if (totalSizeBytes == null) return '';
    if (totalSizeBytes! < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes! < 1024 * 1024) {
      return '${(totalSizeBytes! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes! / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Callback para actualizar progreso
typedef ProgressCallback = void Function(DownloadProgress progress);

/// Gestor de colas y estado de descarga
class DownloadManager {
  final AppDatabase database;
  final ProgressCallback? onProgress;
  
  DownloadManager({
    required this.database,
    this.onProgress,
  });
  
  /// Registrar inicio de descarga
  Future<void> markDownloadStarted({
    required DownloadPhase phase,
    required String entityType,
    int? entityId,
  }) async {
    await database.into(database.downloadSync).insert(
      DownloadSyncCompanion.insert(
        phase: phase.name,
        entityType: entityType,
        entityId: Value(entityId),
        downloadedAt: DateTime.now(),
        completed: const Value(false),
      ),
      mode: InsertMode.replace,
    );
  }
  
  /// Marcar descarga como completada
  Future<void> markDownloadCompleted({
    required DownloadPhase phase,
    required String entityType,
    int? entityId,
  }) async {
    final query = database.select(database.downloadSync)
      ..where((tbl) => 
        tbl.phase.equals(phase.name) &
        tbl.entityType.equals(entityType) &
        (entityId != null 
          ? tbl.entityId.equals(entityId) 
          : const Constant(true)));
    
    final existing = await query.getSingleOrNull();
    
    if (existing != null) {
      await (database.update(database.downloadSync)
        ..where((tbl) => tbl.id.equals(existing.id)))
        .write(DownloadSyncCompanion(
          completed: const Value(true),
          errorMessage: const Value.absent(),
        ));
    } else {
      await database.into(database.downloadSync).insert(
        DownloadSyncCompanion.insert(
          phase: phase.name,
          entityType: entityType,
          entityId: Value(entityId),
          downloadedAt: DateTime.now(),
          completed: const Value(true),
        ),
        mode: InsertMode.replace,
      );
    }
  }
  
  /// Marcar descarga con error
  Future<void> markDownloadError({
    required DownloadPhase phase,
    required String entityType,
    int? entityId,
    required String error,
  }) async {
    final query = database.select(database.downloadSync)
      ..where((tbl) => 
        tbl.phase.equals(phase.name) &
        tbl.entityType.equals(entityType) &
        (entityId != null 
          ? tbl.entityId.equals(entityId) 
          : const Constant(true)));
    
    final existing = await query.getSingleOrNull();
    
    if (existing != null) {
      await (database.update(database.downloadSync)
        ..where((tbl) => tbl.id.equals(existing.id)))
        .write(DownloadSyncCompanion(
          completed: const Value(false),
          errorMessage: Value(error),
        ));
    } else {
      await database.into(database.downloadSync).insert(
        DownloadSyncCompanion.insert(
          phase: phase.name,
          entityType: entityType,
          entityId: Value(entityId),
          downloadedAt: DateTime.now(),
          completed: const Value(false),
          errorMessage: Value(error),
        ),
        mode: InsertMode.replace,
      );
    }
  }
  
  /// Verificar si una entidad ya fue descargada
  Future<bool> isDownloaded({
    required DownloadPhase phase,
    required String entityType,
    int? entityId,
  }) async {
    final query = database.select(database.downloadSync)
      ..where((tbl) => 
        tbl.phase.equals(phase.name) &
        tbl.entityType.equals(entityType) &
        tbl.completed.equals(true) &
        (entityId != null 
          ? tbl.entityId.equals(entityId) 
          : const Constant(true)));
    
    final result = await query.getSingleOrNull();
    return result != null;
  }
  
  /// Obtener todas las descargas de una fase
  Future<List<DownloadSyncData>> getPhaseDownloads(DownloadPhase phase) async {
    final query = database.select(database.downloadSync)
      ..where((tbl) => tbl.phase.equals(phase.name));
    
    return await query.get();
  }
  
  /// Notificar progreso
  void notifyProgress(DownloadProgress progress) {
    onProgress?.call(progress);
  }
}


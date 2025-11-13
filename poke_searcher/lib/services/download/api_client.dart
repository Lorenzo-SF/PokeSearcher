import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../utils/logger.dart';

/// Cliente HTTP para interactuar con PokeAPI
class ApiClient {
  static const String baseUrl = 'https://pokeapi.co/api/v2';
  
  final http.Client _client;
  DateTime? _lastRequestTime;
  static const Duration _minRequestInterval = Duration(milliseconds: 300); // Rate limiting: ~3 requests/segundo (más conservador)
  
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  
  /// Esperar si es necesario para respetar el rate limiting
  Future<void> _waitForRateLimit() async {
    if (_lastRequestTime != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastRequestTime!);
      if (timeSinceLastRequest < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - timeSinceLastRequest);
      }
    }
    _lastRequestTime = DateTime.now();
  }
  
  /// Realizar petición con retry automático en caso de "too many requests"
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 5,
  }) async {
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      await _waitForRateLimit();
      
      try {
        final response = await request();
        
        // Si es "too many requests" (429), esperar y reintentar
        if (response.statusCode == 429) {
          retryCount++;
          if (retryCount >= maxRetries) {
            throw ApiException(
              'Too many requests. Por favor espera unos momentos antes de reintentar.',
              response.statusCode,
            );
          }
          
          // Backoff exponencial más agresivo: esperar más tiempo en cada reintento
          // 5s, 10s, 20s, 30s, 40s
          final waitTime = Duration(seconds: (retryCount * 5).clamp(5, 40));
          Logger.api('Rate limit alcanzado. Esperando ${waitTime.inSeconds}s antes de reintentar... (intento $retryCount/$maxRetries)');
          await Future.delayed(waitTime);
          continue;
        }
        
        return response;
      } catch (e) {
        if (e is ApiException && e.statusCode == 429) {
          // Ya manejado arriba
          continue;
        }
        if (retryCount >= maxRetries - 1) {
          rethrow;
        }
        retryCount++;
        final waitTime = Duration(seconds: (retryCount * 3).clamp(3, 15));
        await Future.delayed(waitTime);
      }
    }
    
    throw ApiException('Error después de $maxRetries intentos', null);
  }
  
  /// Obtener lista de recursos de un endpoint
  /// Retorna un mapa con 'count' y 'results' (lista de {name, url})
  Future<Map<String, dynamic>> getResourceList({
    required String endpoint,
    int? limit,
    int? offset,
  }) async {
    final uri = Uri.parse('$baseUrl/$endpoint')
        .replace(queryParameters: {
      if (limit != null) 'limit': limit.toString(),
      if (offset != null) 'offset': offset.toString(),
    });
    
    final response = await _requestWithRetry(() => _client.get(uri));
    
    if (response.statusCode != 200) {
      throw ApiException(
        'Error al obtener lista de $endpoint: ${response.statusCode}',
        response.statusCode,
      );
    }
    
    return json.decode(response.body) as Map<String, dynamic>;
  }
  
  /// Obtener un recurso específico por ID o nombre
  Future<Map<String, dynamic>> getResource({
    required String endpoint,
    required String identifier, // Puede ser ID o nombre
  }) async {
    final uri = Uri.parse('$baseUrl/$endpoint/$identifier');
    
    final response = await _requestWithRetry(() => _client.get(uri));
    
    if (response.statusCode != 200) {
      throw ApiException(
        'Error al obtener $endpoint/$identifier: ${response.statusCode}',
        response.statusCode,
      );
    }
    
    return json.decode(response.body) as Map<String, dynamic>;
  }
  
  /// Obtener un recurso por URL completa
  Future<Map<String, dynamic>> getResourceByUrl(String url) async {
    final uri = Uri.parse(url);
    
    final response = await _requestWithRetry(() => _client.get(uri));
    
    if (response.statusCode != 200) {
      throw ApiException(
        'Error al obtener recurso desde URL: ${response.statusCode}',
        response.statusCode,
      );
    }
    
    return json.decode(response.body) as Map<String, dynamic>;
  }
  
  /// Descargar archivo binario (imagen, audio, etc.)
  Future<List<int>> downloadFile(String url) async {
    final uri = Uri.parse(url);
    
    final response = await _requestWithRetry(() => _client.get(uri));
    
    if (response.statusCode != 200) {
      throw ApiException(
        'Error al descargar archivo: ${response.statusCode}',
        response.statusCode,
      );
    }
    
    return response.bodyBytes;
  }
  
  /// Verificar si una URL es un archivo multimedia
  static bool isMediaUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg') ||
        path.endsWith('.ogg') ||
        path.endsWith('.mp3') ||
        path.endsWith('.wav') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp');
  }
  
  void dispose() {
    _client.close();
  }
}

/// Excepción personalizada para errores de API
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  
  ApiException(this.message, [this.statusCode]);
  
  @override
  String toString() => 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}


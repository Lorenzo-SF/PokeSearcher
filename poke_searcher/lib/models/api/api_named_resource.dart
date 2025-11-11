/// Recurso con nombre y URL (formato estándar de PokeAPI)
class ApiNamedResource {
  final String name;
  final String url;
  
  ApiNamedResource({
    required this.name,
    required this.url,
  });
  
  factory ApiNamedResource.fromJson(Map<String, dynamic> json) {
    return ApiNamedResource(
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
    };
  }
  
  /// Extraer ID de la URL
  int? get idFromUrl {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        final id = int.tryParse(lastSegment);
        return id;
      }
    } catch (e) {
      // Ignorar errores de parsing
    }
    return null;
  }
}


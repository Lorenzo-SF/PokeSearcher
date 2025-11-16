import 'dart:ui';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/type_dao.dart';
import '../utils/color_generator.dart';
import '../utils/type_image_helper.dart';
import 'type_detail_screen.dart';

class TypesListScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;

  const TypesListScreen({
    super.key,
    required this.database,
    required this.appConfig,
  });

  @override
  State<TypesListScreen> createState() => _TypesListScreenState();
}

class _TypesListScreenState extends State<TypesListScreen> {
  List<Type> _types = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final typeDao = TypeDao(widget.database);
      final types = await typeDao.getAllTypes();
      
      // Filtrar tipos unknown, stellar y shadow
      final filteredTypes = types.where((type) {
        final nameLower = type.name.toLowerCase();
        return nameLower != 'unknown' && 
               nameLower != 'stellar' && 
               nameLower != 'shadow';
      }).toList();
      
      // Ordenar por nombre
      filteredTypes.sort((a, b) => a.name.compareTo(b.name));
      
      setState(() {
        _types = filteredTypes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar tipos: $e'),
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
          // Fondo con blur
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade900,
                  Colors.purple.shade900,
                ],
              ),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                ),
              ),
            ),
          ),
          // Contenido
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 56,
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _types.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 64,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No hay tipos disponibles',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Calcular número de columnas según el ancho disponible
                          // Cada imagen tiene 200px de ancho + 16px de padding lateral
                          final itemWidth = 200.0 + 32.0; // ancho + padding
                          final crossAxisCount = (constraints.maxWidth / itemWidth).floor().clamp(1, 10);
                          
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 200 / 40, // Ancho: 200, Alto: 40
                            ),
                            itemCount: _types.length,
                            itemBuilder: (context, index) {
                              final type = _types[index];
                              return _buildTypeImage(type);
                            },
                          );
                        },
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
                    color: Colors.black.withOpacity(0.3),
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

  Widget _buildTypeImage(Type type) {
    return FutureBuilder<String?>(
      future: TypeImageHelper.getTypeImagePathFromConfig(
        typeApiId: type.apiId,
        typeName: type.name,
        appConfig: widget.appConfig,
        database: widget.database,
      ),
      builder: (context, snapshot) {
        final imagePath = snapshot.data ?? 'assets/types/${type.name.toLowerCase()}.png';
        
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TypeDetailScreen(
                  database: widget.database,
                  appConfig: widget.appConfig,
                  typeId: type.id,
                ),
              ),
            );
          },
          child: Container(
            width: 200,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                imagePath,
                width: 200,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback: mostrar color de fondo con nombre
                  final colorHex = type.color;
                  final color = colorHex != null 
                      ? Color(ColorGenerator.hexToColor(colorHex))
                      : Colors.grey;
                  
                  return Container(
                    width: 200,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        type.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}


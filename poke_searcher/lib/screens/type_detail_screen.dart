import 'dart:ui';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/type_dao.dart';
import '../utils/color_generator.dart';

class TypeDetailScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;
  final int typeId;

  const TypeDetailScreen({
    super.key,
    required this.database,
    required this.appConfig,
    required this.typeId,
  });

  @override
  State<TypeDetailScreen> createState() => _TypeDetailScreenState();
}

class _TypeDetailScreenState extends State<TypeDetailScreen> {
  Type? _type;
  List<Type> _doubleDamageTo = [];
  List<Type> _halfDamageTo = [];
  List<Type> _noDamageTo = [];
  List<Type> _doubleDamageFrom = [];
  List<Type> _halfDamageFrom = [];
  List<Type> _noDamageFrom = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTypeData();
  }

  Future<void> _loadTypeData() async {
    try {
      final typeDao = TypeDao(widget.database);
      
      // Obtener tipo
      _type = await typeDao.getTypeById(widget.typeId);
      if (_type == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      // Obtener relaciones de efectividad
      _doubleDamageTo = await typeDao.getDoubleDamageTo(widget.typeId);
      _halfDamageTo = await typeDao.getHalfDamageTo(widget.typeId);
      _noDamageTo = await typeDao.getNoDamageTo(widget.typeId);
      _doubleDamageFrom = await typeDao.getDoubleDamageFrom(widget.typeId);
      _halfDamageFrom = await typeDao.getHalfDamageFrom(widget.typeId);
      _noDamageFrom = await typeDao.getNoDamageFrom(widget.typeId);
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar tipo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Stack(
          children: [
            _buildBackground(),
            const Center(child: CircularProgressIndicator()),
            _buildBackButton(),
          ],
        ),
      );
    }

    if (_type == null) {
      return Scaffold(
        body: Stack(
          children: [
            _buildBackground(),
            const Center(
              child: Text('No se pudo cargar la información del tipo'),
            ),
            _buildBackButton(),
          ],
        ),
      );
    }

    final colorHex = _type!.color;
    final typeColor = colorHex != null 
        ? Color(ColorGenerator.hexToColor(colorHex))
        : Colors.grey;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
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
                // Cápsula del tipo (arriba)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      _type!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Super efectivo contra
                if (_doubleDamageTo.isNotEmpty) ...[
                  _buildSection(
                    title: 'Super efectivo contra',
                    types: _doubleDamageTo,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 24),
                ],
                
                // No muy efectivo contra
                if (_halfDamageTo.isNotEmpty) ...[
                  _buildSection(
                    title: 'No muy efectivo contra',
                    types: _halfDamageTo,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Sin efecto contra
                if (_noDamageTo.isNotEmpty) ...[
                  _buildSection(
                    title: 'Sin efecto contra',
                    types: _noDamageTo,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Débil contra
                if (_doubleDamageFrom.isNotEmpty) ...[
                  _buildSection(
                    title: 'Débil contra',
                    types: _doubleDamageFrom,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Resistente a
                if (_halfDamageFrom.isNotEmpty) ...[
                  _buildSection(
                    title: 'Resistente a',
                    types: _halfDamageFrom,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Inmune a
                if (_noDamageFrom.isNotEmpty) ...[
                  _buildSection(
                    title: 'Inmune a',
                    types: _noDamageFrom,
                    color: Colors.purple,
                  ),
                ],
              ],
            ),
          ),
          _buildBackButton(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
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
    );
  }

  Widget _buildBackButton() {
    return Positioned(
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
    );
  }

  Widget _buildSection({
    required String title,
    required List<Type> types,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: types.map((type) {
            final colorHex = type.color;
            final typeColor = colorHex != null 
                ? Color(ColorGenerator.hexToColor(colorHex))
                : Colors.grey;
            
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                type.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}


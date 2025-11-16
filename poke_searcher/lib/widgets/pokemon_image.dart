import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/media_path_helper.dart';
import '../utils/logger.dart';

/// Widget que carga una imagen de pokemon desde archivos locales o assets.
/// 
/// Soporta múltiples formatos:
/// - SVG (usando flutter_svg)
/// - PNG, JPG, JPEG (usando Image.file)
/// 
/// Los archivos se cargan desde el directorio de datos de la app,
/// que contiene los archivos extraídos del ZIP de backup.
class PokemonImage extends StatelessWidget {
  /// Ruta del archivo de imagen (puede ser relativa o absoluta)
  final String? imagePath;
  
  /// Cómo ajustar la imagen dentro de sus límites
  final BoxFit fit;
  
  /// Ancho opcional de la imagen
  final double? width;
  
  /// Alto opcional de la imagen
  final double? height;
  
  /// Widget a mostrar en caso de error o si imagePath es null/vacío
  final Widget? errorWidget;

  const PokemonImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return errorWidget ?? const Icon(
        Icons.catching_pokemon,
        size: 32,
        color: Colors.white,
      );
    }
    
    // Convertir ruta de asset a ruta local
    return FutureBuilder<String?>(
      future: MediaPathHelper.assetPathToLocalPath(imagePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return errorWidget ?? const Icon(
            Icons.catching_pokemon,
            size: 32,
            color: Colors.white,
          );
        }
        
        final localPath = snapshot.data!;
        final isSvg = localPath.toLowerCase().endsWith('.svg');
        
        // Verificar que el archivo existe
        final file = File(localPath);
        if (!file.existsSync()) {
          Logger.error('Archivo de imagen no existe', context: LogContext.pokemon, error: localPath);
          return errorWidget ?? const Icon(
            Icons.catching_pokemon,
            size: 32,
            color: Colors.white,
          );
        }
        
        if (isSvg) {
          // Para SVG, usar SvgPicture.file
          try {
            return SvgPicture.file(
              file,
              fit: fit,
              width: width,
              height: height,
              placeholderBuilder: (context) {
                return errorWidget ?? const Icon(
                  Icons.catching_pokemon,
                  size: 32,
                  color: Colors.white,
                );
              },
            );
          } catch (e) {
            Logger.error(
              'Error cargando SVG: $localPath',
              context: LogContext.pokemon,
              error: e,
            );
            return errorWidget ?? const Icon(
              Icons.catching_pokemon,
              size: 32,
              color: Colors.white,
            );
          }
        } else {
          // Para PNG/JPG, usar Image.file
          try {
            return Image.file(
              file,
              fit: fit,
              width: width,
              height: height,
              errorBuilder: (context, error, stackTrace) {
                Logger.error(
                  'Error cargando imagen: $localPath',
                  context: LogContext.pokemon,
                  error: error,
                );
                return errorWidget ?? const Icon(
                  Icons.catching_pokemon,
                  size: 32,
                  color: Colors.white,
                );
              },
            );
          } catch (e) {
            Logger.error(
              'Excepción cargando imagen: $localPath',
              context: LogContext.pokemon,
              error: e,
            );
            return errorWidget ?? const Icon(
              Icons.catching_pokemon,
              size: 32,
              color: Colors.white,
            );
          }
        }
      },
    );
  }
}


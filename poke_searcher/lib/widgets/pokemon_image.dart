import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/media_path_helper.dart';

/// Widget que carga una imagen de pokemon desde archivos locales o assets
/// Soporta SVG y PNG/JPG desde archivos locales extraídos del ZIP
class PokemonImage extends StatelessWidget {
  final String? imagePath;
  final BoxFit fit;
  final double? width;
  final double? height;
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
      print('[PokemonImage] ⚠️ imagePath es null o vacío');
      return errorWidget ?? const Icon(
        Icons.catching_pokemon,
        size: 32,
        color: Colors.white,
      );
    }

    print('[PokemonImage] 🔍 Iniciando carga de imagen');
    print('[PokemonImage]   - imagePath original: $imagePath');
    
    // Convertir ruta de asset a ruta local
    return FutureBuilder<String?>(
      future: MediaPathHelper.assetPathToLocalPath(imagePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          print('[PokemonImage] ⚠️ No se pudo convertir ruta a local');
          return errorWidget ?? const Icon(
            Icons.catching_pokemon,
            size: 32,
            color: Colors.white,
          );
        }
        
        final localPath = snapshot.data!;
        final isSvg = localPath.toLowerCase().endsWith('.svg');
        print('[PokemonImage]   - Ruta local: $localPath');
        print('[PokemonImage]   - Es SVG: $isSvg');
        
        // Verificar que el archivo existe
        final file = File(localPath);
        if (!file.existsSync()) {
          print('[PokemonImage] ❌ Archivo no existe: $localPath');
          return errorWidget ?? const Icon(
            Icons.catching_pokemon,
            size: 32,
            color: Colors.white,
          );
        }
        
        if (isSvg) {
          // Para SVG, usar SvgPicture.file
          try {
            print('[PokemonImage] 📦 Intentando cargar SVG desde archivo: $localPath');
            return SvgPicture.file(
              file,
              fit: fit,
              width: width,
              height: height,
              placeholderBuilder: (context) {
                print('[PokemonImage] ⏳ Mostrando placeholder para SVG');
                return errorWidget ?? const Icon(
                  Icons.catching_pokemon,
                  size: 32,
                  color: Colors.white,
                );
              },
            );
          } catch (e, stackTrace) {
            print('[PokemonImage] ❌ Error cargando SVG: $localPath (original: $imagePath)');
            print('[PokemonImage] Error: $e');
            print('[PokemonImage] StackTrace: $stackTrace');
            return errorWidget ?? const Icon(
              Icons.catching_pokemon,
              size: 32,
              color: Colors.white,
            );
          }
        } else {
          // Para PNG/JPG, usar Image.file
          print('[PokemonImage] 📦 Intentando cargar imagen PNG/JPG desde archivo: $localPath');
          try {
            return Image.file(
              file,
              fit: fit,
              width: width,
              height: height,
              errorBuilder: (context, error, stackTrace) {
                print('[PokemonImage] ❌ Error cargando imagen: $localPath (original: $imagePath)');
                print('[PokemonImage] Error: $error');
                print('[PokemonImage] StackTrace: $stackTrace');
                return errorWidget ?? const Icon(
                  Icons.catching_pokemon,
                  size: 32,
                  color: Colors.white,
                );
              },
            );
          } catch (e, stackTrace) {
            print('[PokemonImage] ❌ Excepción cargando imagen: $localPath (original: $imagePath)');
            print('[PokemonImage] Error: $e');
            print('[PokemonImage] StackTrace: $stackTrace');
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


import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/color_generator.dart';
import '../database/app_database.dart';

/// Widget que muestra franjas de color rotadas 45° basadas en los tipos de pokemon
/// 
/// Divide el fondo en 6 columnas. Si el pokemon tiene 1 tipo, se pintan las 
/// columnas 5 y 6 con ese color. Si tiene 2 tipos, la columna 5 es el 1º tipo 
/// y la 6 el 2º tipo. Luego rota 45° a la izquierda sobre el centro.
class TypeStripeBackground extends StatelessWidget {
  final List<Type> types;
  final Widget child;
  final double? width;
  final double? height;

  const TypeStripeBackground({
    super.key,
    required this.types,
    required this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return child;
    }

    // Obtener colores de los tipos
    final colors = types.map((type) {
      final colorHex = type.color;
      if (colorHex == null || colorHex.isEmpty) {
        return Colors.grey;
      }
      return Color(ColorGenerator.hexToColor(colorHex));
    }).toList();

    // Si solo hay 1 tipo, usar ese color para ambas columnas
    // Si hay 2 tipos, usar cada uno para su columna
    final color1 = colors.isNotEmpty ? colors[0] : Colors.grey;
    final color2 = colors.length > 1 ? colors[1] : color1;

    return Stack(
      children: [
        // Fondo con franjas rotadas
        if (width != null && height != null)
          Positioned.fill(
            child: Transform.rotate(
              angle: -math.pi / 4, // -45 grados (rotación a la izquierda)
              alignment: Alignment.center, // Rotar desde el centro
              child: CustomPaint(
                size: Size(width!, height!),
                painter: _StripePainter(
                  color1: color1,
                  color2: color2,
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return Transform.rotate(
                angle: -math.pi / 4, // -45 grados (rotación a la izquierda)
                alignment: Alignment.center, // Rotar desde el centro
                child: CustomPaint(
                  size: constraints.biggest,
                  painter: _StripePainter(
                    color1: color1,
                    color2: color2,
                  ),
                ),
              );
            },
          ),
        // Contenido encima
        child,
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  final Color color1;
  final Color color2;

  _StripePainter({
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dividir en 6 columnas iguales (16.67% cada una)
    // Acercar las franjas más a la esquina superior derecha
    // Franja 5: desde 75% hasta 87.5% (12.5% del ancho)
    // Franja 6: desde 87.5% hasta 100% (12.5% del ancho)
    
    // Franja 5: más cerca de la esquina
    final col5Rect = Rect.fromLTWH(
      size.width * 0.75, // 75% = inicio de franja 5
      0,
      size.width * 0.125, // 12.5% del ancho (hasta 87.5%)
      size.height,
    );
    canvas.drawRect(col5Rect, Paint()..color = color1);
    
    // Franja 6: hasta el borde derecho
    final col6Rect = Rect.fromLTWH(
      size.width * 0.875, // 87.5% = inicio de franja 6
      0,
      size.width * 0.125, // 12.5% del ancho (hasta 100%)
      size.height,
    );
    canvas.drawRect(col6Rect, Paint()..color = color2);
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) {
    return oldDelegate.color1 != color1 || oldDelegate.color2 != color2;
  }
}


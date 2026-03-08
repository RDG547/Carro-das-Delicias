import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget reutilizável para renderizar ícones de categoria.
/// Suporta SVG assets (prefixo 'asset:' + .svg), PNG assets (prefixo 'asset:' + .png),
/// URLs de imagem (prefixo 'http'), e emojis/texto (renderizados diretamente).
/// Quando o ícone é nulo ou vazio, exibe o ícone padrão (todos_category.svg).
///
/// Se [categoryName] for fornecido e o ícone não for um asset explícito,
/// tenta usar um override de ícone PNG local para a categoria.
class CategoryIconWidget extends StatelessWidget {
  final String? icone;
  final double size;
  final String? categoryName;

  /// Mapa de ícones PNG locais por nome de categoria.
  static const Map<String, String> categoryIconOverrides = {
    'Rocamboles': 'asset:assets/icons/rocambole_category.png',
    'Bolos': 'asset:assets/icons/bolo_category.png',
    'Doces': 'asset:assets/icons/doce_category.png',
    'Salgados': 'asset:assets/icons/salgado_category.png',
    'Bebidas': 'asset:assets/icons/bebida_category.png',
    'Sobremesas': 'asset:assets/icons/sobremesa_category.png',
  };

  const CategoryIconWidget({
    super.key,
    required this.icone,
    this.size = 24,
    this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    String? icon = icone;

    // Se o ícone não é um asset explícito, aplicar override por nome da categoria
    if (categoryName != null &&
        (icon == null || icon.isEmpty || !icon.startsWith('asset:'))) {
      final override = categoryIconOverrides[categoryName];
      if (override != null) {
        icon = override;
      }
    }

    if (icon == null || icon.isEmpty) {
      // Ícone padrão quando nenhum é definido
      return SvgPicture.asset(
        'assets/icons/todos_category.svg',
        width: size,
        height: size,
      );
    }

    if (icon.startsWith('asset:')) {
      final assetPath = icon.replaceFirst('asset:', '');
      if (assetPath.endsWith('.svg')) {
        return SvgPicture.asset(assetPath, width: size, height: size);
      } else {
        return Image.asset(
          assetPath,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) =>
              Text('📦', style: TextStyle(fontSize: size * 0.67)),
        );
      }
    } else if (icon.startsWith('http')) {
      return Image.network(
        icon,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 16),
      );
    } else {
      // Emoji ou texto - renderizar diretamente
      return Text(icon, style: TextStyle(fontSize: size * 0.67));
    }
  }
}

import 'dart:convert';

class ProductVariantUtils {
  static List<Map<String, dynamic>> extractSizes(dynamic rawSizes) {
    return _extractOptions(rawSizes);
  }

  static List<Map<String, dynamic>> extractFlavors(dynamic rawFlavors) {
    return _extractOptions(rawFlavors);
  }

  static bool hasSizeOptions(Map<String, dynamic> product) {
    return extractSizes(product['tamanhos']).isNotEmpty;
  }

  static bool hasFlavorOptions(Map<String, dynamic> product) {
    return extractFlavors(product['sabores']).isNotEmpty;
  }

  static bool hasMultipleFlavors(Map<String, dynamic> product) {
    return extractFlavors(product['sabores']).length > 1;
  }

  static String flavorCountLabel(int flavorCount) {
    return '$flavorCount ${flavorCount == 1 ? 'Sabor' : 'Sabores'}';
  }

  static bool flavorOptionsMatch(dynamic actual, dynamic expected) {
    final actualFlavors = extractFlavors(actual);
    final expectedFlavors = extractFlavors(expected);

    if (actualFlavors.length != expectedFlavors.length) {
      return false;
    }

    for (var i = 0; i < expectedFlavors.length; i++) {
      final actualName = optionName(actualFlavors[i])?.trim() ?? '';
      final expectedName = optionName(expectedFlavors[i])?.trim() ?? '';
      if (actualName != expectedName) return false;

      final actualIcon = optionIcon(actualFlavors[i])?.trim() ?? '';
      final expectedIcon = optionIcon(expectedFlavors[i])?.trim() ?? '';
      if (actualIcon != expectedIcon) return false;

      final actualEmoji = optionEmoji(actualFlavors[i])?.trim() ?? '';
      final expectedEmoji = optionEmoji(expectedFlavors[i])?.trim() ?? '';
      if (actualEmoji != expectedEmoji) return false;

      final actualImages = optionImages(actualFlavors[i]);
      final expectedImages = optionImages(expectedFlavors[i]);
      if (actualImages.length != expectedImages.length) return false;

      for (
        var imageIndex = 0;
        imageIndex < expectedImages.length;
        imageIndex++
      ) {
        if (actualImages[imageIndex] != expectedImages[imageIndex]) {
          return false;
        }
      }
    }

    return true;
  }

  static String? optionName(dynamic option) {
    if (option == null) return null;
    if (option is Map) {
      return (option['nome'] ?? option['name'])?.toString();
    }

    final text = option.toString();
    if (text.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return (decoded['nome'] ?? decoded['name'])?.toString() ?? text;
      }
    } catch (_) {
      // Mantem o texto original quando nao for JSON.
    }

    return text;
  }

  static String? optionIcon(dynamic option) {
    if (option == null) return null;

    final rawIcon = _rawOptionValue(option, const [
      'icone',
      'icon',
      'imagem_icone',
      'icon_image',
      'emoji',
    ]);
    final icon = rawIcon?.toString().trim();
    if (icon == null || icon.isEmpty) return null;
    return icon;
  }

  static String? optionEmoji(dynamic option) {
    if (option == null) return null;

    final rawEmoji = _rawOptionValue(option, const ['emoji']);
    final emoji = rawEmoji?.toString().trim();
    if (emoji != null && emoji.isNotEmpty) return emoji;

    final rawIcon = _rawOptionValue(option, const ['icone', 'icon']);
    final icon = rawIcon?.toString().trim();
    if (icon == null || icon.isEmpty || isImageIcon(icon)) return null;
    return icon;
  }

  static String? optionImageIcon(dynamic option) {
    if (option == null) return null;

    final rawIcon = _rawOptionValue(option, const [
      'icone',
      'icon',
      'imagem_icone',
      'icon_image',
    ]);
    final icon = rawIcon?.toString().trim();
    if (icon == null || icon.isEmpty || !isImageIcon(icon)) return null;
    return icon;
  }

  static bool isImageIcon(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('asset:') ||
        normalized.startsWith('http://') ||
        normalized.startsWith('https://');
  }

  static List<String> productImages(
    Map<String, dynamic> product, {
    Map<String, dynamic>? selectedFlavor,
  }) {
    final flavorImages = optionImages(selectedFlavor);
    if (flavorImages.isNotEmpty) return flavorImages;

    final productImages = _extractImageList(product['imagens']);
    if (productImages.isNotEmpty) return productImages;

    final imageUrl = product['imagem_url']?.toString().trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return [imageUrl];
    }

    for (final flavor in extractFlavors(product['sabores'])) {
      final images = optionImages(flavor);
      if (images.isNotEmpty) return images;
    }

    return const [];
  }

  static List<String> optionImages(Map<String, dynamic>? option) {
    if (option == null) return const [];

    final images = _extractImageList(option['imagens']);
    if (images.isNotEmpty) return images;

    final imageUrl = (option['imagem_url'] ?? option['image_url'])
        ?.toString()
        .trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return [imageUrl];
    }

    return const [];
  }

  static Map<String, dynamic> applySelections(
    Map<String, dynamic> product, {
    Map<String, dynamic>? selectedSize,
    Map<String, dynamic>? selectedFlavor,
  }) {
    final selectedProduct = Map<String, dynamic>.from(product);

    if (selectedSize != null) {
      selectedProduct['tamanho_selecionado'] = optionName(selectedSize);
      if (selectedSize['preco'] != null) {
        selectedProduct['preco'] = selectedSize['preco'];
      }
    }

    if (selectedFlavor != null) {
      selectedProduct['sabor_selecionado'] = optionName(selectedFlavor);
      final flavorImages = optionImages(selectedFlavor);
      if (flavorImages.isNotEmpty) {
        selectedProduct['imagens'] = flavorImages;
        selectedProduct['imagem_url'] = flavorImages.first;
      }
    }

    return selectedProduct;
  }

  static String selectionSuffix({String? sizeName, String? flavorName}) {
    final parts = <String>[];
    if (sizeName != null && sizeName.trim().isNotEmpty) {
      parts.add(sizeName.trim());
    }
    if (flavorName != null && flavorName.trim().isNotEmpty) {
      parts.add(flavorName.trim());
    }
    if (parts.isEmpty) return '';
    return ' (${parts.join(' / ')})';
  }

  static double? toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value
          .replaceAll('R\$', '')
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  static List<Map<String, dynamic>> _extractOptions(dynamic rawOptions) {
    dynamic parsed = rawOptions;

    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return const [];
      }
    }

    if (parsed is! List) {
      return const [];
    }

    return parsed
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static dynamic _rawOptionValue(dynamic option, List<String> keys) {
    dynamic parsed = option;

    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return null;
      }
    }

    if (parsed is! Map) return null;

    for (final key in keys) {
      final value = parsed[key];
      if (value != null) return value;
    }

    return null;
  }

  static List<String> _extractImageList(dynamic rawImages) {
    dynamic parsed = rawImages;

    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        parsed = parsed
            .split(RegExp(r'[\n,;]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    }

    if (parsed is! List) {
      return const [];
    }

    return parsed
        .where((item) => item != null)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

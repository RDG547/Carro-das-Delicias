import 'package:flutter/material.dart';
import 'product_variant_utils.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class FlavorIconAssets {
  static const String directory = 'assets/icons/sabores/';

  static const List<String> fallbackIcons = [
    'asset:assets/icons/sabores/Pizza_Calabresa.png',
    'asset:assets/icons/sabores/Pizza_Calabresa_Presunto.png',
    'asset:assets/icons/sabores/Pizza_Calabresa__Frango_Catupiry.png',
    'asset:assets/icons/sabores/Pizza_Mussarela.png',
    'asset:assets/icons/sabores/Pizza_Presunto.png',
  ];

  static Future<List<String>>? _iconsFuture;
  static final Set<String> _preloaded = {};
  static Future<List<String>> loadIcons() => _iconsFuture ??= _loadIcons();
  static Future<List<String>> _loadIcons() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final icons =
          manifest
              .listAssets()
              .where((asset) => asset.startsWith(directory))
              .where(_isSupportedImage)
              .map((asset) => 'asset:$asset')
              .toList()
            ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));
      return icons.isEmpty ? fallbackIcons : icons;
    } catch (_) {
      return fallbackIcons;
    }
  }

  static Future<void> precacheForProducts(
    BuildContext context,
    Iterable<Map<String, dynamic>> products,
  ) async {
    final icons = <String>{...await loadIcons()};
    for (final product in products) {
      for (final flavor in ProductVariantUtils.extractFlavors(
        product['sabores'],
      )) {
        final icon = ProductVariantUtils.optionIcon(flavor);
        if (icon != null) icons.add(icon);
      }
    }
    for (final icon in icons) {
      if (!context.mounted) return;
      if (!_preloaded.add(icon)) continue;
      ImageProvider? provider;
      if (icon.startsWith('asset:') && !icon.toLowerCase().endsWith('.svg')) {
        provider = AssetImage(icon.substring(6));
      } else if (icon.startsWith('https://') || icon.startsWith('http://')) {
        provider = NetworkImage(icon);
      }
      if (provider == null) continue;
      await precacheImage(
        ResizeImage(provider, width: 128, height: 128),
        context,
        onError: (_, _) {
          _preloaded.remove(icon);
        },
      );
    }
  }

  static String labelFor(String iconValue) {
    final cleanPath = iconValue.replaceFirst('asset:', '');
    final fileName = path.basenameWithoutExtension(cleanPath);
    final label = fileName
        .replaceAll('__', ' / ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return label.isEmpty ? 'Icone' : label;
  }

  static bool _isSupportedImage(String assetPath) {
    final lowerPath = assetPath.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.webp') ||
        lowerPath.endsWith('.svg');
  }
}

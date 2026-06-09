import 'dart:convert';

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

  static Future<List<String>> loadIcons() async {
    try {
      final manifestText = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
      final icons =
          manifest.keys
              .where((assetPath) => assetPath.startsWith(directory))
              .where(_isSupportedImage)
              .map((assetPath) => 'asset:$assetPath')
              .toList()
            ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));

      return icons.isEmpty ? fallbackIcons : icons;
    } catch (_) {
      return fallbackIcons;
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

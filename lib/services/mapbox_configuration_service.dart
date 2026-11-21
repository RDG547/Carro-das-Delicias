import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../config/supabase_config.dart';

class MapboxConfigurationService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android &&
        SupabaseConfig.mapboxAccessToken.isEmpty) {
      try {
        final token = await const MethodChannel(
          'com.rdtech.carrodasdelicias/config',
        ).invokeMethod<String>('getMapboxAccessToken');
        if (token != null) SupabaseConfig.configureNativeMapboxToken(token);
      } on PlatformException catch (_) {
        debugPrint('A configuração nativa do mapa não está disponível.');
      } on MissingPluginException catch (_) {
        debugPrint(
          'A configuração nativa do mapa não está disponível nesta plataforma.',
        );
      }
    }
    if (SupabaseConfig.mapboxAccessToken.isNotEmpty &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      MapboxOptions.setAccessToken(SupabaseConfig.mapboxAccessToken);
    }
  }
}

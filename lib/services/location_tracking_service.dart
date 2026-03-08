import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class LocationTrackingService {
  static final LocationTrackingService _instance =
      LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;

  final _supabase = Supabase.instance.client;

  /// Verifica e solicita permissões de localização
  Future<bool> checkAndRequestPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Verifica se o serviço de localização está habilitado
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Inicia o rastreamento de localização em tempo real
  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      throw Exception('Permissão de localização negada');
    }

    _isTracking = true;

    // Marca como online no banco
    await _updateOnlineStatus(true);

    // Configurações de precisão de localização
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Atualiza a cada 10 metros
    );

    // Stream de posições em tempo real
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            _updateLocation(position.latitude, position.longitude);
          },
          onError: (error) {
            debugPrint('Erro ao obter localização: $error');
          },
        );

    // Fallback: atualiza a cada 30 segundos mesmo sem mudança significativa
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition();
        await _updateLocation(position.latitude, position.longitude);
      } catch (e) {
        debugPrint('Erro ao atualizar localização: $e');
      }
    });
  }

  /// Para o rastreamento de localização
  Future<void> stopTracking() async {
    debugPrint('🛑 stopTracking chamado - _isTracking: $_isTracking');
    if (!_isTracking) {
      debugPrint('⚠️ Rastreamento já estava parado');
      return;
    }

    _isTracking = false;
    debugPrint('✅ _isTracking definido como false');

    // Cancela subscriptions
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint('✅ Stream de posição cancelada');

    _locationTimer?.cancel();
    _locationTimer = null;
    debugPrint('✅ Timer cancelado');

    // Marca como offline no banco
    debugPrint('📡 Chamando _updateOnlineStatus(false)...');
    await _updateOnlineStatus(false);
    debugPrint('✅ stopTracking concluído');
  }

  /// Atualiza a localização no banco de dados
  Future<void> _updateLocation(double latitude, double longitude) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('kombi_location').upsert({
        'admin_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'is_online': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'admin_id');
    } catch (e) {
      debugPrint('Erro ao atualizar localização no banco: $e');
    }
  }

  /// Atualiza o status online/offline
  Future<void> _updateOnlineStatus(bool isOnline) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      debugPrint('🔍 _updateOnlineStatus($isOnline) - userId: $userId');

      if (userId == null) {
        debugPrint('⚠️ userId é null, abortando');
        return;
      }

      if (isOnline) {
        // Obtém localização atual ao ficar online
        debugPrint('📍 Obtendo posição atual...');
        final position = await Geolocator.getCurrentPosition();
        debugPrint(
          '📍 Posição obtida: ${position.latitude}, ${position.longitude}',
        );

        await _supabase.from('kombi_location').upsert({
          'admin_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'is_online': true,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'admin_id');
        debugPrint('✅ Status ONLINE atualizado no banco');
      } else {
        // Apenas marca como offline, mantém última localização
        debugPrint('📡 Atualizando is_online=false no banco...');
        final result = await _supabase
            .from('kombi_location')
            .update({
              'is_online': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('admin_id', userId)
            .select();
        debugPrint('✅ Status OFFLINE atualizado no banco - resultado: $result');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao atualizar status online: $e');
      debugPrint('Stack: $stackTrace');
    }
  }

  /// Obtém a localização atual da Kombi (para usuários visualizarem)
  Future<Map<String, dynamic>?> getCurrentKombiLocation() async {
    try {
      final response = await _supabase
          .from('kombi_location')
          .select()
          .eq('is_online', true)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Erro ao obter localização da Kombi: $e');
      return null;
    }
  }

  /// Obtém todas as Kombis online
  Future<List<Map<String, dynamic>>> getAllOnlineKombis() async {
    try {
      final response = await _supabase
          .from('kombi_location')
          .select()
          .eq('is_online', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Erro ao obter Kombis online: $e');
      return [];
    }
  }

  /// Obtém nomes dos vendedores a partir dos admin_ids
  Future<Map<String, String>> getVendorNames(List<String> adminIds) async {
    if (adminIds.isEmpty) return {};
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, name')
          .inFilter('id', adminIds);

      final map = <String, String>{};
      for (final row in response) {
        final id = row['id'] as String;
        final name = row['name'] as String? ?? 'Vendedor';
        map[id] = name;
      }
      return map;
    } catch (e) {
      debugPrint('Erro ao obter nomes dos vendedores: $e');
      return {};
    }
  }

  /// Stream de atualizações de localização em tempo real
  Stream<Map<String, dynamic>?> watchKombiLocation() {
    return _supabase
        .from('kombi_location')
        .stream(primaryKey: ['id'])
        .eq('is_online', true)
        .map((data) => data.isNotEmpty ? data.first : null);
  }

  /// Stream de todas as Kombis (online e offline)
  Stream<List<Map<String, dynamic>>> watchAllKombis() {
    return _supabase.from('kombi_location').stream(primaryKey: ['id']);
  }

  /// Verifica se está rastreando
  bool get isTracking => _isTracking;

  /// Cleanup quando o app é fechado
  void dispose() {
    stopTracking();
  }
}

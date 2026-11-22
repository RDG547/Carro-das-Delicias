import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AppSoundService {
  static final _player = AudioPlayer();
  static final _completedOrders = <String>{};

  static Future<void> _play(String asset) async {
    try {
      await _player.play(AssetSource('sounds/$asset.wav'), volume: 0.65);
    } catch (_) {
      // Audio must never interrupt cart or payment operations.
    }
  }

  static void cartCleared() => unawaited(_play('cart_clear'));
  static void purchaseCompleted(Object orderId) {
    if (_completedOrders.add(orderId.toString()))
      unawaited(_play('purchase_complete'));
  }
}

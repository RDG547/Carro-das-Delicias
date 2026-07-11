import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await RemotePushService.initializeFirebaseOnly();
  debugPrint('📩 FCM background: ${message.messageId}');
}

class RemotePushService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const int _maxTokenAttempts = 3;
  static const Duration _tokenRetryDelay = Duration(seconds: 4);
  static bool _firebaseReady = false;
  static bool _initialized = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static String? _lastRegisteredToken;

  static Future<void> initialize() async {
    if (_initialized) return;

    await initializeFirebaseOnly();
    if (!_firebaseReady) {
      debugPrint('⚠️ Firebase/FCM não configurado; push remoto desativado.');
      _initialized = true;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        '📩 FCM foreground: ${message.notification?.title ?? message.messageId}',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('📲 Notificação FCM aberta: ${message.messageId}');
    });

    _initialized = true;
  }

  static Future<void> initializeFirebaseOnly() async {
    if (_firebaseReady) return;

    try {
      if (Firebase.apps.isEmpty) {
        final options = AppFirebaseConfig.options;
        if (options != null) {
          await Firebase.initializeApp(options: options);
        } else {
          await Firebase.initializeApp();
        }
      }
      _firebaseReady = true;
    } catch (error) {
      debugPrint(
        '⚠️ Firebase não inicializado. Configure android/app/google-services.json '
        'ou as variáveis FIREBASE_* no dart-define. Detalhe: $error',
      );
    }
  }

  static Future<void> registerCurrentDevice(User user) async {
    await initialize();
    if (!_firebaseReady) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🔔 Permissão FCM: ${settings.authorizationStatus}');

      final token = await _getTokenWithRetry();
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ FCM não retornou token para ${user.id}');
        return;
      }

      await _registerToken(token);
      _lastRegisteredToken = token;

      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
          .listen((newToken) {
            unawaited(
              _registerToken(newToken).catchError((error) {
                debugPrint('⚠️ Erro ao atualizar token FCM: $error');
              }),
            );
          });
    } catch (error) {
      debugPrint('❌ Erro ao registrar token FCM: $error');
    }
  }

  static Future<String?> _getTokenWithRetry() async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxTokenAttempts; attempt++) {
      try {
        return await FirebaseMessaging.instance.getToken();
      } catch (error) {
        lastError = error;
        final shouldRetry =
            attempt < _maxTokenAttempts && _isTransientTokenError(error);

        if (shouldRetry) {
          final nextDelay = _tokenRetryDelay * attempt;
          debugPrint(
            '⏳ FCM ainda não retornou token '
            '(tentativa $attempt/$_maxTokenAttempts). '
            'Nova tentativa em ${nextDelay.inSeconds}s: ${_describeTokenError(error)}',
          );
        } else {
          debugPrint(
            '❌ Falha definitiva ao obter token FCM '
            '(tentativa $attempt/$_maxTokenAttempts): ${_describeTokenError(error)}',
          );
        }

        if (!shouldRetry) break;
        await Future<void>.delayed(_tokenRetryDelay * attempt);
      }
    }

    if (lastError != null) {
      throw Exception(_describeTokenError(lastError));
    }
    return null;
  }

  static bool _isTransientTokenError(Object error) {
    final details = _describeTokenError(error).toLowerCase();
    return details.contains('fcm registration failed') ||
        details.contains('service_not_available') ||
        details.contains('timeout') ||
        details.contains('network') ||
        details.contains('ioexception');
  }

  static String _describeTokenError(Object error) {
    if (error is FirebaseException) {
      return [
        error.plugin,
        error.code,
        error.message,
      ].whereType<String>().join(' ');
    }
    return error.toString();
  }

  static Future<void> unregisterCurrentDevice() async {
    if (!_firebaseReady) return;

    try {
      final token =
          _lastRegisteredToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _supabase.rpc('unregister_push_token', params: {'p_token': token});
      _lastRegisteredToken = null;
    } catch (error) {
      debugPrint('⚠️ Erro ao desativar token FCM: $error');
    }
  }

  static Future<void> stop() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  static Future<void> _registerToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase.rpc(
      'register_push_token',
      params: {
        'p_token': token,
        'p_platform': _platformLabel,
        'p_device_id': null,
        'p_app_version': null,
      },
    );
    _lastRegisteredToken = token;
    debugPrint('✅ Token FCM registrado para ${user.id}');
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

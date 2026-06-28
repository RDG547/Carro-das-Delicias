import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/network_error_utils.dart';

class UserPresenceService {
  UserPresenceService._();

  static final UserPresenceService instance = UserPresenceService._();

  static const Duration _heartbeatInterval = Duration(seconds: 30);

  Timer? _heartbeatTimer;
  String? _userId;
  DateTime? _retryAfter;
  bool _networkWarningShown = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> start(User user) async {
    _userId = user.id;
    await _writePresence(isOnline: true, user: user);

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(_writePresence(isOnline: true));
    });
  }

  Future<void> pause() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _writePresence(isOnline: false);
  }

  Future<void> stop({bool markOffline = true}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (markOffline) {
      await _writePresence(isOnline: false);
    }
    _userId = null;
  }

  Future<void> _writePresence({required bool isOnline, User? user}) async {
    final activeUser = user ?? _supabase.auth.currentUser;
    final userId = activeUser?.id ?? _userId;
    if (userId == null) return;
    if (_isNetworkBackoffActive) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final presencePayload = <String, dynamic>{
      'is_online': isOnline,
      'last_access_at': now,
      'updated_at': now,
    };

    final email = activeUser?.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      presencePayload['email'] = email;
    }

    try {
      final updated = await _supabase
          .from('profiles')
          .update(presencePayload)
          .eq('id', userId)
          .select('id')
          .limit(1);

      if (updated.isNotEmpty) {
        _clearNetworkBackoff();
        return;
      }

      await _supabase.from('profiles').insert({
        ...presencePayload,
        'id': userId,
        'name': _fallbackName(activeUser, email),
      });
      _clearNetworkBackoff();
    } catch (error) {
      if (NetworkErrorUtils.isTransientNetworkError(error)) {
        _markNetworkUnavailable();
        return;
      }

      debugPrint('Erro ao atualizar presença do usuário: $error');
    }
  }

  bool get _isNetworkBackoffActive {
    final retryAfter = _retryAfter;
    return retryAfter != null && DateTime.now().isBefore(retryAfter);
  }

  void _markNetworkUnavailable() {
    _retryAfter = DateTime.now().add(const Duration(minutes: 1));
    if (_networkWarningShown) return;

    debugPrint(
      'Sem conexão com Supabase para atualizar presença do usuário; nova tentativa em 60s.',
    );
    _networkWarningShown = true;
  }

  void _clearNetworkBackoff() {
    _retryAfter = null;
    _networkWarningShown = false;
  }

  String _fallbackName(User? user, String? email) {
    final metadata = user?.userMetadata ?? <String, dynamic>{};
    final metadataName = (metadata['full_name'] ?? metadata['name'])
        ?.toString()
        .trim();
    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    final emailName = email?.split('@').first.trim();
    if (emailName != null && emailName.isNotEmpty) {
      return emailName;
    }

    return 'Usuário';
  }
}

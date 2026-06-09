import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeAuthUtils {
  static const Duration _refreshSkew = Duration(minutes: 1);

  static bool isExpiredJwtError(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('invalidjwttoken') ||
        message.contains('token has expired') ||
        message.contains('jwt expired');
  }

  static bool _expiresSoon(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;

    final expiresAtDate = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return expiresAtDate.isBefore(DateTime.now().add(_refreshSkew));
  }

  static Future<bool> syncRealtimeAuthToken({
    String source = 'realtime',
  }) async {
    final supabase = Supabase.instance.client;
    final auth = supabase.auth;
    final session = auth.currentSession;

    if (session == null) {
      return false;
    }

    try {
      var activeSession = session;

      if (session.isExpired || _expiresSoon(session)) {
        final response = await auth.refreshSession();
        activeSession = response.session ?? auth.currentSession ?? session;
      }

      await supabase.realtime.setAuth(activeSession.accessToken);
      return true;
    } catch (error) {
      debugPrint('❌ [$source] Falha ao sincronizar token realtime: $error');
      return false;
    }
  }

  static Future<bool> refreshSessionIfNeeded({
    String source = 'realtime',
  }) async {
    final supabase = Supabase.instance.client;
    final auth = supabase.auth;
    final session = auth.currentSession;

    if (session == null) {
      debugPrint('⚠️ [$source] Sem sessão ativa para renovar token realtime');
      return false;
    }

    try {
      final response = await auth.refreshSession();
      final refreshed = response.session != null;
      final activeSession = response.session ?? auth.currentSession;
      if (activeSession != null) {
        await supabase.realtime.setAuth(activeSession.accessToken);
      }
      debugPrint(
        refreshed
            ? '✅ [$source] Sessão renovada para reconectar realtime'
            : '⚠️ [$source] Refresh retornou sem sessão válida',
      );
      return refreshed;
    } catch (error) {
      debugPrint('❌ [$source] Falha ao renovar sessão realtime: $error');
      return false;
    }
  }

  static Future<bool> recoverFromAuthError({
    required Object? error,
    required Future<void> Function() onRecovered,
    String source = 'realtime',
  }) async {
    if (!isExpiredJwtError(error)) {
      return false;
    }

    final refreshed = await refreshSessionIfNeeded(source: source);
    if (!refreshed) {
      return false;
    }

    await onRecovered();
    return true;
  }
}

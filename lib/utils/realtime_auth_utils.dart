import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeAuthUtils {
  static bool isExpiredJwtError(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('invalidjwttoken') ||
        message.contains('token has expired') ||
        message.contains('jwt expired');
  }

  static Future<bool> refreshSessionIfNeeded({
    String source = 'realtime',
  }) async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    if (session == null) {
      debugPrint('⚠️ [$source] Sem sessão ativa para renovar token realtime');
      return false;
    }

    try {
      final response = await auth.refreshSession();
      final refreshed = response.session != null;
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

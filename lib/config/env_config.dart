import 'dart:io';

/// Helper para carregar variáveis de ambiente do arquivo .env em runtime.
/// Funciona em mobile/desktop sem precisar listar .env como asset.
class EnvConfig {
  static final Map<String, String> _vars = {};
  static bool _loaded = false;

  /// Carrega as variáveis do .env (chamado uma vez no main)
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final file = File('.env');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final idx = trimmed.indexOf('=');
          if (idx <= 0) continue;
          final key = trimmed.substring(0, idx).trim();
          final value = trimmed.substring(idx + 1).trim();
          _vars[key] = value;
        }
      }
    } catch (_) {
      // .env não disponível (ex: CI/CD) — usa --dart-define
    }
  }

  /// Obtém uma variável: primeiro tenta --dart-define, depois .env
  static String get(String key, {String defaultValue = ''}) {
    final fromDartDefine = _dartDefines[key];
    if (fromDartDefine != null && fromDartDefine.isNotEmpty) {
      return fromDartDefine;
    }
    return _vars[key] ?? defaultValue;
  }

  // Mapa de --dart-define (compile-time)
  static const Map<String, String> _dartDefines = {
    'STRIPE_SECRET_KEY': String.fromEnvironment('STRIPE_SECRET_KEY'),
    'STRIPE_PUBLISHABLE_KEY': String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
    'ABACATEPAY_API_KEY': String.fromEnvironment('ABACATEPAY_API_KEY'),
  };
}

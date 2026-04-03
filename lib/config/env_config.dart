/// Helper para acessar variáveis de ambiente injetadas via --dart-define-from-file.
class EnvConfig {
  /// Obtém uma variável de ambiente (injetada em compile-time)
  static String get(String key, {String defaultValue = ''}) {
    final value = _dartDefines[key];
    if (value != null && value.isNotEmpty) return value;
    return defaultValue;
  }

  // Mapa de --dart-define (compile-time via --dart-define-from-file=.env)
  static const Map<String, String> _dartDefines = {
    'STRIPE_SECRET_KEY': String.fromEnvironment('STRIPE_SECRET_KEY'),
    'STRIPE_PUBLISHABLE_KEY': String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
    'ABACATEPAY_API_KEY': String.fromEnvironment('ABACATEPAY_API_KEY'),
  };
}

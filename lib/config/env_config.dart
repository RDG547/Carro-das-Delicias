/// Helper para acessar configurações injetadas via --dart-define.
///
/// Não injete chaves secretas em builds de release. Apps Flutter são
/// distribuídos ao cliente e strings embutidas podem ser extraídas do APK/AAB.
class EnvConfig {
  /// Obtém uma variável de ambiente (injetada em compile-time)
  static String get(String key, {String defaultValue = ''}) {
    final value = _dartDefines[key];
    if (value != null && value.isNotEmpty) return value;
    return defaultValue;
  }

  // Mapa de --dart-define. Chaves de pagamento abaixo existem apenas para
  // desenvolvimento local; os serviços bloqueiam seu uso em kReleaseMode.
  static const Map<String, String> _dartDefines = {
    'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    'STRIPE_SECRET_KEY': String.fromEnvironment('STRIPE_SECRET_KEY'),
    'STRIPE_PUBLISHABLE_KEY': String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
    'ABACATEPAY_API_KEY': String.fromEnvironment('ABACATEPAY_API_KEY'),
  };
}

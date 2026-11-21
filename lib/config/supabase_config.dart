/// Configuração segura do Supabase
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rlpnatsygjdzijpwhfxo.supabase.co',
  );

  // ANON KEY: chave pública para desenvolvimento - é seguro expor
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJscG5hdHN5Z2pkemlqcHdoZnhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc4NzE5MjYsImV4cCI6MjA3MzQ0NzkyNn0.UzHldJo7CVJj2Kk-jgQRQ7IuF3ae0MomaO5HbxrjAPw',
  );

  static String get projectRef {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return 'desconhecido';
    return host.split('.').first;
  }

  // MAPBOX TOKEN: Token público do Mapbox para desenvolvimento
  // Para obter um novo token:
  // 1. Acesse: https://account.mapbox.com/access-tokens/
  // 2. Crie um novo token com os escopos: styles:read, fonts:read, geocoding
  // 3. Substitua o valor abaixo
  static const String _mapboxTokenFromEnvironment = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );
  static String _nativeMapboxToken = '';
  static String get mapboxAccessToken =>
      _mapboxTokenFromEnvironment.trim().isNotEmpty
      ? _mapboxTokenFromEnvironment.trim()
      : _nativeMapboxToken;
  static void configureNativeMapboxToken(String token) {
    _nativeMapboxToken = token.trim();
  }
}

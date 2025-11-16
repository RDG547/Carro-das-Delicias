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

  // MAPBOX TOKEN: Token público do Mapbox para desenvolvimento
  // Para obter um novo token:
  // 1. Acesse: https://account.mapbox.com/access-tokens/
  // 2. Crie um novo token com os escopos: styles:read, fonts:read, geocoding
  // 3. Substitua o valor abaixo
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue:
        'pk.eyJ1IjoicmRnNTQ3IiwiYSI6ImNtaHNmY21zdDFpbXcyanB6N2w0Y2NyeWYifQ.RAwJc13MPekGYnD6js9g2A',
  );
}

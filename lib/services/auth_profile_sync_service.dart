import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProfileSyncService {
  static Future<void> syncCurrentUserProfile() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final metadata = user.userMetadata ?? <String, dynamic>{};
      final displayName = (metadata['full_name'] ?? metadata['name'])
          ?.toString()
          .trim();
      final avatarUrl = (metadata['avatar_url'] ?? metadata['picture'])
          ?.toString()
          .trim();
      final phone = metadata['phone']?.toString().trim();

      // Verificar se o perfil já existe para não sobrescrever o role
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      final payload = <String, dynamic>{
        'id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Só definir role na criação do perfil (não sobrescrever role existente)
      if (existing == null) {
        payload['role'] = 'client';
      }

      final email = user.email?.trim().toLowerCase();
      if (email != null && email.isNotEmpty) {
        payload['email'] = email;
      }

      if (displayName != null && displayName.isNotEmpty) {
        payload['name'] = displayName;
      }

      if (phone != null && phone.isNotEmpty) {
        payload['phone'] = phone;
      }

      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        payload['avatar_url'] = avatarUrl;
      }

      await supabase.from('profiles').upsert(payload, onConflict: 'id');
    } catch (error) {
      debugPrint('Erro ao sincronizar perfil autenticado: $error');
    }
  }
}

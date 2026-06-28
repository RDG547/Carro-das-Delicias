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

      final payload = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

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

      final updated = await supabase
          .from('profiles')
          .update(payload)
          .eq('id', user.id)
          .select('id')
          .limit(1);

      if (updated.isNotEmpty) return;

      await supabase.from('profiles').insert({
        ...payload,
        'id': user.id,
        'name': _fallbackName(
          displayName: displayName,
          email: email,
          metadata: metadata,
        ),
      });
    } catch (error) {
      debugPrint('Erro ao sincronizar perfil autenticado: $error');
    }
  }

  static String _fallbackName({
    required String? displayName,
    required String? email,
    required Map<String, dynamic> metadata,
  }) {
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

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

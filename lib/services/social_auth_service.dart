import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialAuthService {
  /// Web Client ID do Google Cloud Console (mesmo configurado no Supabase Auth).
  /// Defina via GOOGLE_WEB_CLIENT_ID no .env
  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static Future<void> signInWithGoogle() async {
    // Na web, usar OAuth redirect padrão
    if (kIsWeb) {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        scopes: 'openid email profile',
      );
      if (!launched) {
        throw Exception('Não foi possível abrir o login do Google.');
      }
      return;
    }

    // No mobile, usar login nativo (dentro do app)
    final googleSignIn = GoogleSignIn(serverClientId: _webClientId);

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Login com Google cancelado.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('Não foi possível obter o token do Google.');
    }

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }
}

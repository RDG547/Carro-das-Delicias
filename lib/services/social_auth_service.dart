import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';

enum SocialAuthLaunchMode { native, oauth }

class SocialAuthResult {
  final SocialAuthLaunchMode mode;

  const SocialAuthResult(this.mode);

  bool get openedExternalBrowser => mode == SocialAuthLaunchMode.oauth;
}

class SocialAuthService {
  /// Web Client ID do Google Cloud Console (mesmo configurado no Supabase Auth).
  /// Defina via --dart-define=GOOGLE_WEB_CLIENT_ID=...
  static const String _defaultWebClientId =
      '709873107589-kkvu666a7p4iigbeulrv4ptemfslg9co.apps.googleusercontent.com';

  static String get _webClientId => EnvConfig.get(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: _defaultWebClientId,
  ).trim();

  static const String _googleScopes = 'openid email profile';

  static Future<SocialAuthResult> signInWithGoogle() async {
    if (kIsWeb) {
      return _signInWithGoogleOAuth();
    }

    final webClientId = _webClientId;
    if (!_isUsableGoogleWebClientId(webClientId)) {
      throw Exception(
        'GOOGLE_WEB_CLIENT_ID inválido. Configure o Web Client ID do Google no .env.json.',
      );
    }

    try {
      await _signInWithGoogleNative(webClientId);
      return const SocialAuthResult(SocialAuthLaunchMode.native);
    } on PlatformException catch (error) {
      if (_shouldFallbackToOAuth(error)) {
        debugPrint(
          'Google Sign-In nativo falhou com código de configuração. Tentando OAuth do Supabase: $error',
        );
        return _signInWithGoogleOAuth();
      }

      throw Exception(_friendlyGoogleSignInError(error));
    }
  }

  static Future<void> _signInWithGoogleNative(String webClientId) async {
    final googleSignIn = GoogleSignIn(serverClientId: webClientId);
    await _forgetPreviousGoogleAccount(googleSignIn);

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Login com Google cancelado.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception(
        'Não foi possível obter o token do Google. Confira o Web Client ID e os clientes Android com SHA-1 no Google Cloud.',
      );
    }

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  static Future<SocialAuthResult> _signInWithGoogleOAuth() async {
    final launched = await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      scopes: _googleScopes,
      queryParams: {'prompt': 'select_account'},
    );
    if (!launched) {
      throw Exception('Não foi possível abrir o login do Google.');
    }
    return const SocialAuthResult(SocialAuthLaunchMode.oauth);
  }

  static Future<void> _forgetPreviousGoogleAccount(
    GoogleSignIn googleSignIn,
  ) async {
    try {
      await googleSignIn.signOut();
    } catch (error) {
      debugPrint('Não foi possível limpar a conta Google anterior: $error');
    }
  }

  static bool _isUsableGoogleWebClientId(String value) {
    final clientId = value.trim();
    return clientId.endsWith('.apps.googleusercontent.com') &&
        !clientId.contains('xxxx') &&
        !clientId.startsWith('000000000000-');
  }

  static bool _shouldFallbackToOAuth(PlatformException error) {
    final details = [
      error.code,
      error.message,
      error.details?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    return error.code == 'sign_in_failed' &&
        (details.contains('10') || details.contains('developer_error'));
  }

  static String _friendlyGoogleSignInError(PlatformException error) {
    final details = [
      error.code,
      error.message,
      error.details?.toString(),
    ].whereType<String>().join(' ');

    if (_shouldFallbackToOAuth(error)) {
      return 'Configuração do Google Sign-In incompleta. Confira o Web Client ID, o pacote Android e os SHA-1 no Google Cloud.';
    }

    if (details.toLowerCase().contains('network')) {
      return 'Não foi possível conectar ao Google. Verifique sua internet e tente novamente.';
    }

    return 'Não foi possível iniciar o login com Google. Tente novamente.';
  }
}

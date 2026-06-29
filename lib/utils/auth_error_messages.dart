import 'package:supabase_flutter/supabase_flutter.dart';

class AuthErrorMessages {
  static String fromAuthException(AuthException error) {
    final message = error.message;
    final normalized = _normalize(
      '${error.statusCode ?? ''} ${error.code ?? ''} $message',
    );

    if (_isRateLimit(normalized, error.statusCode)) {
      return 'Muitas tentativas de cadastro ou envio de e-mail em pouco tempo. Aguarde alguns minutos e tente novamente. Se continuar, use o cadastro com Google.';
    }

    if (normalized.contains('email address not authorized')) {
      return 'O servidor de e-mail do Supabase ainda não está configurado para produção. Configure um SMTP próprio no Supabase para liberar cadastros de qualquer e-mail.';
    }

    if (normalized.contains('signup_masked_response')) {
      return 'O Supabase não confirmou a criação da conta. Confira se você está olhando o projeto Supabase correto ou tente fazer login/usar outro email.';
    }

    if (normalized.contains('already') ||
        normalized.contains('exists') ||
        normalized.contains('registered') ||
        normalized.contains('user_already_exists')) {
      return 'Este email já está cadastrado. Tente fazer login ou use outro email.';
    }

    if (normalized.contains('invalid login credentials')) {
      return 'Email, celular ou senha inválidos.';
    }

    if (normalized.contains('email not confirmed') ||
        normalized.contains('email_not_confirmed') ||
        normalized.contains('not confirmed')) {
      return 'Confirme seu e-mail antes de fazer login. Verifique sua caixa de entrada ou spam.';
    }

    if (normalized.contains('password')) {
      return 'A senha deve ter pelo menos 6 caracteres.';
    }

    if (normalized.contains('saving new user') ||
        normalized.contains('unexpected_failure')) {
      return 'Não foi possível concluir o cadastro por uma configuração do servidor. Verifique as configurações de Auth no Supabase.';
    }

    return message;
  }

  static String fromFunctionException(FunctionException error) {
    final details = error.details;
    final detailMessage = details is Map
        ? details['message']?.toString()
        : details?.toString();
    final message = detailMessage?.trim().isNotEmpty == true
        ? detailMessage!.trim()
        : error.reasonPhrase ?? 'Erro ao processar a solicitação.';
    final normalized = _normalize('${error.status} $message');

    if (_isRateLimit(normalized, error.status.toString())) {
      return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }

    return message;
  }

  static String fromObject(Object error) {
    if (error is AuthException) {
      return fromAuthException(error);
    }

    if (error is FunctionException) {
      return fromFunctionException(error);
    }

    final message = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    final normalized = _normalize(message);

    if (_isRateLimit(normalized, null)) {
      return 'Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.';
    }

    if (normalized.contains('platformexception') &&
        normalized.contains('sign_in_failed') &&
        normalized.contains('10')) {
      return 'Configuração do Google Sign-In incompleta. Confira o pacote Android e os SHA-1/SHA-256 no Google Cloud e na Play Console.';
    }

    return message;
  }

  static bool _isRateLimit(String normalized, String? statusCode) {
    return statusCode == '429' ||
        normalized.contains('rate limit') ||
        normalized.contains('rate_limit') ||
        normalized.contains('too many requests') ||
        normalized.contains('over_email_send_rate_limit') ||
        normalized.contains('email rate limit');
  }

  static String _normalize(String value) => value.toLowerCase().trim();
}

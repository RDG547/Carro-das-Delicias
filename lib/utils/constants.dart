// Configurações do Supabase
const String supabaseUrl = 'https://jaoehwpvvcwfvcwmkznx.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imphb2Vod3B2dmN3ZnZjd21rem54Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc3OTQzMjQsImV4cCI6MjA3MzM3MDMyNH0.X2NtY0TIBOM_8JItUerG6vNvE0T3Mas_uSF_ErpxrVw';

// Regex para validações
class ValidationRegex {
  static final email = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static final phone = RegExp(r'^[\d\s\(\)\-\+]{10,}$');
}

// Mensagens de erro
class ErrorMessages {
  static const String emailRequired = 'Por favor, digite seu email';
  static const String emailInvalid = 'Digite um email válido';
  static const String phoneRequired = 'Por favor, digite seu celular';
  static const String phoneInvalid =
      'Digite um número de celular válido (10-11 dígitos)';
  static const String passwordRequired = 'Por favor, digite sua senha';
  static const String passwordTooShort =
      'A senha deve ter pelo menos 6 caracteres';
  static const String passwordsDontMatch = 'As senhas não coincidem';
  static const String nameRequired = 'Por favor, digite seu nome';
  static const String nameTooShort = 'Nome deve ter pelo menos 2 caracteres';
  static const String emailOrPhoneRequired =
      'Por favor, digite seu email ou celular';
  static const String emailOrPhoneInvalid =
      'Digite um email válido ou celular (10-11 dígitos)';
}

// Mensagens de sucesso
class SuccessMessages {
  static const String accountCreated = 'Cadastro realizado com sucesso!';
  static const String loginSuccess = 'Login realizado com sucesso!';
  static const String logoutSuccess = 'Logout realizado com sucesso!';
}

// Textos da interface
class AppTexts {
  static const String appName = 'Carro das Delícias';
  static const String login = 'Entre na sua conta';
  static const String register = 'Criar conta';
  static const String fillDataToContinue = 'Preencha seus dados para continuar';
  static const String dontHaveAccount = 'Não tem uma conta? ';
  static const String signUp = 'Cadastre-se';
  static const String alreadyHaveAccount = 'Já tem uma conta? ';
  static const String signIn = 'Entre aqui';
  static const String confirmEmail = 'Confirme seu email';
  static const String confirmEmailMessage =
      'Um link de confirmação foi enviado para seu email. Por favor, confirme seu email antes de fazer login.';
}

// Utilitários de formatação
class CurrencyFormatter {
  /// Formata um valor double para string monetária brasileira
  /// Exemplo: 10.5 -> "R$ 10,50"
  static String format(double? value) {
    if (value == null) return 'R\$ 0,00';

    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Formata um valor double para string monetária sem símbolo
  /// Exemplo: 10.5 -> "10,50"
  static String formatNumber(double? value) {
    if (value == null) return '0,00';

    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}

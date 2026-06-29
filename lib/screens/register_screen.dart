import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/social_auth_service.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/dynamic_password_field.dart';
import '../widgets/google_auth_button.dart';
import '../utils/auth_error_messages.dart';
import '../utils/loading_manager.dart';

/// Formatador para números de celular brasileiro
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;

    // Remove todos os caracteres que não são dígitos
    final digitsOnly = newText.replaceAll(RegExp(r'[^\d]'), '');

    // Limita a 11 dígitos (DDD + 9 dígitos do celular)
    final limitedDigits = digitsOnly.length > 11
        ? digitsOnly.substring(0, 11)
        : digitsOnly;

    String formatted = '';

    if (limitedDigits.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Aplica a formatação baseada na quantidade de dígitos
    if (limitedDigits.length == 1) {
      // Apenas 1 dígito: 1
      formatted = limitedDigits;
    } else if (limitedDigits.length == 2) {
      // 2 dígitos: (11
      formatted = '($limitedDigits';
    } else if (limitedDigits.length <= 6) {
      // DDD + início do número: (11) 9999
      formatted =
          '(${limitedDigits.substring(0, 2)}) ${limitedDigits.substring(2)}';
    } else if (limitedDigits.length <= 10) {
      // Formato antigo: (11) 9999-9999
      formatted =
          '(${limitedDigits.substring(0, 2)}) ${limitedDigits.substring(2, 6)}-${limitedDigits.substring(6)}';
    } else {
      // Formato novo: (11) 99999-9999
      formatted =
          '(${limitedDigits.substring(0, 2)}) ${limitedDigits.substring(2, 7)}-${limitedDigits.substring(7)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ConfirmEmailDialog extends StatefulWidget {
  const _ConfirmEmailDialog({required this.email, required this.onDone});

  final String email;
  final VoidCallback onDone;

  @override
  State<_ConfirmEmailDialog> createState() => _ConfirmEmailDialogState();
}

class _ConfirmEmailDialogState extends State<_ConfirmEmailDialog> {
  static const int _initialSeconds = 5;
  Timer? _timer;
  int _remainingSeconds = _initialSeconds;

  bool get _canClose => _remainingSeconds <= 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canClose,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                color: Colors.green[700],
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Confirme seu e-mail',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enviamos um link de confirmação para:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.25),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                widget.email,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade600),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.report_gmailerrorred_outlined,
                    color: Colors.amber[900],
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Atenção: se não encontrar o e-mail na caixa de entrada, verifique também a pasta Spam ou Lixo eletrônico.',
                      style: TextStyle(
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Após confirmar, volte ao app e faça login normalmente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.25),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canClose ? widget.onDone : null,
              icon: Icon(_canClose ? Icons.check_circle : Icons.timer_outlined),
              label: Text(_canClose ? 'OK' : 'OK ($_remainingSeconds s)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loadingManager = LoadingManager();
  StreamSubscription<AuthState>? _authSubscription;
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardVisible = _isKeyboardVisibleFromWindow();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.session?.user != null && mounted) {
        _returnToAuthRoot();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _loadingManager.dispose();
    super.dispose();
  }

  bool _isKeyboardVisibleFromWindow() {
    return WidgetsBinding.instance.platformDispatcher.views.any(
      (view) => view.viewInsets.bottom > 0,
    );
  }

  @override
  void didChangeMetrics() {
    final keyboardVisible = _isKeyboardVisibleFromWindow();
    if (keyboardVisible == _keyboardVisible || !mounted) return;
    setState(() {
      _keyboardVisible = keyboardVisible;
    });
  }

  void _returnToAuthRoot() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value);
  }

  bool _isValidPhone(String value) {
    // Remove todos os caracteres não numéricos
    String cleanPhone = value.replaceAll(RegExp(r'[^\d]'), '');
    // Verifica se tem 10 ou 11 dígitos (celular brasileiro)
    return cleanPhone.length == 10 || cleanPhone.length == 11;
  }

  String _formatPhone(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Remove o zero inicial se existir (DDD)
    if (cleanPhone.length == 11 && cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }

    // Adiciona código do país se necessário
    if (cleanPhone.length == 10 || cleanPhone.length == 11) {
      return '+55$cleanPhone';
    }

    return '+$cleanPhone';
  }

  Future<bool> _isEmailAlreadyRegistered(String email) async {
    try {
      final supabase = Supabase.instance.client;

      // Verifica na tabela profiles se existe um usuário com este email
      final response = await supabase
          .from('profiles')
          .select('email')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();

      return response != null;
    } catch (e) {
      // Se a tabela profiles não existir ou houver erro,
      // assume que não há duplicação (para não bloquear cadastros)
      debugPrint('Erro ao verificar email: $e');
      return false;
    }
  }

  Future<bool> _isPhoneAlreadyRegistered(String phone) async {
    try {
      final supabase = Supabase.instance.client;
      final formattedPhone = _formatPhone(phone);

      // Verifica na tabela profiles se existe um usuário com este telefone
      final response = await supabase
          .from('profiles')
          .select('phone')
          .eq('phone', formattedPhone)
          .maybeSingle();

      return response != null;
    } catch (e) {
      // Se a tabela profiles não existir ou houver erro,
      // assume que não há duplicação (para não bloquear cadastros)
      debugPrint('Erro ao verificar telefone: $e');
      return false;
    }
  }

  Future<void> _signUp() async {
    if (_loadingManager.isLoading('register')) return;
    if (!_formKey.currentState!.validate()) return;

    _loadingManager.setLoading('register', true);

    try {
      final supabase = Supabase.instance.client;
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      // Validar se email já está cadastrado
      if (await _isEmailAlreadyRegistered(email)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este email já está cadastrado. Tente fazer login ou use outro email.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        _loadingManager.setLoading('register', false);
        return;
      }

      // Validar se telefone já está cadastrado
      if (await _isPhoneAlreadyRegistered(phone)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este telefone já está cadastrado. Tente fazer login ou use outro número.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        _loadingManager.setLoading('register', false);
        return;
      }

      final formattedPhone = _formatPhone(phone);
      final userMetadata = {
        'name': name,
        'full_name': name,
        'phone': formattedPhone,
      };

      final response = await _createAccount(
        supabase: supabase,
        email: email,
        password: password,
        userMetadata: userMetadata,
      );

      if (_isMaskedSignupResponse(response)) {
        throw const AuthException(
          'O Supabase não confirmou a criação da conta.',
          code: 'signup_masked_response',
        );
      }

      final createdUser = response.user;
      if (createdUser == null) {
        throw const AuthException(
          'O Supabase não confirmou a criação do usuário. Tente novamente.',
          code: 'signup_failed',
        );
      }

      debugPrint(
        '✅ Cadastro Auth criado no Supabase ${SupabaseConfig.projectRef}: ${createdUser.id}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.session == null
                  ? 'Cadastro criado. Enviamos um link de confirmação para seu e-mail.'
                  : 'Cadastro realizado com sucesso!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        if (response.session != null) {
          _returnToAuthRoot();
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => _ConfirmEmailDialog(
              email: email,
              onDone: () {
                Navigator.of(context).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            ),
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorMessages.fromAuthException(error)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorMessages.fromObject(error)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        _loadingManager.setLoading('register', false);
      }
    }
  }

  Future<AuthResponse> _createAccount({
    required SupabaseClient supabase,
    required String email,
    required String password,
    required Map<String, String> userMetadata,
  }) async {
    debugPrint(
      '🔐 Criando cadastro no Supabase ${SupabaseConfig.projectRef}...',
    );
    return supabase.auth.signUp(
      email: email,
      password: password,
      data: userMetadata,
      emailRedirectTo: 'carrodasdelicias://auth-callback',
    );
  }

  bool _isMaskedSignupResponse(AuthResponse response) {
    if (response.session != null) return false;
    final identities = response.user?.identities;
    return identities != null && identities.isEmpty;
  }

  Future<void> _signUpWithGoogle() async {
    if (_loadingManager.isLoading('google_register')) return;
    _loadingManager.setLoading('google_register', true);

    try {
      final result = await SocialAuthService.signInWithGoogle();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.openedExternalBrowser
                  ? 'Conclua o cadastro na janela segura do Google.'
                  : 'Cadastro com Google realizado.',
            ),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorMessages.fromAuthException(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorMessages.fromObject(error)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        _loadingManager.setLoading('google_register', false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final keyboardVisible = _keyboardVisible;
    final isCompact = screenWidth < 380;
    final horizontalPadding = screenWidth < 360 ? 16.0 : 24.0;

    return BaseScreen(
      title: 'Cadastro',
      useSafeArea: !keyboardVisible,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentMaxWidth = constraints.maxWidth > 420
              ? 420.0
              : constraints.maxWidth;
          final logoHeight = keyboardVisible ? 0.0 : (isCompact ? 88.0 : 100.0);
          final titleFontSize = isCompact ? 28.0 : 32.0;
          final subtitleFontSize = isCompact ? 15.0 : 16.0;
          final gapAfterLogo = keyboardVisible
              ? 0.0
              : (isCompact ? 20.0 : 24.0);
          final gapAfterSubtitle = keyboardVisible
              ? 12.0
              : (isCompact ? 12.0 : 16.0);
          final fieldGap = keyboardVisible ? 8.0 : (isCompact ? 8.0 : 10.0);
          final beforeButtonsGap = keyboardVisible
              ? 12.0
              : (isCompact ? 12.0 : 16.0);
          final betweenButtonsGap = keyboardVisible
              ? 8.0
              : (isCompact ? 8.0 : 10.0);
          final minContentHeight = keyboardVisible
              ? 0.0
              : constraints.maxHeight;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minContentHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Column(
                    mainAxisAlignment: keyboardVisible
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!keyboardVisible) ...[
                        Center(
                          child: Image.asset(
                            'assets/icons/Icon.png',
                            height: logoHeight,
                            fit: BoxFit.contain,
                          ),
                        ),
                        SizedBox(height: gapAfterLogo),
                        // Título
                        Text(
                          'Criar conta',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontSize: titleFontSize, height: 1.15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Preencha seus dados para continuar',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.grey[600],
                                fontSize: subtitleFontSize,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: gapAfterSubtitle),
                      ],

                      // Formulário
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Campo Nome
                            AnimatedTextField(
                              key: const Key('register_name_field'),
                              controller: _nameController,
                              labelText: 'Nome completo',
                              hintText: 'Digite seu nome completo',
                              prefixIcon: Icons.person_outline,
                              keyboardType: TextInputType.name,
                              textCapitalization: TextCapitalization.words,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Por favor, digite seu nome';
                                }
                                if (value.trim().length < 2) {
                                  return 'Nome deve ter pelo menos 2 caracteres';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldGap),

                            // Campo Celular/WhatsApp
                            AnimatedTextField(
                              key: const Key('register_phone_field'),
                              controller: _phoneController,
                              labelText: 'Celular/WhatsApp',
                              hintText: '(11) 99999-9999',
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [PhoneInputFormatter()],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite seu celular';
                                }
                                if (!_isValidPhone(value)) {
                                  return 'Digite um número de celular válido';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldGap),

                            // Campo Email
                            TextFormField(
                              key: const Key('register_email_field'),
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'Digite seu email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite seu email';
                                }
                                if (!_isValidEmail(value)) {
                                  return 'Digite um email válido';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldGap),

                            // Campo Senha
                            DynamicPasswordField(
                              controller: _passwordController,
                              labelText: 'Senha',
                              hintText: 'Digite sua senha',
                              uniqueId: 'register_password',
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite sua senha';
                                }
                                if (value.length < 6) {
                                  return 'A senha deve ter pelo menos 6 caracteres';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: fieldGap),

                            // Campo Confirmar Senha
                            DynamicPasswordField(
                              controller: _confirmPasswordController,
                              labelText: 'Confirmar senha',
                              hintText: 'Digite sua senha novamente',
                              uniqueId: 'register_confirm_password',
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, confirme sua senha';
                                }
                                if (value != _passwordController.text) {
                                  return 'As senhas não coincidem';
                                }
                                return null;
                              },
                            ),

                            SizedBox(height: beforeButtonsGap),

                            // Botão Cadastrar
                            DynamicLoadingButton(
                              loadingManager: _loadingManager,
                              loadingKey: 'register',
                              text: 'Cadastrar',
                              onPressed: _signUp,
                              icon: Icons.person_add,
                            ),
                            SizedBox(height: betweenButtonsGap),

                            GoogleAuthButton(
                              loadingManager: _loadingManager,
                              loadingKey: 'google_register',
                              text: 'Cadastrar com Google',
                              onPressed: _signUpWithGoogle,
                            ),
                            SizedBox(height: betweenButtonsGap),

                            // Link para Login
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                Text(
                                  'Já tem uma conta?',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text(
                                    'Entre aqui',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

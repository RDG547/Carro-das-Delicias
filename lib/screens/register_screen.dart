import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_auth_service.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/dynamic_password_field.dart';
import '../widgets/google_auth_button.dart';
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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loadingManager = LoadingManager();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
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
    _authSubscription?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _loadingManager.dispose();
    super.dispose();
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
        'role': 'client',
      };

      // Cadastro no Supabase Auth
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: userMetadata,
      );

      if (response.user != null) {
        // O banco já tenta criar o perfil via trigger; o upsert mantém os dados sincronizados.
        try {
          await supabase.from('profiles').upsert({
            'id': response.user!.id,
            'name': name,
            'phone': formattedPhone,
            'email': email,
            'role': 'client',
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id');
        } catch (e) {
          debugPrint('Erro ao salvar perfil: $e');
        }

        if (mounted) {
          // Mostrar mensagem de sucesso
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cadastro realizado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );

          // Navegar para a tela home ou aguardar confirmação de email
          if (response.session != null) {
            _returnToAuthRoot();
          } else {
            // Se precisar confirmar email
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Confirme seu email'),
                content: const Text(
                  'Um link de confirmação foi enviado para seu email. '
                  'Por favor, confirme seu email antes de fazer login.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        String message = error.message;

        // Personalizar mensagens para casos específicos
        if (message.toLowerCase().contains('email') &&
            (message.toLowerCase().contains('already') ||
                message.toLowerCase().contains('exists'))) {
          message =
              'Este email já está cadastrado. Tente fazer login ou use outro email.';
        } else if (message.toLowerCase().contains('password')) {
          message = 'A senha deve ter pelo menos 6 caracteres.';
        } else if (message.toLowerCase().contains('saving new user') ||
            message.toLowerCase().contains('unexpected_failure')) {
          message =
              'Não foi possível concluir o cadastro por uma configuração do servidor. '
              'A correção do Supabase já foi preparada no projeto.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro inesperado: $error'),
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

  Future<void> _signUpWithGoogle() async {
    _loadingManager.setLoading('google_register', true);

    try {
      await SocialAuthService.signInWithGoogle();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Continue o cadastro na janela do Google.'),
            backgroundColor: Colors.black,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar cadastro com Google: $error'),
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
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
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

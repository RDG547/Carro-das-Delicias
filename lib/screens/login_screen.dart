import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_auth_service.dart';
import '../widgets/base_screen.dart';
import '../widgets/dynamic_password_field.dart';
import '../widgets/google_auth_button.dart';
import '../utils/loading_manager.dart';
import 'register_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailOrPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _loadingManager = LoadingManager();

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _loadingManager.dispose();
    super.dispose();
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

  Future<void> _signInAsGuest() async {
    _loadingManager.setLoading('guest_login', true);

    try {
      // Simula um pequeno delay para mostrar o loading
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        // Navega para home com modo visitante
        BaseScreen.pushReplacement(
          context,
          const MainScreen(isGuestMode: true),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao entrar como visitante: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        _loadingManager.setLoading('guest_login', false);
      }
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    _loadingManager.setLoading('email_login', true);

    try {
      final supabase = Supabase.instance.client;
      final emailOrPhone = _emailOrPhoneController.text.trim();
      final password = _passwordController.text;

      // Adiciona timeout para evitar carregamento infinito
      final loginFuture = _performLogin(supabase, emailOrPhone, password);
      final response = await loginFuture.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout na autenticação. Tente novamente.');
        },
      );

      if (response.user != null && mounted) {
        // Login bem-sucedido - mostrar mensagem e navegar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login realizado com sucesso!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        // Pequeno delay para mostrar a mensagem
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
        return; // Sai da função sem parar o loading aqui
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
            content: Text('Erro inesperado: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    // Só para o loading se chegou até aqui (erro ou login inválido)
    if (mounted) {
      _loadingManager.setLoading('email_login', false);
    }
  }

  Future<void> _signInWithGoogle() async {
    _loadingManager.setLoading('google_login', true);

    try {
      await SocialAuthService.signInWithGoogle();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Continue o login na janela do Google.'),
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
            content: Text('Erro ao iniciar login com Google: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        _loadingManager.setLoading('google_login', false);
      }
    }
  }

  Future<AuthResponse> _performLogin(
    SupabaseClient supabase,
    String emailOrPhone,
    String password,
  ) async {
    if (_isValidEmail(emailOrPhone)) {
      // Login com email
      return await supabase.auth.signInWithPassword(
        email: emailOrPhone,
        password: password,
      );
    } else {
      // Login com telefone
      String cleanPhone = emailOrPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanPhone.length == 11 && cleanPhone.startsWith('0')) {
        cleanPhone = cleanPhone.substring(1);
      }
      if (cleanPhone.length == 10) {
        cleanPhone = '55$cleanPhone'; // Adiciona código do Brasil
      } else if (cleanPhone.length == 11) {
        cleanPhone = '55$cleanPhone';
      }

      return await supabase.auth.signInWithPassword(
        phone: '+$cleanPhone',
        password: password,
      );
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
      title: 'Login',
      showAppBar: true,
      showBackButton: false,
      useSafeArea: !keyboardVisible,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        keyboardVisible ? 0.0 : 8.0,
        horizontalPadding,
        keyboardVisible ? 0.0 : 24.0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentMaxWidth = constraints.maxWidth > 420
              ? 420.0
              : constraints.maxWidth;
          final logoHeight = keyboardVisible
              ? (isCompact ? 72.0 : 80.0)
              : (isCompact ? 88.0 : 100.0);
          final titleFontSize = keyboardVisible
              ? (isCompact ? 24.0 : 26.0)
              : (isCompact ? 28.0 : 32.0);
          final subtitleFontSize = keyboardVisible
              ? 14.0
              : (isCompact ? 15.0 : 16.0);
          final gapAfterLogo = keyboardVisible
              ? 16.0
              : (isCompact ? 20.0 : 24.0);
          final gapAfterSubtitle = keyboardVisible
              ? 24.0
              : (isCompact ? 36.0 : 48.0);
          final fieldGap = keyboardVisible ? 12.0 : (isCompact ? 14.0 : 16.0);
          final beforeButtonsGap = keyboardVisible
              ? 18.0
              : (isCompact ? 20.0 : 24.0);
          final betweenButtonsGap = keyboardVisible
              ? 12.0
              : (isCompact ? 14.0 : 16.0);
          final outerVerticalPadding = keyboardVisible
              ? 0.0
              : (isCompact ? 16.0 : 24.0);
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
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.symmetric(
                      vertical: outerVerticalPadding,
                    ),
                    child: Column(
                      mainAxisAlignment: keyboardVisible
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/icons/Icon.png',
                            height: logoHeight,
                            fit: BoxFit.contain,
                          ),
                        ),
                        SizedBox(height: gapAfterLogo),
                        // Logo/Título
                        Text(
                          'Carro das\nDelícias',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontSize: titleFontSize, height: 1.15),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Entre na sua conta',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.grey[600],
                                fontSize: subtitleFontSize,
                              ),
                          textAlign: TextAlign.center,
                        ),

                        SizedBox(height: gapAfterSubtitle),

                        // Formulário
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              // Campo Email ou Telefone
                              TextFormField(
                                key: const Key('login_email_phone_field'),
                                controller: _emailOrPhoneController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Email ou Celular',
                                  hintText:
                                      'Digite seu email ou número de celular',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite seu email ou celular';
                                  }
                                  if (!_isValidEmail(value) &&
                                      !_isValidPhone(value)) {
                                    return 'Digite um email válido ou celular (10-11 dígitos)';
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
                                uniqueId: 'login',
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

                              SizedBox(height: beforeButtonsGap),

                              // Botão Entrar
                              DynamicLoadingButton(
                                loadingManager: _loadingManager,
                                loadingKey: 'email_login',
                                text: 'Entrar',
                                onPressed: _signIn,
                                icon: Icons.login,
                              ),

                              SizedBox(height: betweenButtonsGap),

                              GoogleAuthButton(
                                loadingManager: _loadingManager,
                                loadingKey: 'google_login',
                                text: 'Continuar com Google',
                                onPressed: _signInWithGoogle,
                              ),

                              SizedBox(height: betweenButtonsGap),

                              // Botão Entrar como Visitante
                              ListenableBuilder(
                                listenable: _loadingManager,
                                builder: (context, child) {
                                  final isGuestLoading = _loadingManager
                                      .isLoading('guest_login');
                                  final isAnyLoading =
                                      _loadingManager.hasAnyLoading;

                                  return SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: isAnyLoading
                                          ? null
                                          : _signInAsGuest,
                                      icon: isGuestLoading
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.grey,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.visibility,
                                              color: Colors.grey,
                                            ),
                                      label: Text(
                                        isGuestLoading
                                            ? 'Entrando...'
                                            : 'Entrar como Visitante',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Colors.grey,
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          vertical: 14,
                                          horizontal: isCompact ? 16 : 24,
                                        ),
                                        minimumSize: const Size.fromHeight(54),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              SizedBox(height: betweenButtonsGap),

                              // Link para Cadastro
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    'Não tem uma conta?',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      BaseScreen.push(
                                        context,
                                        const RegisterScreen(),
                                      );
                                    },
                                    child: const Text(
                                      'Cadastre-se',
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
            ),
          );
        },
      ),
    );
  }
}

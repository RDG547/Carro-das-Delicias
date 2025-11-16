import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/dynamic_password_field.dart';
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
    return BaseScreen(
      title: 'Login',
      showAppBar: true,
      showBackButton: false,
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40), // Reduzido de 60 para 40
            // Logo/Título
            Text(
              'Carro das\nDelícias',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontSize: 32, height: 1.2),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Entre na sua conta',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 48),

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
                      hintText: 'Digite seu email ou número de celular',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, digite seu email ou celular';
                      }
                      if (!_isValidEmail(value) && !_isValidPhone(value)) {
                        return 'Digite um email válido ou celular (10-11 dígitos)';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

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

                  const SizedBox(height: 24),

                  // Botão Entrar
                  DynamicLoadingButton(
                    loadingManager: _loadingManager,
                    loadingKey: 'email_login',
                    text: 'Entrar',
                    onPressed: _signIn,
                    icon: Icons.login,
                  ),

                  const SizedBox(height: 16),

                  // Botão Entrar como Visitante
                  LoadingBuilder(
                    loadingManager: _loadingManager,
                    loadingKey: 'guest_login',
                    builder: (context, isGuestLoading) {
                      return LoadingBuilder(
                        loadingManager: _loadingManager,
                        loadingKey: 'email_login',
                        builder: (context, isEmailLoading) {
                          final isAnyLoading = isGuestLoading || isEmailLoading;
                          return OutlinedButton.icon(
                            onPressed: isAnyLoading ? null : _signInAsGuest,
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
                              style: const TextStyle(color: Colors.grey),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.grey),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Link para Cadastro
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Não tem uma conta? ',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: () {
                          BaseScreen.push(context, const RegisterScreen());
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
    );
  }
}

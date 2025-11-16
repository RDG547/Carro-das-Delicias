import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/dynamic_password_field.dart';
import '../utils/loading_manager.dart';
import 'login_screen.dart';
import 'home_screen.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

      // Cadastro no Supabase Auth
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'phone': formattedPhone},
      );

      if (response.user != null) {
        // Salvar dados adicionais na tabela de perfil se necessário
        try {
          await supabase.from('profiles').insert({
            'id': response.user!.id,
            'name': name,
            'phone': formattedPhone,
            'email': email,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          // Se a tabela profiles não existir, apenas continue
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
            BaseScreen.pushReplacement(context, const HomeScreen());
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
                      BaseScreen.pushReplacement(context, const LoginScreen());
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

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Cadastro',
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // Título
            Text(
              'Criar conta',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontSize: 28),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Preencha seus dados para continuar',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

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

                  const SizedBox(height: 16),

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

                  const SizedBox(height: 16),

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

                  const SizedBox(height: 16),

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

                  const SizedBox(height: 16),

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

                  const SizedBox(height: 32),

                  // Botão Cadastrar
                  DynamicLoadingButton(
                    loadingManager: _loadingManager,
                    loadingKey: 'register',
                    text: 'Cadastrar',
                    onPressed: _signUp,
                    icon: Icons.person_add,
                  ),
                  const SizedBox(height: 16),

                  // Link para Login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Já tem uma conta? ',
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
    );
  }
}

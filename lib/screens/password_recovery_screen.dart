import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/auth_error_messages.dart';
import '../widgets/dynamic_password_field.dart';

class AuthEmailLinks {
  static const callback = 'carrodasdelicias://auth-callback';
  static const recovery = callback;
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.recoverySession = false,
    this.changePassword = false,
    this.initialEmail = '',
  });
  final bool recoverySession;
  final bool changePassword;
  final String initialEmail;
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  StreamSubscription<AuthState>? _subscription;
  Timer? _timer;
  bool _sent = false;
  bool _verified = false;
  bool _busy = false;
  int _cooldown = 0;
  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
    _verified = widget.recoverySession || widget.changePassword;
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.passwordRecovery &&
          state.session != null &&
          mounted) {
        setState(() => _verified = true);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    for (final controller in [
      _email,
      _code,
      _currentPassword,
      _password,
      _confirmation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthErrorMessages.fromObject(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      _form.currentState!.validate();
      return;
    }
    await Supabase.instance.client.auth.resetPasswordForEmail(
      _email.text.trim().toLowerCase(),
      redirectTo: AuthEmailLinks.recovery,
    );
    if (!mounted) return;
    setState(() {
      _sent = true;
      _cooldown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  });
  Future<void> _verify() => _run(() async {
    if (!_form.currentState!.validate()) return;
    final result = await Supabase.instance.client.auth.verifyOTP(
      email: _email.text.trim().toLowerCase(),
      token: _code.text.trim(),
      type: OtpType.recovery,
    );
    if (result.session == null) {
      throw const AuthException(
        'Não foi possível validar o código. Solicite um novo email.',
      );
    }
    if (mounted) setState(() => _verified = true);
  });
  Future<void> _save() => _run(() async {
    if (!_form.currentState!.validate()) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null || !_verified) {
      throw const AuthException(
        'A sessão de recuperação expirou. Solicite um novo email.',
      );
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.changePassword) {
      final email = client.auth.currentUser?.email;
      if (email == null) {
        throw const AuthException('Recupere sua senha pelo email da conta.');
      }
      await client.auth.signInWithPassword(
        email: email,
        password: _currentPassword.text,
      );
    }
    await client.auth.updateUser(UserAttributes(password: _password.text));
    if (widget.changePassword) {
      if (navigator.mounted && navigator.canPop()) navigator.pop();
    } else {
      await client.auth.signOut();
      if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    }
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.changePassword
                ? 'Senha alterada com sucesso.'
                : 'Senha alterada. Entre com a nova senha.',
          ),
        ),
      );
    }
  });
  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: Text(widget.changePassword ? 'Alterar senha' : 'Recuperar senha'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _verified
                        ? Icons.lock_reset
                        : Icons.mark_email_read_outlined,
                    size: 64,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _verified
                        ? 'Escolha sua nova senha'
                        : 'Informe o email da sua conta',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_verified) ...[
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      readOnly: _sent,
                      decoration: _decoration('Email', Icons.alternate_email),
                      validator: (value) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Digite um email válido.',
                    ),
                    const SizedBox(height: 16),
                    if (_sent) ...[
                      const Text(
                        'Se houver uma conta com esse email, enviaremos as instruções. Abra o link recebido ou digite o código informado no email. Confira também o spam.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: _decoration(
                          'Código do email',
                          Icons.pin_outlined,
                        ),
                        validator: (value) => (value?.length ?? 0) >= 6
                            ? null
                            : 'Digite o código recebido.',
                      ),
                    ],
                  ] else ...[
                    if (widget.changePassword) ...[
                      DynamicPasswordField(
                        controller: _currentPassword,
                        labelText: 'Senha atual',
                        hintText: 'Digite sua senha atual',
                        uniqueId: 'change_current',
                        validator: (value) => value?.isNotEmpty == true
                            ? null
                            : 'Informe sua senha atual.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    DynamicPasswordField(
                      controller: _password,
                      labelText: 'Nova senha',
                      hintText: 'Use pelo menos 8 caracteres',
                      uniqueId: 'recovery_new',
                      validator: (value) => (value?.length ?? 0) >= 8
                          ? null
                          : 'Use pelo menos 8 caracteres.',
                    ),
                    const SizedBox(height: 16),
                    DynamicPasswordField(
                      controller: _confirmation,
                      labelText: 'Confirmar nova senha',
                      hintText: 'Repita a nova senha',
                      uniqueId: 'recovery_confirm',
                      validator: (value) => value == _password.text
                          ? null
                          : 'As senhas não coincidem.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : (_verified ? _save : (_sent ? _verify : _send)),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset),
                    label: Text(
                      _busy
                          ? 'Aguarde...'
                          : (_verified
                                ? 'Salvar nova senha'
                                : (_sent
                                      ? 'Confirmar código'
                                      : 'Enviar email')),
                    ),
                  ),
                  if (_sent && !_verified)
                    TextButton(
                      onPressed: _busy || _cooldown > 0 ? null : _send,
                      child: Text(
                        _cooldown > 0
                            ? 'Reenviar em ${_cooldown}s'
                            : 'Reenviar email',
                      ),
                    ),
                  if (widget.changePassword)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PasswordRecoveryScreen(
                                  initialEmail:
                                      Supabase
                                          .instance
                                          .client
                                          .auth
                                          .currentUser
                                          ?.email ??
                                      '',
                                ),
                              ),
                            ),
                      child: const Text('Esqueci minha senha atual'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({super.key, required this.email});
  final String email;
  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  final _code = TextEditingController();
  StreamSubscription<AuthState>? _subscription;
  bool _busy = false;
  int _cooldown = 60;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _startCooldown();
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.session?.user.email?.toLowerCase() ==
              widget.email.toLowerCase() &&
          mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  void _startCooldown() {
    _timer?.cancel();
    _cooldown = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _submit({bool resend = false}) async {
    if (_busy) return;
    if (!resend && _code.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o código recebido no email.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (resend) {
        await auth.resend(
          type: OtpType.signup,
          email: widget.email,
          emailRedirectTo: AuthEmailLinks.callback,
        );
        if (mounted) setState(_startCooldown);
      } else {
        await auth.verifyOTP(
          email: widget.email,
          token: _code.text.trim(),
          type: OtpType.signup,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthErrorMessages.fromObject(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confirmar email')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Confira sua caixa de entrada e o spam de ${widget.email}. Abra o link de confirmação ou digite o código recebido.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Código de confirmação',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : () => _submit(),
                  child: Text(_busy ? 'Aguarde...' : 'Confirmar email'),
                ),
                TextButton(
                  onPressed: _busy || _cooldown > 0
                      ? null
                      : () => _submit(resend: true),
                  child: Text(
                    _cooldown > 0
                        ? 'Reenviar em ${_cooldown}s'
                        : 'Reenviar confirmação',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/main_screen.dart';
import 'services/auth_profile_sync_service.dart';
import 'services/notification_service.dart';
import 'services/deep_link_service.dart';
import 'services/order_payment_service.dart';
import 'services/remote_push_service.dart';
import 'services/user_presence_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isPasswordRecovery = false;
  User? _user;
  StreamSubscription<AuthState>? _authSubscription;
  String? _authenticatedServicesUserId;
  Future<void>? _authenticatedServicesFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
    DeepLinkService().onPasswordRecovery = _enterPasswordRecovery;

    // Inicializar deep link service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService().init(context);
      DeepLinkService().checkInitialLink();
    });

    // Escuta mudanças no estado de autenticação
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final newUser = data.session?.user;
      if (data.event == AuthChangeEvent.passwordRecovery &&
          data.session != null) {
        _enterPasswordRecovery();
      }
      if (data.event == AuthChangeEvent.signedOut) _isPasswordRecovery = false;

      if (mounted) {
        setState(() {
          _user = newUser;
          _isLoading = false;
        });

        // Gerenciar listener de notificações baseado no estado de autenticação
        if (newUser != null && !_isPasswordRecovery) {
          unawaited(_startAuthenticatedServices(newUser));
        } else {
          // Usuário fez logout - parar escuta de notificações
          _authenticatedServicesUserId = null;
          _authenticatedServicesFuture = null;
          unawaited(RemotePushService.stop());
          unawaited(UserPresenceService.instance.stop(markOffline: true));
          NotificationService.stopListeningToNotifications();
        }
      }
    });
  }

  void _enterPasswordRecovery() {
    if (!mounted) return;
    setState(() => _isPasswordRecovery = true);
    // A recovery link can arrive while a product or another page is open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = _user;
    if (user == null || _isPasswordRecovery) return;

    if (state == AppLifecycleState.resumed) {
      unawaited(UserPresenceService.instance.start(user));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(UserPresenceService.instance.pause());
    }
  }

  Future<void> _checkAuth() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (mounted) {
        setState(() {
          _user = session?.user;
          _isLoading = false;
        });

        // Se já há um usuário logado, iniciar escuta de notificações
        if (_user != null) {
          unawaited(_startAuthenticatedServices(_user!));
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _user = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startAuthenticatedServices(User user) async {
    if (_authenticatedServicesUserId == user.id &&
        _authenticatedServicesFuture != null) {
      return _authenticatedServicesFuture;
    }

    _authenticatedServicesUserId = user.id;
    _authenticatedServicesFuture = _startAuthenticatedServicesInternal(user);
    return _authenticatedServicesFuture;
  }

  Future<void> _startAuthenticatedServicesInternal(User user) async {
    final supabase = Supabase.instance.client;

    try {
      final profile = await supabase
          .from('profiles')
          .select('is_banned, banned_until')
          .eq('id', user.id)
          .maybeSingle();

      final bannedUntil = DateTime.tryParse(
        profile?['banned_until']?.toString() ?? '',
      );
      final isBanned =
          profile?['is_banned'] == true ||
          (bannedUntil != null && bannedUntil.isAfter(DateTime.now()));

      if (isBanned) {
        await UserPresenceService.instance.stop(markOffline: true);
        await RemotePushService.unregisterCurrentDevice();
        await supabase.auth.signOut();
        if (mounted) {
          setState(() {
            _user = null;
          });
        }
        NotificationService.stopListeningToNotifications();
        return;
      }
    } catch (_) {
      // Colunas de banimento podem não existir até a migration ser aplicada.
    }

    await AuthProfileSyncService.syncCurrentUserProfile();
    unawaited(RemotePushService.registerCurrentDevice(user));
    unawaited(UserPresenceService.instance.start(user));
    unawaited(OrderPaymentService.syncPendingPaymentsForCurrentUser());
    NotificationService.startListeningToNotifications();
    NotificationService.checkPendingNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    // Parar escuta ao destruir o widget
    unawaited(UserPresenceService.instance.stop(markOffline: true));
    unawaited(RemotePushService.stop());
    NotificationService.stopListeningToNotifications();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.black),
              SizedBox(height: 16),
              Text(
                'Carregando...',
                style: TextStyle(color: Colors.black, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_isPasswordRecovery && _user != null) {
      return const PasswordRecoveryScreen(recoverySession: true);
    }
    return _user != null ? const MainScreen() : const LoginScreen();
  }
}

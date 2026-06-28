import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/auth_profile_sync_service.dart';
import 'services/notification_service.dart';
import 'services/deep_link_service.dart';
import 'services/order_payment_service.dart';
import 'services/user_presence_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  User? _user;
  StreamSubscription<AuthState>? _authSubscription;
  String? _authenticatedServicesUserId;
  Future<void>? _authenticatedServicesFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();

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

      if (mounted) {
        setState(() {
          _user = newUser;
          _isLoading = false;
        });

        // Gerenciar listener de notificações baseado no estado de autenticação
        if (newUser != null) {
          unawaited(_startAuthenticatedServices(newUser));
        } else {
          // Usuário fez logout - parar escuta de notificações
          _authenticatedServicesUserId = null;
          _authenticatedServicesFuture = null;
          unawaited(UserPresenceService.instance.stop(markOffline: true));
          NotificationService.stopListeningToNotifications();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = _user;
    if (user == null) return;

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

    return _user != null ? const MainScreen() : const LoginScreen();
  }
}

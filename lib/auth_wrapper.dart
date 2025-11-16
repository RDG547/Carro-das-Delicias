import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/notification_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  User? _user;

  @override
  void initState() {
    super.initState();
    _checkAuth();

    // Escuta mudanças no estado de autenticação
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final newUser = data.session?.user;

      if (mounted) {
        setState(() {
          _user = newUser;
          _isLoading = false;
        });

        // Gerenciar listener de notificações baseado no estado de autenticação
        if (newUser != null) {
          // Usuário fez login - iniciar escuta de notificações
          NotificationService.startListeningToNotifications();
          // Verificar notificações pendentes
          NotificationService.checkPendingNotifications();
        } else {
          // Usuário fez logout - parar escuta de notificações
          NotificationService.stopListeningToNotifications();
        }
      }
    });
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
          NotificationService.startListeningToNotifications();
          // Verificar notificações pendentes ao abrir app
          NotificationService.checkPendingNotifications();
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

  @override
  void dispose() {
    // Parar escuta ao destruir o widget
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

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../widgets/base_screen.dart';
import '../widgets/main_navigation_provider.dart';
import '../screens/login_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/support_legal_screen.dart';
import '../services/cart_service.dart';
import '../services/location_tracking_service.dart';
import '../services/remote_push_service.dart';
import '../services/user_presence_service.dart';
import '../utils/realtime_auth_utils.dart';

// ValueNotifier global para o status da Kombi (compartilhado entre todas instâncias)
final ValueNotifier<bool> kombiOnlineStatus = ValueNotifier<bool>(false);

class AppMenu extends StatefulWidget {
  final bool isGuestMode;
  final bool isAdmin;
  final VoidCallback? onAdminReturn;

  const AppMenu({
    super.key,
    required this.isGuestMode,
    this.isAdmin = false,
    this.onAdminReturn,
  });

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> {
  String? _avatarUrl;
  String? _profileName;
  bool _isLoadingAvatar = false;
  static bool _isListeningToKombi =
      false; // Garante apenas uma subscription ativa
  static StreamSubscription?
  _globalKombiSubscription; // Subscription global compartilhada
  static Timer? _kombiFreshnessTimer;
  static List<Map<String, dynamic>> _lastKombiRows = const [];
  static bool _isRecoveringKombiAuth = false;
  static int _kombiListenerOwners = 0;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🚀 AppMenu - initState chamado, isGuestMode: ${widget.isGuestMode}',
    );
    if (!widget.isGuestMode) {
      _loadUserAvatar();
    }

    // Inicia o stream apenas uma vez globalmente
    _kombiListenerOwners++;
    if (!_isListeningToKombi) {
      _isListeningToKombi = true;
      unawaited(_listenToKombiStatus());
    }

    // Sempre carrega o status inicial da Kombi, mesmo para visitantes.
    unawaited(_checkKombiStatus());
  }

  @override
  void dispose() {
    _kombiListenerOwners = (_kombiListenerOwners - 1).clamp(0, 1 << 30);

    // Cancela a subscription global quando a última instância for destruída
    if (_kombiListenerOwners == 0) {
      _globalKombiSubscription?.cancel();
      _globalKombiSubscription = null;
      _isListeningToKombi = false;
      _kombiFreshnessTimer?.cancel();
      _kombiFreshnessTimer = null;
      debugPrint('🛑 AppMenu - Subscription global cancelada');
    }

    super.dispose();
  }

  Future<void> _listenToKombiStatus() async {
    debugPrint('🎧 AppMenu - _listenToKombiStatus iniciado');
    _globalKombiSubscription?.cancel();
    await RealtimeAuthUtils.syncRealtimeAuthToken(
      source: 'app_menu_kombi_stream',
    );
    if (_kombiListenerOwners == 0) {
      _isListeningToKombi = false;
      return;
    }

    // Escuta mudanças na tabela kombi_location em tempo real via websocket.
    _globalKombiSubscription = Supabase.instance.client
        .from('kombi_location')
        .stream(primaryKey: ['id'])
        .listen(
          (data) {
            final rows = data
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
            _applyKombiStatusRows(rows, source: 'realtime');
          },
          onError: (error) {
            debugPrint('❌ AppMenu - Erro no stream da Kombi: $error');
            unawaited(_handleKombiStreamError(error));
          },
        );
    debugPrint('✅ AppMenu - Stream subscription criado');
  }

  static void _applyKombiStatusRows(
    List<Map<String, dynamic>> rows, {
    required String source,
  }) {
    _lastKombiRows = rows;
    final isOnline = rows.any(LocationTrackingService.isKombiRecentlyOnline);

    if (kombiOnlineStatus.value != isOnline) {
      debugPrint(
        '📡 AppMenu - Kombi ${isOnline ? "ONLINE" : "OFFLINE"} ($source)',
      );
      kombiOnlineStatus.value = isOnline;
    }

    _scheduleKombiFreshnessTimer(rows);
  }

  static void _scheduleKombiFreshnessTimer(List<Map<String, dynamic>> rows) {
    _kombiFreshnessTimer?.cancel();
    _kombiFreshnessTimer = null;

    if (_kombiListenerOwners == 0) return;

    final now = DateTime.now().toUtc();
    DateTime? nextExpiry;

    for (final row in rows) {
      if (row['is_online'] != true) continue;

      final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
      if (updatedAt == null) continue;

      final expiry = updatedAt.toUtc().add(
        LocationTrackingService.onlineFreshness,
      );
      if (expiry.isBefore(now) || expiry.isAtSameMomentAs(now)) continue;

      if (nextExpiry == null || expiry.isBefore(nextExpiry)) {
        nextExpiry = expiry;
      }
    }

    if (nextExpiry == null) return;

    final delay = nextExpiry.difference(now) + const Duration(seconds: 1);
    _kombiFreshnessTimer = Timer(delay, () {
      if (_kombiListenerOwners > 0) {
        _applyKombiStatusRows(_lastKombiRows, source: 'freshness_timeout');
      }
    });
  }

  Future<void> _handleKombiStreamError(Object? error) async {
    if (_isRecoveringKombiAuth || _kombiListenerOwners == 0) {
      return;
    }

    _isRecoveringKombiAuth = true;
    try {
      final recovered = await RealtimeAuthUtils.recoverFromAuthError(
        error: error,
        source: 'app_menu_kombi_stream',
        onRecovered: () async {
          await _listenToKombiStatus();
          await _checkKombiStatus();
        },
      );

      if (!recovered && RealtimeAuthUtils.isExpiredJwtError(error)) {
        debugPrint(
          '⚠️ AppMenu - Não foi possível recuperar o stream da Kombi após expiração do token',
        );
      }
    } finally {
      _isRecoveringKombiAuth = false;
    }
  }

  // Verifica se o erro é de conexão de rede
  static bool _isConnectionError(dynamic error) {
    if (error == null) return false;
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('no route to host') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timed out') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('errno = 113') ||
        errorString.contains('errno = 111') ||
        errorString.contains('clientexception');
  }

  static Future<void> _checkKombiStatus() async {
    try {
      // Verifica se existe pelo menos uma Kombi realmente online.
      final response = await Supabase.instance.client
          .from('kombi_location')
          .select('id, is_online, updated_at')
          .eq('is_online', true)
          .order('updated_at', ascending: false)
          .limit(5);

      _applyKombiStatusRows(
        List<Map<String, dynamic>>.from(response),
        source: 'initial_check',
      );
    } catch (e) {
      if (_isConnectionError(e)) {
        debugPrint('⚠️ AppMenu - Sem conexão para verificar status da Kombi');
        // Não mostrar erro, apenas manter status atual (offline)
        kombiOnlineStatus.value = false;
      } else {
        debugPrint('❌ AppMenu - Erro ao verificar status da Kombi: $e');
      }
    }
  }

  Widget _buildSimpleMenuItem({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
        ],
      ),
    );
  }

  Future<void> _loadUserAvatar() async {
    if (_isLoadingAvatar) return;

    setState(() => _isLoadingAvatar = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('name, avatar_url')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted && response != null) {
          setState(() {
            _avatarUrl = response['avatar_url']?.toString();
            final profileName = response['name']?.toString().trim();
            _profileName = profileName?.isNotEmpty == true ? profileName : null;
            _isLoadingAvatar = false;
          });
        } else if (mounted) {
          setState(() => _isLoadingAvatar = false);
        }
      } else if (mounted) {
        setState(() => _isLoadingAvatar = false);
      }
    } catch (e) {
      if (_isConnectionError(e)) {
        debugPrint('⚠️ AppMenu - Sem conexão para carregar avatar');
      } else {
        debugPrint('Erro ao carregar avatar: $e');
      }
      if (mounted) {
        setState(() => _isLoadingAvatar = false);
      }
    }
  }

  String _getUserDisplayName(User? user) {
    if (user == null) return 'Usuário';

    String? fullName = _profileName;
    fullName ??= (user.userMetadata?['full_name'] ?? user.userMetadata?['name'])
        ?.toString()
        .trim();
    if (fullName != null && fullName.isNotEmpty) {
      // Retorna apenas o primeiro nome
      return fullName.split(' ').first;
    }

    // Se não tem nome no metadata, pega o email e usa a parte antes do @
    String? email = user.email;
    if (email != null && email.isNotEmpty) {
      String emailName = email.split('@').first;
      // Capitaliza a primeira letra
      return emailName[0].toUpperCase() + emailName.substring(1).toLowerCase();
    }

    return 'Usuário';
  }

  void _signOut(BuildContext context) async {
    try {
      await UserPresenceService.instance.stop(markOffline: true);
      await RemotePushService.unregisterCurrentDevice();
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        // Voltar para a tela inicial (AuthWrapper vai redirecionar para LoginScreen)
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer logout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAvatar({double radius = 18, double fontSize = 16}) {
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(_avatarUrl!),
        backgroundColor: Colors.grey[300],
        onBackgroundImageError: (_, _) {
          // Se houver erro ao carregar a imagem, vai mostrar a inicial
        },
        child: Container(), // Necessário para o error handler funcionar
      );
    }

    // Fallback visual padronizado do perfil.
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[100],
      child: ClipOval(
        child: Image.asset(
          'assets/icons/appbar/profile.png',
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            widget.isGuestMode ? Icons.visibility_rounded : Icons.person,
            size: radius,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return PopupMenuButton<String>(
      icon: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.isGuestMode ? Colors.grey[400]! : Colors.black,
            width: 2,
          ),
        ),
        child: _buildAvatar(),
      ),
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      onOpened: () {
        if (!widget.isGuestMode) {
          unawaited(_loadUserAvatar());
        }
      },
      onSelected: (value) {
        if (value == 'logout') {
          _signOut(context);
        } else if (value == 'login' && widget.isGuestMode) {
          BaseScreen.pushReplacement(context, const LoginScreen());
        } else if (value == 'cart') {
          // Navega para o carrinho usando o PageView do MainScreen
          final provider = MainNavigationProvider.of(context);
          if (provider?.navigateToPageDirect != null) {
            // Navega diretamente para índice 4 do PageView (Carrinho)
            provider!.navigateToPageDirect!(4);
          } else {
            // Fallback: se não houver provider (ex: telas Admin/Tracking),
            // volta para MainScreen e depois navega pro carrinho
            Navigator.of(context).popUntil((route) => route.isFirst);
            // Aguarda um frame para garantir que o MainScreen está montado
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newProvider = MainNavigationProvider.of(context);
              if (newProvider?.navigateToPageDirect != null) {
                newProvider!.navigateToPageDirect!(4);
              }
            });
          }
        } else if (value == 'profile') {
          // Navega para o perfil usando o PageView do MainScreen
          final provider = MainNavigationProvider.of(context);
          if (provider?.navigateToPage != null) {
            // Navega para índice 4 da navbar (Perfil)
            provider!.navigateToPage!(4);
          } else {
            // Fallback: se não houver provider, usa push normal
            BaseScreen.push(
              context,
              ProfileScreen(isGuestMode: widget.isGuestMode),
            );
          }
        } else if (value == 'admin' && widget.isAdmin) {
          // Navega para a tela de administração usando o PageView do MainScreen
          final provider = MainNavigationProvider.of(context);
          if (provider?.navigateToPageDirect != null) {
            // Navega diretamente para índice 6 do PageView (Admin)
            provider!.navigateToPageDirect!(6);
          } else {
            // Fallback: se não houver provider,
            // volta para MainScreen e depois navega pro admin
            Navigator.of(context).popUntil((route) => route.isFirst);
            // Aguarda um frame para garantir que o MainScreen está montado
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newProvider = MainNavigationProvider.of(context);
              if (newProvider?.navigateToPageDirect != null) {
                newProvider!.navigateToPageDirect!(6);
              }
            });
          }
        } else if (value == 'tracking') {
          // Navega para a tela de rastreamento usando o PageView do MainScreen
          final provider = MainNavigationProvider.of(context);
          if (provider?.navigateToPageDirect != null) {
            // Navega diretamente para índice 5 do PageView (Rastrear Kombi)
            provider!.navigateToPageDirect!(5);
          } else {
            // Fallback: se não houver provider (ex: tela Admin),
            // volta para MainScreen e depois navega pro tracking
            Navigator.of(context).popUntil((route) => route.isFirst);
            // Aguarda um frame para garantir que o MainScreen está montado
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final newProvider = MainNavigationProvider.of(context);
              if (newProvider?.navigateToPageDirect != null) {
                newProvider!.navigateToPageDirect!(5);
              }
            });
          }
        } else if (value == 'support_legal') {
          final provider = MainNavigationProvider.of(context);
          if (provider?.navigateToPageDirect != null) {
            // Navega diretamente para índice 7 do PageView (Ajuda e Políticas)
            provider!.navigateToPageDirect!(7);
          } else {
            BaseScreen.push(context, const SupportLegalScreen());
          }
        }
      },
      itemBuilder: (context) => [
        // Header do menu
        PopupMenuItem(
          enabled: false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _buildAvatar(radius: 22.5, fontSize: 18),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isGuestMode
                            ? 'Visitante'
                            : _getUserDisplayName(user),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (!widget.isGuestMode)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isAdmin
                                ? Colors.red[100]
                                : Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.isAdmin ? 'Administrador' : 'Cliente',
                            style: TextStyle(
                              color: widget.isAdmin
                                  ? Colors.red[700]
                                  : Colors.blue[700],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (widget.isGuestMode)
                        Text(
                          'Modo de visualização',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Opção Carrinho
        if (!widget.isGuestMode)
          PopupMenuItem(
            value: 'cart',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.shopping_cart_outlined,
                          color: Colors.orange[700],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: CartService(),
                        builder: (context, child) {
                          final itemCount = CartService().totalItems;
                          if (itemCount == 0) {
                            return const SizedBox.shrink();
                          }

                          return Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '$itemCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Carrinho',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

        // Opção Perfil
        PopupMenuItem(
          value: 'profile',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.isGuestMode
                        ? Icons.visibility_rounded
                        : Icons.person_rounded,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.isGuestMode ? 'Visualizar Perfil' : 'Meu Perfil',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),

        // Opção Admin (só para admins)
        if (!widget.isGuestMode && widget.isAdmin)
          PopupMenuItem(
            value: 'admin',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_sharp,
                      color: Colors.purple[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Administração',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

        // Opção Rastrear Kombi (sempre visível)
        PopupMenuItem(
          value: 'tracking',
          child: ValueListenableBuilder<bool>(
            valueListenable: kombiOnlineStatus,
            builder: (context, isKombiOnlineLocal, _) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isKombiOnlineLocal
                            ? Colors.green[50]
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: isKombiOnlineLocal
                            ? Colors.green[700]
                            : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Rastrear Kombi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isKombiOnlineLocal
                            ? Colors.green[100]
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: isKombiOnlineLocal
                                ? Colors.green[700]
                                : Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isKombiOnlineLocal ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isKombiOnlineLocal
                                  ? Colors.green[700]
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        PopupMenuItem(
          value: 'support_legal',
          child: _buildSimpleMenuItem(
            icon: Icons.policy_outlined,
            color: Colors.teal,
            label: 'Ajuda e Políticas',
          ),
        ),

        const PopupMenuDivider(),

        // Opção Logout/Login
        PopupMenuItem(
          value: widget.isGuestMode ? 'login' : 'logout',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.isGuestMode
                        ? Colors.green[50]
                        : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.isGuestMode ? Icons.login_sharp : Icons.logout_sharp,
                    color: widget.isGuestMode
                        ? Colors.green[700]
                        : Colors.red[700],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.isGuestMode ? 'Fazer Login' : 'Sair',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

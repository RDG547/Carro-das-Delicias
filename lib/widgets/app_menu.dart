import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../widgets/base_screen.dart';
import '../widgets/main_navigation_provider.dart';
import '../screens/login_screen.dart';
import '../screens/profile_screen.dart';
import '../services/cart_service.dart';

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
  bool _isLoadingAvatar = false;
  static bool _isListeningToKombi =
      false; // Garante apenas uma subscription ativa
  static StreamSubscription?
  _globalKombiSubscription; // Subscription global compartilhada

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🚀 AppMenu - initState chamado, isGuestMode: ${widget.isGuestMode}',
    );
    if (!widget.isGuestMode) {
      _loadUserAvatar();
    }

    // Sempre carrega o status da Kombi, mesmo para visitantes
    _checkKombiStatus();

    // Inicia o stream apenas uma vez globalmente
    if (!_isListeningToKombi) {
      _isListeningToKombi = true;
      _listenToKombiStatus();
    }
  }

  @override
  void dispose() {
    // Cancela a subscription global quando a última instância for destruída
    if (_isListeningToKombi && _globalKombiSubscription != null) {
      _globalKombiSubscription?.cancel();
      _globalKombiSubscription = null;
      _isListeningToKombi = false;
      debugPrint('🛑 AppMenu - Subscription global cancelada');
    }

    super.dispose();
  }

  void _listenToKombiStatus() {
    debugPrint('🎧 AppMenu - _listenToKombiStatus iniciado');
    // Escuta mudanças na tabela kombi_location em tempo real
    _globalKombiSubscription = Supabase.instance.client
        .from('kombi_location')
        .stream(primaryKey: ['id'])
        .listen((data) {
          debugPrint('🔍 AppMenu - Stream update recebido');
          debugPrint('📦 AppMenu - Data: $data');
          debugPrint('📏 AppMenu - Data length: ${data.length}');

          if (data.isEmpty) {
            debugPrint(
              '⚠️ AppMenu - Data vazio, mantendo status atual: ${kombiOnlineStatus.value}',
            );
          } else {
            final isOnline = data.first['is_online'] == true;
            debugPrint(
              '📡 AppMenu - Status atualizado: ${isOnline ? "ONLINE" : "OFFLINE"}',
            );
            kombiOnlineStatus.value =
                isOnline; // Atualiza o ValueNotifier global
          }
        });
    debugPrint('✅ AppMenu - Stream subscription criado');
  }

  Future<void> _checkKombiStatus() async {
    debugPrint('🔎 AppMenu - _checkKombiStatus iniciado');
    try {
      // Verifica se existe algum registro de localização (online ou offline)
      final response = await Supabase.instance.client
          .from('kombi_location')
          .select()
          .limit(1)
          .maybeSingle();

      debugPrint('🔍 AppMenu - Check inicial response: $response');

      if (response != null) {
        final isOnline = response['is_online'] == true;
        debugPrint(
          '📊 AppMenu - Status inicial: ${isOnline ? "ONLINE" : "OFFLINE"}',
        );
        kombiOnlineStatus.value = isOnline; // Atualiza o ValueNotifier global
      } else {
        debugPrint('⚠️ AppMenu - Response null');
      }
    } catch (e) {
      debugPrint('❌ AppMenu - Erro ao verificar status da Kombi: $e');
    }
  }

  Future<void> _loadUserAvatar() async {
    if (_isLoadingAvatar) return;

    setState(() => _isLoadingAvatar = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('avatar_url')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted && response != null) {
          setState(() {
            _avatarUrl = response['avatar_url'];
            _isLoadingAvatar = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar avatar: $e');
      if (mounted) {
        setState(() => _isLoadingAvatar = false);
      }
    }
  }

  String _getUserDisplayName(User? user) {
    if (user == null) return 'Usuário';

    // Tenta pegar o nome do metadata primeiro
    String? fullName = user.userMetadata?['name'] as String?;
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
    final user = Supabase.instance.client.auth.currentUser;

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

    // Fallback: mostrar inicial do nome
    return CircleAvatar(
      radius: radius,
      backgroundColor: widget.isGuestMode ? Colors.grey[200] : Colors.black,
      child: Text(
        widget.isGuestMode
            ? 'V'
            : _getUserDisplayName(user).substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: widget.isGuestMode ? Colors.grey[600] : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
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

        const PopupMenuDivider(),

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
                        ? Icons.visibility_outlined
                        : Icons.person_outline,
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
                      Icons.admin_panel_settings_outlined,
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
              debugPrint(
                '🔄 Rastrear Kombi - Rebuild local, status: $isKombiOnlineLocal',
              );
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
                        Icons.location_on,
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
                    widget.isGuestMode ? Icons.login : Icons.logout,
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

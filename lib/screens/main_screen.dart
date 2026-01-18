import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/main_navigation_provider.dart';
import '../providers/admin_status_provider.dart';
import 'home_screen.dart';
import 'descontos_screen.dart';
import 'cart_screen.dart';
import 'pedidos_screen.dart';
import 'profile_screen.dart';
import 'kombi_tracking_screen.dart';
import 'admin_screen.dart';
import '../widgets/notification_bell_navbar.dart';

class MainScreen extends StatefulWidget {
  final bool isGuestMode;

  const MainScreen({super.key, this.isGuestMode = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late PageController _pageController;
  bool _isAdmin = false;
  bool _isLoadingAdminStatus = true;
  bool _isNotificationMenuOpen =
      false; // Controla se o menu de notificações está aberto
  bool _showNavbar = true; // Controla se a navbar deve ser exibida
  int _currentPageIndex = 0; // Rastreia o índice atual do PageView
  final GlobalKey<NotificationBellNavbarState> _notificationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _checkAdminStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminStatus() async {
    if (widget.isGuestMode) {
      setState(() {
        _isAdmin = false;
        _isLoadingAdminStatus = false;
      });
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            _isAdmin = response['role'] == 'admin';
            _isLoadingAdminStatus = false;
          });
        }
      } catch (e) {
        debugPrint('Erro ao verificar status admin: $e');
        if (mounted) {
          setState(() {
            _isAdmin = false;
            _isLoadingAdminStatus = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isAdmin = false;
          _isLoadingAdminStatus = false;
        });
      }
    }
  }

  void navigateToHome() {
    _onTabTapped(0);
  }

  void _onTabTapped(int index) {
    // Abrir menu de notificações quando clicar (índice 2)
    if (index == 2) {
      _notificationKey.currentState?.toggleMenuFromOutside();
      setState(() {
        _isNotificationMenuOpen = true;
        _currentIndex = 2; // Manter selecionado enquanto o menu está aberto
      });
      return;
    }

    // Mapeamento dos índices da navbar para o PageView
    // NavBar:   0=Início, 1=Descontos, 2=Notificações(menu), 3=Pedidos, 4=Perfil
    // PageView: 0=Início, 1=Descontos,                       2=Pedidos, 3=Perfil
    int pageIndex;
    if (index < 2) {
      pageIndex = index; // 0->0, 1->1
    } else if (index == 3) {
      pageIndex = 2; // Pedidos: NavBar 3 -> PageView 2
    } else {
      pageIndex = 3; // Perfil: NavBar 4 -> PageView 3
    }

    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    // Ajustar índice ao mudar página
    // PageView: 0=Início, 1=Descontos, 2=Pedidos, 3=Perfil, 4=Carrinho, 5=Rastrear Kombi, 6=Admin
    // NavBar: 0=Início, 1=Descontos, 2=Notificações(menu), 3=Pedidos, 4=Perfil
    setState(() {
      _currentPageIndex = index; // Atualiza o índice da página atual
      if (index == 6) {
        // Admin (6): oculta navbar e desativa seleção
        _currentIndex = -1;
        _showNavbar = false;
        _isNotificationMenuOpen = false;
      } else if (index == 4 || index == 5) {
        // Carrinho (4) e Rastrear Kombi (5): mostra navbar mas sem seleção (não está na navbar)
        _currentIndex = -1;
        _showNavbar = true;
        _isNotificationMenuOpen = false;
      } else {
        // Mapeamento dos índices do PageView para NavBar
        // PageView: 0=Início, 1=Descontos, 2=Pedidos, 3=Perfil
        // NavBar:   0=Início, 1=Descontos, 3=Pedidos, 4=Perfil
        if (index <= 1) {
          _currentIndex = index; // 0->0, 1->1
        } else if (index == 2) {
          _currentIndex = 3; // Pedidos: PageView 2 -> NavBar 3
        } else if (index == 3) {
          _currentIndex = 4; // Perfil: PageView 3 -> NavBar 4
        }
        _showNavbar = true;
        _isNotificationMenuOpen = false;
      }
    });
  }

  void _onNotificationMenuToggle(bool isOpen) {
    setState(() {
      _isNotificationMenuOpen = isOpen;
    });

    if (!isOpen && _currentIndex == 2) {
      // Se o menu foi fechado e estávamos no índice 2 (Notificações), voltar para a página atual
      // Verifica se o PageController está anexado antes de acessar .page
      if (_pageController.hasClients) {
        setState(() {
          _currentIndex = _pageController.page?.round() ?? 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // PageView ocupa toda a tela, navbar fica por cima
          AdminStatusProvider(
            isAdmin: _isAdmin,
            isLoading: _isLoadingAdminStatus,
            child: MainNavigationProvider(
              navigateToHome: navigateToHome,
              navigateToPage: (navBarIndex) {
                // Converter índice da navbar para índice do PageView
                // NavBar:   0=Início, 1=Descontos, 2=Notificações(menu), 3=Pedidos, 4=Perfil
                // PageView: 0=Início, 1=Descontos, 2=Pedidos,            3=Perfil
                int pageIndex;
                if (navBarIndex < 2) {
                  pageIndex = navBarIndex; // 0->0, 1->1
                } else if (navBarIndex == 2) {
                  return; // Notificações não tem página
                } else if (navBarIndex == 3) {
                  pageIndex = 2; // Pedidos: NavBar 3 -> PageView 2
                } else {
                  pageIndex = 3; // Perfil: NavBar 4 -> PageView 3
                }

                _pageController.animateToPage(
                  pageIndex,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              navigateToPageDirect: (pageIndex) {
                // Navega diretamente para o índice do PageView (usado para Carrinho)
                _pageController.animateToPage(
                  pageIndex,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                // Desabilita swipe quando estiver na tela de Rastreamento (índice 5)
                physics: _currentPageIndex == 5
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                children: [
                  HomeScreen(isGuestMode: widget.isGuestMode), // índice 0
                  const DescontosScreen(), // índice 1
                  const PedidosScreen(), // índice 2
                  ProfileScreen(isGuestMode: widget.isGuestMode), // índice 3
                  const CartScreen(), // índice 4 (sem navbar)
                  const KombiTrackingScreen(), // índice 5 (sem navbar)
                  const AdminScreen(), // índice 6 (apenas para admin, sem navbar)
                ],
              ),
            ),
          ),
          // Navbar - só esconde na tela de Rastreamento (5)
          if (_showNavbar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BottomNavigationBar(
                        currentIndex: _currentIndex < 0
                            ? 0
                            : _currentIndex, // Garante índice válido
                        onTap: _onTabTapped,
                        type: BottomNavigationBarType.fixed,
                        backgroundColor: Colors.white,
                        selectedItemColor: _currentIndex < 0
                            ? Colors.grey[600]
                            : Colors.black,
                        unselectedItemColor: Colors.grey[600],
                        selectedLabelStyle: TextStyle(
                          fontWeight: _currentIndex < 0
                              ? FontWeight.w400
                              : FontWeight.w600,
                          fontSize: _currentIndex < 0 ? 10 : 11,
                          height: 1.2,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 10,
                          height: 1.2,
                        ),
                        elevation: 0,
                        items: [
                          BottomNavigationBarItem(
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.home_outlined),
                            ),
                            activeIcon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.home),
                            ),
                            label: 'Início',
                          ),
                          BottomNavigationBarItem(
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.local_offer_outlined),
                            ),
                            activeIcon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.local_offer),
                            ),
                            label: 'Descontos',
                          ),
                          BottomNavigationBarItem(
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: NotificationBellNavbar(
                                key: _notificationKey,
                                onMenuToggle: _onNotificationMenuToggle,
                                isActive: _isNotificationMenuOpen,
                              ),
                            ),
                            label: 'Notificações',
                          ),
                          BottomNavigationBarItem(
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.shopping_bag_outlined),
                            ),
                            activeIcon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.shopping_bag),
                            ),
                            label: 'Pedidos',
                          ),
                          BottomNavigationBarItem(
                            icon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.person_outline),
                            ),
                            activeIcon: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Icon(Icons.person),
                            ),
                            label: 'Perfil',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

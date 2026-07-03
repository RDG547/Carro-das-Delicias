import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/main_navigation_service.dart';
import '../widgets/main_navigation_provider.dart';
import '../providers/admin_status_provider.dart';
import 'home_screen.dart';
import 'descontos_screen.dart';
import 'cart_screen.dart';
import 'pedidos_screen.dart';
import 'profile_screen.dart';
import 'kombi_tracking_screen.dart';
import 'admin_screen.dart';
import 'support_legal_screen.dart';
import '../widgets/notification_bell_navbar.dart';

class MainScreen extends StatefulWidget {
  final bool isGuestMode;

  const MainScreen({super.key, this.isGuestMode = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late PageController _pageController;
  bool _isAdmin = false;
  bool _isLoadingAdminStatus = true;
  bool _showNavbar = true; // Controla se a navbar deve ser exibida
  bool _keyboardVisible = false;
  final GlobalKey<NotificationBellNavbarState> _notificationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardVisible = _isKeyboardVisibleFromWindow();
    _pageController = PageController();
    MainNavigationService.attach(_navigateToPageDirect);
    _checkAdminStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MainNavigationService.detach();
    _pageController.dispose();
    super.dispose();
  }

  bool _isKeyboardVisibleFromWindow() {
    return WidgetsBinding.instance.platformDispatcher.views.any(
      (view) => view.viewInsets.bottom > 0,
    );
  }

  @override
  void didChangeMetrics() {
    final keyboardVisible = _isKeyboardVisibleFromWindow();
    if (keyboardVisible == _keyboardVisible || !mounted) return;
    setState(() {
      _keyboardVisible = keyboardVisible;
    });
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

  void _navigateToPageDirect(int pageIndex) {
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onTabTapped(int index) {
    // Abrir menu de notificações quando clicar (índice 2)
    if (index == 2) {
      _notificationKey.currentState?.toggleMenuFromOutside();
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
    // PageView: 0=Início, 1=Descontos, 2=Pedidos, 3=Perfil, 4=Carrinho, 5=Rastrear Kombi, 6=Admin, 7=Ajuda
    // NavBar: 0=Início, 1=Descontos, 2=Notificações(menu), 3=Pedidos, 4=Perfil
    setState(() {
      if (index == 6) {
        // Admin (6): oculta navbar e desativa seleção
        _currentIndex = -1;
        _showNavbar = false;
      } else if (index == 4) {
        // Carrinho (4): oculta navbar para não cobrir controles próprios.
        _currentIndex = -1;
        _showNavbar = false;
      } else if (index == 5 || index == 7) {
        // Rastreamento e Ajuda/Políticas ficam fora das abas principais,
        // mas mantêm a navbar como atalho global.
        _currentIndex = -1;
        _showNavbar = true;
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final rawBottomInset = view.viewPadding.bottom / view.devicePixelRatio;
    final navbarBottomOffset = _keyboardVisible ? 16.0 : 16.0 + rawBottomInset;
    final shouldShowNavbar =
        _showNavbar && !(_keyboardVisible && _currentIndex == 4);

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
                _navigateToPageDirect(pageIndex);
              },
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                // Evita o "vazamento" lateral entre telas; a navegação segue
                // controlada pela navbar e pelo menu.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  HomeScreen(isGuestMode: widget.isGuestMode), // índice 0
                  const DescontosScreen(), // índice 1
                  const PedidosScreen(), // índice 2
                  ProfileScreen(isGuestMode: widget.isGuestMode), // índice 3
                  const CartScreen(), // índice 4 (sem navbar)
                  const KombiTrackingScreen(), // índice 5 (com navbar)
                  const AdminScreen(), // índice 6 (apenas para admin, sem navbar)
                  const SupportLegalScreen(), // índice 7 (com navbar)
                ],
              ),
            ),
          ),
          // Navbar principal
          if (shouldShowNavbar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, navbarBottomOffset),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
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
                    borderRadius: BorderRadius.circular(26),
                    child: _buildCustomNavbar(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomNavbar() {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          _buildNavbarItem(
            index: 0,
            label: 'Início',
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
          ),
          _buildNavbarItem(
            index: 1,
            label: 'Descontos',
            icon: Icons.local_offer_outlined,
            activeIcon: Icons.local_offer,
          ),
          _buildNavbarItem(
            index: 2,
            label: 'Notificações',
            customIcon: NotificationBellNavbar(key: _notificationKey),
          ),
          _buildNavbarItem(
            index: 3,
            label: 'Pedidos',
            icon: Icons.shopping_bag_outlined,
            activeIcon: Icons.shopping_bag,
          ),
          _buildNavbarItem(
            index: 4,
            label: 'Perfil',
            icon: Icons.person_outline,
            activeIcon: Icons.person,
          ),
        ],
      ),
    );
  }

  Widget _buildNavbarItem({
    required int index,
    required String label,
    IconData? icon,
    IconData? activeIcon,
    Widget? customIcon,
  }) {
    final selected = _currentIndex == index;
    final color = selected ? Colors.black : Colors.grey[600]!;

    final IconData? resolvedIcon;
    if (selected) {
      resolvedIcon = activeIcon ?? icon;
    } else {
      resolvedIcon = icon;
    }
    final iconWidget = customIcon ?? Icon(resolvedIcon, size: 25);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabTapped(index),
          child: IconTheme(
            data: IconThemeData(color: color, size: 25),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 25, child: Center(child: iconWidget)),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: selected ? 11 : 10,
                        height: 1,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
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
}

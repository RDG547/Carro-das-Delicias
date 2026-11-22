import '../services/app_sound_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/checkout_screen.dart';
import '../services/cart_service.dart';
import '../services/main_navigation_service.dart';
import '../utils/constants.dart';
import 'cart_item_card.dart';
import 'main_navigation_provider.dart';

class CartNavbarMenu extends StatefulWidget {
  const CartNavbarMenu({super.key});

  @override
  State<CartNavbarMenu> createState() => CartNavbarMenuState();
}

class CartNavbarMenuState extends State<CartNavbarMenu>
    with SingleTickerProviderStateMixin {
  final _cartService = CartService();
  final Map<String, TextEditingController> _observationControllers = {};
  late final AnimationController _menuAnimationController;
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;
  bool _isClosingOverlay = false;
  bool _isDisposed = false;
  bool _showClearConfirmation = false;

  @override
  void initState() {
    super.initState();
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _syncObservationControllers();
    _cartService.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cartService.removeListener(_onCartChanged);
    for (final controller in _observationControllers.values) {
      controller.dispose();
    }
    _observationControllers.clear();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _menuAnimationController.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted && !_isDisposed) {
      _syncObservationControllers();
      setState(() {});
      _overlayEntry?.markNeedsBuild();
    }
  }

  void _syncObservationControllers() {
    final currentKeys = _cartService.items.map((item) => item.cartKey).toSet();
    _observationControllers.removeWhere((key, controller) {
      if (currentKeys.contains(key)) return false;
      controller.dispose();
      return true;
    });

    for (final item in _cartService.items) {
      _observationControllers.putIfAbsent(
        item.cartKey,
        () => TextEditingController(text: item.observacoes ?? ''),
      );
    }
  }

  void toggleMenuFromOutside() {
    _toggleMenu();
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      unawaited(_removeOverlay());
      return;
    }

    _showMenu();
  }

  Future<void> _removeOverlay({bool immediate = false}) async {
    if (_overlayEntry == null) {
      if (mounted && !_isDisposed) {
        setState(() => _isMenuOpen = false);
      } else {
        _isMenuOpen = false;
      }
      return;
    }

    if (!immediate) {
      if (_isClosingOverlay) return;
      _isClosingOverlay = true;
      try {
        await _menuAnimationController.reverse();
      } catch (_) {
        // O widget pode desmontar durante a animação.
      }
    } else {
      _menuAnimationController.stop();
      _menuAnimationController.value = 0;
    }

    _overlayEntry?.remove();
    _overlayEntry = null;
    _showClearConfirmation = false;
    _isClosingOverlay = false;
    if (mounted && !_isDisposed) {
      setState(() => _isMenuOpen = false);
    } else {
      _isMenuOpen = false;
    }
  }

  void _showMenu() {
    if (_overlayEntry != null) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;

    final offset = renderObject.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalMargin = screenSize.width < 360 ? 10.0 : 16.0;
    final availableWidth = screenSize.width - (horizontalMargin * 2);
    final menuWidth = availableWidth < 300
        ? availableWidth
        : availableWidth.clamp(300.0, 440.0).toDouble();
    final menuLeft = (screenSize.width - menuWidth) / 2;
    final menuBottom = screenSize.height - offset.dy + 20;
    final maxHeight = screenSize.height * 0.72;
    final estimatedHeight = _cartService.isEmpty
        ? 250.0
        : 190.0 + (_cartService.items.length * 230.0);
    final menuHeight = estimatedHeight.clamp(250.0, maxHeight);

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            bottom: 80,
            child: GestureDetector(
              onTap: _removeOverlay,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            width: menuWidth,
            child: AnimatedBuilder(
              animation: _menuAnimationController,
              builder: (context, child) {
                final value = Curves.easeOutCubic.transform(
                  _menuAnimationController.value,
                );
                return Transform.scale(
                  scale: 0.92 + (0.08 * value),
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - value)),
                    child: Opacity(opacity: value, child: child),
                  ),
                );
              },
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(14),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: menuHeight),
                  child: _buildMenuContent(),
                ),
              ),
            ),
          ),
          if (_showClearConfirmation) _buildClearCartConfirmation(),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _menuAnimationController.forward(from: 0);
    if (mounted) {
      setState(() => _isMenuOpen = true);
    } else {
      _isMenuOpen = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = _cartService.totalItems;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          _isMenuOpen ? Icons.shopping_cart : Icons.shopping_cart_outlined,
          size: 25,
        ),
        if (totalItems > 0)
          Positioned(right: -8, top: -8, child: _Badge(count: totalItems)),
      ],
    );
  }

  Widget _buildMenuContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.shopping_cart_rounded,
                    color: Colors.orange[700],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Carrinho',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        _cartService.isEmpty
                            ? 'Nenhum item adicionado'
                            : '${_cartService.totalItems} ${_cartService.totalItems == 1 ? 'item' : 'itens'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildHeaderActions(),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _cartService.isEmpty
                ? _buildEmptyCart()
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _cartService.items.length,
                    itemBuilder: (context, index) {
                      final item = _cartService.items[index];
                      return CartItemCard(
                        item: item,
                        cartService: _cartService,
                        observationController:
                            _observationControllers[item.cartKey]!,
                      );
                    },
                  ),
          ),
          if (_cartService.items.isNotEmpty) _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 10),
          Text(
            'Seu carrinho está vazio',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adicione produtos para montar seu pedido.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              Text(
                CurrencyFormatter.format(_cartService.total),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _goToCheckout,
              icon: const Icon(Icons.payment_rounded),
              label: const Text('Finalizar pedido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCartScreen() {
    unawaited(_removeOverlay());
    if (MainNavigationService.navigateToCart()) return;

    final provider = MainNavigationProvider.of(context);
    provider?.navigateToPageDirect?.call(MainNavigationService.cartPageIndex);
  }

  void _goToCheckout() {
    if (_cartService.isEmpty) return;
    unawaited(_removeOverlay());
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  Widget _buildHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: _openCartScreen,
          icon: const Icon(Icons.shopping_cart_checkout, size: 15),
          label: const Text(
            'Ver carrinho',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (_cartService.items.isNotEmpty) ...[
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: 'Limpar carrinho',
            onPressed: _confirmClearCart,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red[700],
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  Future<void> _confirmClearCart() async {
    _setClearConfirmationVisible(true);
  }

  void _setClearConfirmationVisible(bool visible) {
    if (_showClearConfirmation == visible) return;
    _showClearConfirmation = visible;
    if (mounted && !_isDisposed) {
      setState(() {});
    }
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _clearCartAfterConfirmation() async {
    _setClearConfirmationVisible(false);
    await _cartService.clearCart();
    AppSoundService.cartCleared();
  }

  Widget _buildClearCartConfirmation() {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: InkWell(
          onTap: () => _setClearConfirmationVisible(false),
          child: Center(
            child: InkWell(
              onTap: () {},
              child: AlertDialog(
                title: const Text(
                  'Limpar carrinho',
                  textAlign: TextAlign.center,
                ),
                content: const Text(
                  'Tem certeza que deseja remover todos os itens do carrinho?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => _setClearConfirmationVisible(false),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/icons/menu/cancel_button.png',
                          width: 18,
                          height: 18,
                        ),
                        const SizedBox(width: 4),
                        const Text('Cancelar'),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _clearCartAfterConfirmation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/icons/menu/delete_button.png',
                          width: 18,
                          height: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        const Text('Limpar'),
                      ],
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
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

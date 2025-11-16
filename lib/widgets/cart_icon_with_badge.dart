import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import 'main_navigation_provider.dart';

class CartIconWithBadge extends StatefulWidget {
  final Color? iconColor;
  final double? iconSize;

  const CartIconWithBadge({super.key, this.iconColor, this.iconSize});

  @override
  State<CartIconWithBadge> createState() => _CartIconWithBadgeState();
}

class _CartIconWithBadgeState extends State<CartIconWithBadge> {
  final _cartService = CartService();

  @override
  void initState() {
    super.initState();
    _cartService.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cartService.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = _cartService.totalItems;

    return Stack(
      children: [
        IconButton(
          icon: Icon(
            Icons.shopping_cart,
            color: widget.iconColor,
            size: widget.iconSize,
          ),
          onPressed: () {
            // Navega para o carrinho usando o PageView do MainScreen
            final provider = MainNavigationProvider.of(context);
            if (provider?.navigateToPageDirect != null) {
              provider!.navigateToPageDirect!(2); // Índice 2 = Carrinho
            }
          },
        ),
        if (totalItems > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$totalItems',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

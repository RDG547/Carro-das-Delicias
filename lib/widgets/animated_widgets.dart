import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/constants.dart';
import '../services/cart_service.dart';
import '../services/favorites_service.dart';
import '../services/main_navigation_service.dart';
import '../screens/cart_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/checkout_screen.dart';
import '../utils/app_snackbar.dart';
import 'size_selector_dialog.dart';
import 'main_navigation_provider.dart';
import 'category_icon_widget.dart';
import 'favorite_heart_animation.dart';
import '../providers/admin_status_provider.dart';
import 'edit_product_dialog.dart';

/// Botão animado com efeito de escala ao pressionar
class AnimatedButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;

  const AnimatedButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
    this.icon,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _onTapDown : null,
      onTapUp: widget.onPressed != null ? _onTapUp : null,
      onTapCancel: widget.onPressed != null ? _onTapCancel : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: widget.isLoading ? null : widget.onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.backgroundColor ?? Colors.black,
                  foregroundColor: widget.textColor ?? Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            widget.text,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Campo de texto animado com validação visual
class AnimatedTextField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const AnimatedTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
  });

  @override
  State<AnimatedTextField> createState() => _AnimatedTextFieldState();
}

class _AnimatedTextFieldState extends State<AnimatedTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _focusAnimation;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _focusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _focusAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: 0.1 * _focusAnimation.value,
                ),
                blurRadius: 8 * _focusAnimation.value,
                offset: Offset(0, 2 * _focusAnimation.value),
              ),
            ],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            inputFormatters: widget.inputFormatters,
            validator: widget.validator,
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: _isFocused ? Colors.black : Colors.grey[600],
                    )
                  : null,
              suffixIcon: widget.suffixIcon,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.black),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[400]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.black,
                  width: 2 + _focusAnimation.value,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              labelStyle: TextStyle(
                color: _isFocused ? Colors.black : Colors.grey[700],
                fontWeight: _isFocused ? FontWeight.w600 : FontWeight.normal,
              ),
              hintStyle: TextStyle(color: Colors.grey[500]),
              filled: true,
              fillColor: _isFocused ? Colors.grey[50] : Colors.transparent,
            ),
          ),
        );
      },
    );
  }
}

/// Card animado para exibir produtos
class AnimatedProductCard extends StatefulWidget {
  final Map<String, dynamic> produto;
  final VoidCallback? onTap;
  final VoidCallback? onProductDeleted;
  final bool showAddToCart;
  final bool? isAdmin; // Parâmetro opcional para forçar status de admin

  const AnimatedProductCard({
    super.key,
    required this.produto,
    this.onTap,
    this.onProductDeleted,
    this.showAddToCart = true,
    this.isAdmin,
  });

  @override
  State<AnimatedProductCard> createState() => _AnimatedProductCardState();
}

class _AnimatedProductCardState extends State<AnimatedProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  final _cartService = CartService();
  final _favoritesService = FavoritesService();
  static const List<double> _grayscaleMatrix = [
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isProductAvailable => widget.produto['ativo'] != false;

  void _showUnavailableProductMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Produto indisponível no momento. Aguarde a disponibilidade.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _openCartPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (MainNavigationService.navigateToCart()) {
        return;
      }

      final provider = MainNavigationProvider.of(context);
      if (provider?.navigateToPageDirect != null) {
        provider!.navigateToPageDirect!(MainNavigationService.cartPageIndex);
        return;
      }

      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => const CartScreen()));
    });
  }

  Widget _buildPriceWidget() {
    final tamanhos = widget.produto['tamanhos'];
    final preco = widget.produto['preco'];
    final precoAnterior = widget.produto['preco_anterior'];
    final isPromocao = widget.produto['promocao'] ?? false;

    // Se tem múltiplos tamanhos, mostrar o menor preço
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      // Encontrar o menor preço
      double menorPreco = double.infinity;
      for (var tamanho in tamanhos) {
        final precoTamanho = tamanho['preco']?.toDouble() ?? 0.0;
        if (precoTamanho < menorPreco && precoTamanho > 0) {
          menorPreco = precoTamanho;
        }
      }

      if (menorPreco == double.infinity) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Sem preço',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black54,
            ),
          ),
        );
      }

      final hasDesconto = precoAnterior != null && precoAnterior > menorPreco;
      final temMultiplosPrecos = tamanhos.length > 1;

      if (hasDesconto) {
        final percentualDesconto =
            ((precoAnterior - menorPreco) / precoAnterior * 100).toInt();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$percentualDesconto% OFF',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(precoAnterior),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              temMultiplosPrecos ? 'A partir de' : 'Preço',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                CurrencyFormatter.format(menorPreco),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            tamanhos.length > 1 ? 'A partir de' : 'Preço',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.green, Colors.teal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              CurrencyFormatter.format(menorPreco),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Se não há preço, retorna sem preço
    if (preco == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Sem preço',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black54,
          ),
        ),
      );
    }

    final precoAtual = preco.toDouble();
    final hasDesconto = precoAnterior != null && precoAnterior > precoAtual;

    // Se tem desconto, mostra preço anterior riscado
    if (hasDesconto) {
      final percentualDesconto =
          ((precoAnterior - precoAtual) / precoAnterior * 100).toInt();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Badge de desconto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$percentualDesconto% OFF',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Preço anterior riscado
          Text(
            CurrencyFormatter.format(precoAnterior),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 2),
          // Preço com desconto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.deepOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              CurrencyFormatter.format(precoAtual),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Se está em promoção (sem desconto específico), mostra badge de promoção
    if (isPromocao) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Badge de promoção
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'PROMOÇÃO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Preço em promoção
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.red, Colors.redAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              CurrencyFormatter.format(precoAtual),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Preço normal sem promoção ou desconto
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.green, Colors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        CurrencyFormatter.format(precoAtual),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
      ),
    );
  }

  Future<void> _buyNow() async {
    try {
      if (!_isProductAvailable) {
        _showUnavailableProductMessage();
        return;
      }

      final produto = widget.produto;
      final tamanhos = produto['tamanhos'];

      // Se tem tamanhos, mostrar diálogo para escolher
      if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
        await _showSizeSelectorAndBuy();
        return;
      }

      final preco = produto['preco']?.toDouble();

      debugPrint('🛒 Comprando produto: ${produto['nome']}');

      if (preco == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto sem preço não pode ser comprado'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Adiciona ao carrinho com flag isBuyNow = true
      await _cartService.addItem(produto, isBuyNow: true);
      debugPrint(
        '✅ Produto adicionado ao carrinho, navegando para checkout...',
      );

      if (mounted) {
        try {
          final result = await Navigator.pushNamed(context, '/checkout');
          debugPrint('🔗 Navegação para checkout executada');

          // Se o usuário voltou sem finalizar, remove o item
          if (result == null && mounted) {
            await _cartService.clearBuyNowItems();
            debugPrint('🗑️ Item de compra rápida removido');
          }
        } catch (e) {
          debugPrint('❌ Erro na navegação para checkout: $e');
          // Fallback: usar Navigator.push
          if (!mounted) return;

          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CheckoutScreen()),
          );

          // Se o usuário voltou sem finalizar no fallback também
          if (result == null && mounted) {
            await _cartService.clearBuyNowItems();
            debugPrint('🗑️ Item de compra rápida removido (fallback)');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Erro em _buyNow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar compra: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showSizeSelectorAndBuy() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => SizeSelectorDialog(
        produto: widget.produto,
        action: SizeSelectionAction.buyNow,
        onSizeSelected: (selectedSize) async {
          // Criar produto com tamanho selecionado
          final produtoComTamanho = Map<String, dynamic>.from(widget.produto);
          produtoComTamanho['preco'] = selectedSize['preco'];
          produtoComTamanho['tamanho_selecionado'] = selectedSize['nome'];

          debugPrint(
            '🛒 Comprando produto com tamanho: ${selectedSize['nome']}',
          );

          // Capturar contexto ANTES do await
          final navigator = Navigator.of(context);

          // Adiciona ao carrinho com flag isBuyNow = true
          await _cartService.addItem(produtoComTamanho, isBuyNow: true);

          if (!mounted) return;

          try {
            final result = await navigator.pushNamed('/checkout');

            // Se o usuário voltou sem finalizar, remove o item
            if (result == null && mounted) {
              await _cartService.clearBuyNowItems();
              debugPrint('🗑️ Item de compra rápida removido');
            }
          } catch (e) {
            debugPrint('❌ Erro na navegação para checkout: $e');
            if (!mounted) return;

            final result = await navigator.push(
              MaterialPageRoute(builder: (context) => const CheckoutScreen()),
            );

            if (result == null && mounted) {
              await _cartService.clearBuyNowItems();
              debugPrint('🗑️ Item de compra rápida removido (fallback)');
            }
          }
        },
      ),
    );
  }

  Future<void> _addToCart() async {
    if (!_isProductAvailable) {
      _showUnavailableProductMessage();
      return;
    }

    final currentContext = context;
    final produto = widget.produto;
    final tamanhos = produto['tamanhos'];

    // Se tem tamanhos, mostrar diálogo para escolher
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      await _showSizeSelectorAndAddToCart();
      return;
    }

    final preco = produto['preco']?.toDouble();

    if (preco == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Produto sem preço não pode ser adicionado ao carrinho',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _cartService.addItem(produto);

    if (!currentContext.mounted) return;

    AppSnackBar.showCartAdded(
      currentContext,
      message: '${produto['nome']} adicionado ao carrinho!',
      onViewCart: _openCartPage,
      avoidAdminFab: widget.isAdmin == true,
    );
  }

  Future<void> _showSizeSelectorAndAddToCart() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => SizeSelectorDialog(
        produto: widget.produto,
        action: SizeSelectionAction.addToCart,
        onSizeSelected: (selectedSize) async {
          final currentContext = context;
          // Criar produto com tamanho selecionado
          final produtoComTamanho = Map<String, dynamic>.from(widget.produto);
          produtoComTamanho['preco'] = selectedSize['preco'];
          produtoComTamanho['tamanho_selecionado'] = selectedSize['nome'];

          await _cartService.addItem(produtoComTamanho);

          if (!currentContext.mounted) return;

          AppSnackBar.showCartAdded(
            currentContext,
            message:
                '${widget.produto['nome']} (${selectedSize['nome']}) adicionado ao carrinho!',
            onViewCart: _openCartPage,
            avoidAdminFab: widget.isAdmin == true,
          );
        },
      ),
    );
  }

  void _goToProductDetail() async {
    try {
      if (!_isProductAvailable) {
        _showUnavailableProductMessage();
        return;
      }

      debugPrint(
        '🔗 Navegando para detalhes do produto: ${widget.produto['nome']}',
      );
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(produto: widget.produto),
        ),
      );
      if (result == 'go_to_cart' && mounted) {
        _openCartPage();
      }
    } catch (e) {
      debugPrint('❌ Erro ao navegar para detalhes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir detalhes do produto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAdminOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                widget.produto['nome'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar Produto'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditProductDialog();
                },
              ),
              const Divider(),
              ListTile(
                leading: Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 24,
                  height: 24,
                  color: Colors.red,
                ),
                title: const Text('Excluir Produto'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditProductDialog() async {
    try {
      // Buscar categorias do Supabase
      final response = await Supabase.instance.client
          .from('categorias')
          .select()
          .order('ordem', ascending: true);

      final categorias = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => EditProductDialog(
          produto: widget.produto,
          categorias: categorias,
          onProductUpdated: () {
            // Recarregar a página atual
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Produto atualizado com sucesso!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar categorias: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir o produto "${widget.produto['nome']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
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
            onPressed: () => Navigator.pop(context, true),
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
                  color: Colors.black,
                ),
                const SizedBox(width: 4),
                const Text('Excluir'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteProduct();
    }
  }

  // Verifica se o erro é de conexão de rede
  bool _isConnectionError(dynamic error) {
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

  void _showConnectionErrorSnackbar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sem conexão com o servidor. Verifique sua internet.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteProduct() async {
    try {
      await Supabase.instance.client
          .from('produtos')
          .delete()
          .eq('id', widget.produto['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );

        // Notificar o pai para recarregar a lista de produtos
        widget.onProductDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        if (_isConnectionError(e)) {
          _showConnectionErrorSnackbar();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir produto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [Colors.white, Colors.grey[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border.all(color: Colors.grey[300]!, width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTapDown: (_) {
                debugPrint('🔽 TapDown no produto');
                _controller.forward();
              },
              onTapCancel: () {
                debugPrint('❌ TapCancel no produto');
                _controller.reverse();
              },
              onTap: () {
                debugPrint('👆 Tap no card do produto - chamando navegação');
                _controller.reverse();
                if (!_isProductAvailable) {
                  _showUnavailableProductMessage();
                } else if (widget.onTap != null) {
                  widget.onTap!();
                } else {
                  _goToProductDetail();
                }
              },
              onLongPress: () {
                debugPrint('👆 Long press no card do produto');
                _controller.reverse();
                // Verifica se é admin (do parâmetro ou do provider)
                bool adminStatus = false;
                if (widget.isAdmin != null) {
                  adminStatus = widget.isAdmin!;
                } else {
                  final adminProvider = AdminStatusProvider.of(context);
                  adminStatus = adminProvider != null && adminProvider.isAdmin;
                }
                debugPrint('👤 IsAdmin para long press: $adminStatus');
                if (adminStatus) {
                  _showAdminOptions();
                }
              },
              child: ColorFiltered(
                colorFilter: _isProductAvailable
                    ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                    : const ColorFilter.matrix(_grayscaleMatrix),
                child: Opacity(
                  opacity: _isProductAvailable ? 1 : 0.82,
                  child: Column(
                    children: [
                      // Tag de Promoção/Desconto no topo (se houver)
                      if (widget.produto['preco_anterior'] != null &&
                          widget.produto['preco_anterior'] >
                              widget.produto['preco'])
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.deepOrange],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.local_offer,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PROMOÇÃO - ${((widget.produto['preco_anterior'] - widget.produto['preco']) / widget.produto['preco_anterior'] * 100).toInt()}% OFF',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Conteúdo principal do card
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Imagem ou Ícone da categoria
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange[200]!),
                              ),
                              child:
                                  widget.produto['imagem_url'] != null &&
                                      widget.produto['imagem_url']
                                          .toString()
                                          .isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        widget.produto['imagem_url'],
                                        fit: BoxFit.cover,
                                        cacheWidth: 240,
                                        cacheHeight: 240,
                                        filterQuality: FilterQuality.medium,
                                        errorBuilder:
                                            (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => Center(
                                              child: CategoryIconWidget(
                                                icone: widget
                                                    .produto['categoria_icone'],
                                                size: 40,
                                              ),
                                            ),
                                      ),
                                    )
                                  : Center(
                                      child: CategoryIconWidget(
                                        icone:
                                            widget.produto['categoria_icone'] ??
                                            '🍰',
                                        size: 40,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 16),

                            // Informações do produto
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nome do produto
                                  Text(
                                    widget.produto['nome'] ??
                                        'Produto sem nome',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.black87,
                                      decoration: _isProductAvailable
                                          ? TextDecoration.none
                                          : TextDecoration.lineThrough,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),

                                  // Apenas descrição se disponível
                                  if (widget.produto['descricao'] != null &&
                                      widget.produto['descricao']
                                          .toString()
                                          .isNotEmpty)
                                    Text(
                                      widget.produto['descricao'],
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),

                            // Preço com desconto ou normal
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Botão de favorito
                                GestureDetector(
                                  onTap: () async {
                                    final productId = widget.produto['id']
                                        .toString();
                                    final wasFavorite = _favoritesService
                                        .isFavorite(productId);
                                    final productName = widget.produto['nome'];
                                    final overlay = Overlay.of(context);

                                    await _favoritesService.toggleFavorite(
                                      productId,
                                    );
                                    if (!context.mounted) return;
                                    setState(() {}); // Atualizar UI

                                    // Mostrar animação de coração
                                    FavoriteHeartAnimation.showWithOverlay(
                                      overlay,
                                      isFavoriting: !wasFavorite,
                                    );

                                    // Mostrar feedback visual
                                    AppSnackBar.showTop(
                                      context,
                                      toolbarHeight: 48,
                                      topSpacing: 36,
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: wasFavorite
                                          ? Colors.grey.shade700
                                          : Colors.red,
                                      content: Row(
                                        children: [
                                          Icon(
                                            wasFavorite
                                                ? Icons.heart_broken
                                                : Icons.favorite,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              wasFavorite
                                                  ? 'Removido dos favoritos'
                                                  : '$productName adicionado aos favoritos!',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      _favoritesService.isFavorite(
                                            widget.produto['id'].toString(),
                                          )
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color:
                                          _favoritesService.isFavorite(
                                            widget.produto['id'].toString(),
                                          )
                                          ? Colors.red
                                          : Colors.grey,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Preço
                                _buildPriceWidget(),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Botões de ação (se showAddToCart for true)
                      // Envolvido com GestureDetector para não propagar tap para o InkWell
                      if (widget.showAddToCart &&
                          widget.produto['preco'] != null)
                        GestureDetector(
                          onTap: () {
                            // Absorver tap para não propagar para o InkWell
                            debugPrint('🛑 Tap nos botões - não navega');
                          },
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                // Botão Comprar
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isProductAvailable
                                        ? _buyNow
                                        : _showUnavailableProductMessage,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.shopping_bag, size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'Comprar',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Botão Adicionar ao Carrinho
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isProductAvailable
                                        ? _addToCart
                                        : _showUnavailableProductMessage,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black,
                                      side: const BorderSide(
                                        color: Colors.black,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(
                                            Icons.add_shopping_cart,
                                            size: 14,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Carrinho',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

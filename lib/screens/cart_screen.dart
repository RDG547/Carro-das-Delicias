import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../services/cart_service.dart';
import '../utils/constants.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartService = CartService();
  final Map<String, TextEditingController> _observationControllers = {};
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _cartService.addListener(_onCartChanged);
    _initializeControllers();
    // Atrasa a verificação para depois do primeiro build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdminStatus();
    });
  }

  Future<void> _checkAdminStatus() async {
    if (_isAdmin) return; // Já verificado, evita verificações desnecessárias

    try {
      final user = Supabase.instance.client.auth.currentUser;
      debugPrint('🔍 Cart - Verificando admin status - user: ${user?.id}');

      if (user == null) {
        debugPrint('⚠️ Cart - Usuário não autenticado');
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('📊 Cart - Resposta da query: $response');

      if (mounted && response != null) {
        final isAdmin = response['role'] == 'admin';
        debugPrint('✅ Cart - is_admin definido como: $isAdmin');
        if (_isAdmin != isAdmin) {
          setState(() => _isAdmin = isAdmin);
        }
      } else {
        debugPrint('⚠️ Cart - Response null ou widget desmontado');
      }
    } catch (e) {
      debugPrint('❌ Cart - Erro ao verificar status admin: $e');
    }
  }

  @override
  void dispose() {
    _cartService.removeListener(_onCartChanged);
    _disposeControllers();
    super.dispose();
  }

  void _initializeControllers() {
    for (final item in _cartService.items) {
      _observationControllers[item.id] = TextEditingController(
        text: item.observacoes ?? '',
      );
    }
  }

  void _disposeControllers() {
    for (final controller in _observationControllers.values) {
      controller.dispose();
    }
    _observationControllers.clear();
  }

  void _onCartChanged() {
    if (mounted) {
      setState(() {
        // Remover controladores de itens que não existem mais
        final currentIds = _cartService.items.map((item) => item.id).toSet();
        _observationControllers.removeWhere((id, controller) {
          if (!currentIds.contains(id)) {
            controller.dispose();
            return true;
          }
          return false;
        });

        // Adicionar controladores para novos itens
        for (final item in _cartService.items) {
          if (!_observationControllers.containsKey(item.id)) {
            _observationControllers[item.id] = TextEditingController(
              text: item.observacoes ?? '',
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: const BoxDecoration(color: Colors.black),
          child: SafeArea(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                children: [
                  // Botão voltar para Home
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        debugPrint(
                          '🔙 Botão voltar pressionado - Voltando para Home',
                        );
                        // Navega de volta para Home usando MainNavigationProvider
                        final provider = MainNavigationProvider.of(context);
                        if (provider?.navigateToPage != null) {
                          provider!.navigateToPage!(0); // Índice 0 = Início
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  // Título centralizado
                  Center(
                    child: Text(
                      'Meu Carrinho',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  // Actions à direita
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_cartService.items.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_sweep,
                              color: Colors.white,
                            ),
                            onPressed: _showClearCartDialog,
                            tooltip: 'Limpar carrinho',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        AppMenu(isGuestMode: false, isAdmin: _isAdmin),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _cartService.isEmpty
          ? _buildEmptyCart()
          : Stack(
              children: [
                _buildCartContent(),
                // Botão de finalizar fixo - fica atrás da navbar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildCheckoutButton(),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 120,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Seu carrinho está vazio',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Adicione alguns deliciosos produtos\npara começar seu pedido!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              final provider = MainNavigationProvider.of(context);
              if (provider?.navigateToPage != null) {
                provider!.navigateToPage!(0); // Navega para tela de início
              }
            },
            icon: const Icon(Icons.restaurant_menu),
            label: const Text('Ver Produtos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartContent() {
    return Column(
      children: [
        // Header com resumo
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            border: Border(bottom: BorderSide(color: Colors.orange[200]!)),
          ),
          child: Row(
            children: [
              Icon(Icons.shopping_cart, color: Colors.orange[700]),
              const SizedBox(width: 12),
              Text(
                '${_cartService.totalItems} itens no carrinho',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
        ),

        // Lista de itens
        Expanded(
          child: ListView.builder(
            addRepaintBoundaries: true,
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  220, // Espaço para o botão de finalizar (120px) + navbar (80px) + margem (20px)
            ),
            itemCount: _cartService.items.length,
            itemBuilder: (context, index) {
              final item = _cartService.items[index];
              return _buildCartItem(item, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartItem(CartItem item, int index) {
    final controller = _observationControllers[item.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Imagem do produto
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[100],
                  ),
                  child: item.imagemUrl != null && item.imagemUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            item.imagemUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            cacheHeight: 160,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildProductPlaceholder(),
                          ),
                        )
                      : _buildProductPlaceholder(),
                ),

                const SizedBox(width: 16),

                // Informações do produto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nome,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.categoriaNome != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.categoriaNome!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (item.tamanhoSelecionado != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Tamanho: ${_formatTamanho(item.tamanhoSelecionado!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        CurrencyFormatter.format(item.preco),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),

                // Controles de quantidade
                Column(
                  children: [
                    _buildQuantityControls(item),
                    const SizedBox(height: 8),
                    Text(
                      CurrencyFormatter.format(item.subtotal),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Campo de observações (expansível)
          if (controller != null) _buildObservationsField(item, controller),
        ],
      ),
    );
  }

  Widget _buildProductPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[200]!, Colors.pink[200]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.fastfood, size: 32, color: Colors.white),
      ),
    );
  }

  Widget _buildQuantityControls(CartItem item) {
    return Column(
      children: [
        const Text(
          'Quantidade',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQuantityButton(
                icon: Icons.remove,
                onPressed: () =>
                    _cartService.updateQuantity(item.id, item.quantidade - 1),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  item.quantidade.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              _buildQuantityButton(
                icon: Icons.add,
                onPressed: () =>
                    _cartService.updateQuantity(item.id, item.quantidade + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildObservationsField(
    CartItem item,
    TextEditingController controller,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Observações',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Escreva uma observação... (opcional)',
              hintStyle: TextStyle(fontSize: 12),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 14),
            maxLines: 2,
            onChanged: (value) {
              _cartService.updateObservations(
                item.id,
                value.trim().isEmpty ? null : value.trim(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Resumo do pedido
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total do Pedido:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Text(
                CurrencyFormatter.format(_cartService.total),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Botão de finalizar pedido
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _goToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Finalizar Pedido',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCartDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Carrinho'),
        content: const Text(
          'Tem certeza que deseja remover todos os itens do carrinho?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              _cartService.clearCart();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  void _goToCheckout() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CheckoutScreen()),
    );
  }

  String _formatTamanho(String tamanhoJson) {
    try {
      final tamanho = json.decode(tamanhoJson);
      if (tamanho is Map<String, dynamic>) {
        return tamanho['nome'] ?? tamanhoJson;
      }
      return tamanhoJson;
    } catch (e) {
      return tamanhoJson;
    }
  }
}

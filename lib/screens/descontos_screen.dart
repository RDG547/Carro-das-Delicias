import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../providers/admin_status_provider.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';
import '../services/cart_service.dart';
import 'product_detail_screen.dart';

/// Constrói o widget do ícone de categoria (suporta SVG asset, PNG asset, URL de imagem e emoji)
Widget _buildCategoryIconWidget(String? icone, {double size = 24}) {
  if (icone == null) return const SizedBox.shrink();
  if (icone.startsWith('asset:')) {
    final assetPath = icone.replaceFirst('asset:', '');
    if (assetPath.endsWith('.svg')) {
      return SvgPicture.asset(assetPath, width: size, height: size);
    } else {
      return Image.asset(assetPath, width: size, height: size);
    }
  } else if (icone.startsWith('http')) {
    return Image.network(
      icone,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, size: 16),
    );
  } else {
    return Text(icone, style: TextStyle(fontSize: size * 0.67));
  }
}

class DescontosScreen extends StatefulWidget {
  const DescontosScreen({super.key});

  @override
  State<DescontosScreen> createState() => _DescontosScreenState();
}

class _DescontosScreenState extends State<DescontosScreen> {
  List<Map<String, dynamic>> _produtosComDesconto = [];
  bool _isLoading = true;
  final CartService _cartService = CartService();

  @override
  void initState() {
    super.initState();
    _loadProdutosComDesconto();
  }

  Future<void> _loadProdutosComDesconto() async {
    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('produtos')
          .select('*, categorias!categoria_id(nome, icone)')
          .not('preco_anterior', 'is', null)
          .eq('ativo', true)
          .order('created_at', ascending: false);

      setState(() {
        _produtosComDesconto = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar produtos com desconto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatPrice(dynamic price) {
    if (price is num) {
      return 'R\$ ${price.toStringAsFixed(2).replaceAll('.', ',')}';
    }
    return 'R\$ 0,00';
  }

  double _calcularPercentualDesconto(
    dynamic precoAnterior,
    dynamic precoAtual,
  ) {
    if (precoAnterior is num && precoAtual is num && precoAnterior > 0) {
      return ((precoAnterior - precoAtual) / precoAnterior) * 100;
    }
    return 0.0;
  }

  void _goToHome() {
    debugPrint('🔙 Botão de voltar pressionado na tela de descontos');
    // Navega de volta para Home usando MainNavigationProvider
    final provider = MainNavigationProvider.of(context);
    if (provider?.navigateToPage != null) {
      provider!.navigateToPage!(0); // Índice 0 = Início
    } else {
      // Fallback: se não houver provider, tenta pop
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _navigateToProductDetail(Map<String, dynamic> produto) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(produto: produto),
      ),
    );
    if (result == 'go_to_cart' && mounted) {
      final provider = MainNavigationProvider.of(context);
      provider?.navigateToPageDirect?.call(4);
    }
  }

  void _addToCart(Map<String, dynamic> produto) {
    _cartService.addItem(produto, quantidade: 1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${produto['nome']} adicionado ao carrinho!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmojiPlaceholder(Map<String, dynamic>? categoria) {
    final String icone = categoria?['icone'] ?? '🍰';
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SizedBox(
          width: 80,
          height: 80,
          child: _buildCategoryIconWidget(icone, size: 72),
        ),
      ),
    );
  }

  Future<void> _buyNow(Map<String, dynamic> produto) async {
    // Adiciona ao carrinho com flag isBuyNow = true
    await _cartService.addItem(produto, isBuyNow: true);

    if (mounted) {
      final result = await Navigator.pushNamed(context, '/checkout');

      // Se o usuário voltou sem finalizar, remove o item
      if (result == null && mounted) {
        await _cartService.clearBuyNowItems();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuestMode = user == null;
    final adminProvider = AdminStatusProvider.of(context);
    final isAdmin = adminProvider?.isAdmin ?? false;

    return BaseScreen(
      title: 'Descontos',
      showBackButton: true,
      onBackPressed: _goToHome,
      actions: [AppMenu(isGuestMode: isGuestMode, isAdmin: isAdmin)],
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _produtosComDesconto.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_offer_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Nenhuma oferta disponível',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Volte em breve para ver nossas promoções!',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadProdutosComDesconto,
              child: ListView.builder(
                addRepaintBoundaries: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _produtosComDesconto.length,
                itemBuilder: (context, index) {
                  final produto = _produtosComDesconto[index];
                  final categoria = produto['categorias'];
                  final precoAnterior = produto['preco_anterior'] ?? 0.0;
                  final precoAtual = produto['preco'] ?? 0.0;
                  final percentualDesconto = _calcularPercentualDesconto(
                    precoAnterior,
                    precoAtual,
                  );

                  return GestureDetector(
                    onTap: () => _navigateToProductDetail(produto),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [Colors.red[50]!, Colors.orange[50]!],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Badge de desconto
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${percentualDesconto.toInt()}% OFF',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (categoria != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: _buildCategoryIconWidget(
                                              categoria['icone'] ?? '📦',
                                              size: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            categoria['nome'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Imagem do produto
                              Center(
                                child:
                                    (produto['imagens'] != null &&
                                        produto['imagens'] is List &&
                                        (produto['imagens'] as List).isNotEmpty)
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          (produto['imagens'] as List).first,
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          cacheWidth: 240,
                                          cacheHeight: 240,
                                          filterQuality: FilterQuality.medium,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return _buildEmojiPlaceholder(
                                                  categoria,
                                                );
                                              },
                                          loadingBuilder:
                                              (
                                                context,
                                                child,
                                                loadingProgress,
                                              ) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Container(
                                                  width: 120,
                                                  height: 120,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                );
                                              },
                                        ),
                                      )
                                    : (produto['imagem_url'] != null &&
                                          produto['imagem_url']
                                              .toString()
                                              .isNotEmpty)
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          produto['imagem_url'],
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          cacheWidth: 240,
                                          cacheHeight: 240,
                                          filterQuality: FilterQuality.medium,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  width: 120,
                                                  height: 120,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.image_not_supported,
                                                    size: 50,
                                                    color: Colors.grey,
                                                  ),
                                                );
                                              },
                                          loadingBuilder:
                                              (
                                                context,
                                                child,
                                                loadingProgress,
                                              ) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Container(
                                                  width: 120,
                                                  height: 120,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                );
                                              },
                                        ),
                                      )
                                    : _buildEmojiPlaceholder(categoria),
                              ),
                              const SizedBox(height: 12),

                              // Nome do produto
                              Text(
                                produto['nome'] ?? 'Produto',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              // Descrição
                              if (produto['descricao'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    produto['descricao'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                              const SizedBox(height: 16),

                              // Preços
                              Row(
                                children: [
                                  // Preço anterior (riscado)
                                  Text(
                                    _formatPrice(precoAnterior),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Preço atual com desconto
                                  Text(
                                    _formatPrice(precoAtual),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),

                                  const Spacer(),

                                  // Economia
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Economize ${_formatPrice(precoAnterior - precoAtual)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[800],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Botões de ação
                              Row(
                                children: [
                                  // Botão Comprar
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: ElevatedButton(
                                        onPressed: () => _buyNow(produto),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.shopping_bag,
                                                size: 16,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Comprar',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Botão Carrinho
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: OutlinedButton(
                                        onPressed: () => _addToCart(produto),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.black,
                                          side: const BorderSide(
                                            color: Colors.black,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.shopping_cart,
                                                size: 16,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Carrinho',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

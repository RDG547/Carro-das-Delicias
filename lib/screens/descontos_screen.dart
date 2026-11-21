import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/category_icon_widget.dart';
import '../providers/admin_status_provider.dart';
import '../widgets/app_menu.dart';
import '../widgets/flavor_count_badge.dart';
import '../widgets/main_navigation_provider.dart';
import '../services/cart_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/app_settings_service.dart';
import '../services/main_navigation_service.dart';
import '../utils/product_action_helper.dart';
import '../utils/product_variant_utils.dart';
import '../utils/scroll_indicator_layout.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/scroll_down_indicator.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

enum DiscountSortOption { biggestDiscount, latest, alphabetical }

class DescontosScreen extends StatefulWidget {
  const DescontosScreen({super.key});

  @override
  State<DescontosScreen> createState() => _DescontosScreenState();
}

class _DescontosScreenState extends State<DescontosScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _produtosComDesconto = [];
  bool _isLoading = true;
  final CartService _cartService = CartService();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _scrollIndicatorController;
  RealtimeChannel? _productsChannel;
  RealtimeChannel? _categoriesChannel;
  Timer? _realtimeDebounceTimer;
  Timer? _realtimeReconnectTimer;
  bool _showScrollIndicator = true;
  bool _hasScrolledDown = false;
  bool _isScrollIndicatorAnimating = false;
  late final VoidCallback _catalogSyncListener;
  DiscountSortOption _sortOption = DiscountSortOption.biggestDiscount;
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
    WidgetsBinding.instance.addObserver(this);
    _scrollIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_hasScrolledDown) {
        _hasScrolledDown = true;
      }
      if (_scrollController.offset > 50 && _showScrollIndicator) {
        _hideScrollIndicator();
      }
    });
    _catalogSyncListener = () {
      _scheduleProductsRefresh();
    };
    CatalogSyncService.instance.addListener(_catalogSyncListener);
    AppSettingsService.showProductsWithoutPhotos.addListener(
      _catalogSyncListener,
    );
    _loadProdutosComDesconto();
    _setupRealtimeSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollIndicatorAvailabilityChecks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeDebounceTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    CatalogSyncService.instance.removeListener(_catalogSyncListener);
    AppSettingsService.showProductsWithoutPhotos.removeListener(
      _catalogSyncListener,
    );
    if (_productsChannel != null) {
      Supabase.instance.client.removeChannel(_productsChannel!);
    }
    if (_categoriesChannel != null) {
      Supabase.instance.client.removeChannel(_categoriesChannel!);
    }
    _scrollController.dispose();
    _scrollIndicatorController.dispose();
    super.dispose();
  }

  void _setupRealtimeSubscription() => CatalogSyncService.instance.start();

  void _scheduleProductsRefresh() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _loadProdutosComDesconto(showLoadingIndicator: false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _setupRealtimeSubscription();
    unawaited(_loadProdutosComDesconto(showLoadingIndicator: false));
  }

  void _scheduleScrollIndicatorAvailabilityChecks() {
    const delays = [0, 120, 320];
    for (final delay in delays) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) {
          _updateScrollIndicatorAvailability();
        }
      });
    }
  }

  double _scrollIndicatorBottomOffset(BuildContext context) {
    return scrollIndicatorBottomOffset(context);
  }

  bool _loadingProducts = false;
  bool _productsReloadQueued = false;

  Future<void> _loadProdutosComDesconto({
    bool showLoadingIndicator = true,
  }) async {
    if (!mounted) return;
    if (_loadingProducts) {
      _productsReloadQueued = true;
      return;
    }
    _loadingProducts = true;
    if (showLoadingIndicator) setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('produtos')
          .select('*, categorias!categoria_id(nome, icone)')
          .not('preco_anterior', 'is', null)
          .order('created_at', ascending: false);

      final produtos =
          List<Map<String, dynamic>>.from(response).map((produto) {
            final rawCategoria = produto['categorias'];
            final categoria = rawCategoria is Map
                ? Map<String, dynamic>.from(rawCategoria)
                : null;
            return {
              ...produto,
              'categoria_nome': categoria?['nome'] ?? produto['categoria_nome'],
              'categoria_icone':
                  categoria?['icone'] ?? produto['categoria_icone'],
            };
          }).toList()..sort((a, b) {
            final aPriority = a['ativo'] == false ? 1 : 0;
            final bPriority = b['ativo'] == false ? 1 : 0;
            return aPriority.compareTo(bPriority);
          });

      if (!mounted) return;
      setState(() {
        final isAdmin = AdminStatusProvider.of(context)?.isAdmin ?? false;
        _produtosComDesconto = produtos
            .where(
              (p) => AppSettingsService.isProductVisible(p, isAdmin: isAdmin),
            )
            .toList();
      });
      _scheduleScrollIndicatorAvailabilityChecks();
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
      _loadingProducts = false;
      if (mounted) {
        setState(() => _isLoading = false);
        if (_productsReloadQueued) {
          _productsReloadQueued = false;
          _scheduleProductsRefresh();
        }
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

  bool _isProductAvailable(Map<String, dynamic> produto) {
    return produto['ativo'] != false;
  }

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

  void _hideScrollIndicator() {
    if (!_showScrollIndicator) return;

    _scrollIndicatorController.stop(canceled: true);
    _scrollIndicatorController.value = 0;
    setState(() => _showScrollIndicator = false);
  }

  void _startScrollIndicatorHint() {
    if (_isScrollIndicatorAnimating ||
        !_showScrollIndicator ||
        _hasScrolledDown) {
      return;
    }

    _isScrollIndicatorAnimating = true;
    unawaited(() async {
      try {
        while (mounted && _showScrollIndicator && !_hasScrolledDown) {
          await _scrollIndicatorController.forward(from: 0).orCancel;
          if (!mounted || !_showScrollIndicator || _hasScrolledDown) {
            break;
          }
          await _scrollIndicatorController.reverse().orCancel;
        }
      } on TickerCanceled {
        // Interrupcao esperada quando o indicador e ocultado.
      } finally {
        _isScrollIndicatorAnimating = false;
        if (mounted) {
          _scrollIndicatorController.value = 0;
        }
      }
    }());
  }

  void _updateScrollIndicatorAvailability() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_hasScrolledDown) return;

      final canScroll = _scrollController.position.maxScrollExtent > 24;
      if (canScroll) {
        if (!_showScrollIndicator) {
          setState(() => _showScrollIndicator = true);
        }
        _startScrollIndicatorHint();
      } else if (!canScroll && _showScrollIndicator) {
        _hideScrollIndicator();
      }
    });
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

  Map<String, dynamic> _getDisplayPriceInfo(Map<String, dynamic> produto) {
    final tamanhos = ProductVariantUtils.extractSizes(produto['tamanhos']);
    final precoAnterior = ProductVariantUtils.toDouble(
      produto['preco_anterior'],
    );

    if (tamanhos.isNotEmpty) {
      final precos = <double>{};
      for (final tamanho in tamanhos) {
        final precoTamanho =
            ProductVariantUtils.toDouble(tamanho['preco']) ?? 0.0;
        if (precoTamanho > 0) precos.add(precoTamanho);
      }

      if (precos.isEmpty) {
        return {
          'currentPrice': null,
          'previousPrice': null,
          'hasDiscount': false,
          'hasMultiplePrices': false,
        };
      }

      final menorPreco = precos.reduce((a, b) => a < b ? a : b);
      final hasDiscount = precoAnterior != null && precoAnterior > menorPreco;

      return {
        'currentPrice': menorPreco,
        'previousPrice': hasDiscount ? precoAnterior : null,
        'hasDiscount': hasDiscount,
        'hasMultiplePrices': tamanhos.length > 1,
      };
    }

    final precoAtual = ProductVariantUtils.toDouble(produto['preco']);
    final hasDiscount =
        precoAnterior != null &&
        precoAtual != null &&
        precoAnterior > precoAtual;

    return {
      'currentPrice': precoAtual,
      'previousPrice': hasDiscount ? precoAnterior : null,
      'hasDiscount': hasDiscount,
      'hasMultiplePrices': false,
    };
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
    if (!_isProductAvailable(produto)) {
      _showUnavailableProductMessage();
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(produto: produto),
      ),
    );
    if (result == 'go_to_cart' && mounted) {
      _openCartPage();
    }
  }

  void _addToCart(Map<String, dynamic> produto) {
    if (!_isProductAvailable(produto)) {
      _showUnavailableProductMessage();
      return;
    }

    ProductActionHelper.addToCart(
      context: context,
      cartService: _cartService,
      produto: produto,
      onViewCart: _openCartPage,
    );
  }

  void _showAdminOptions(Map<String, dynamic> produto) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
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
                  produto['nome']?.toString() ?? 'Produto',
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
                    _showEditProductDialog(produto);
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
                    _showDeleteConfirmation(produto);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditProductDialog(Map<String, dynamic> produto) async {
    try {
      final response = await Supabase.instance.client
          .from('categorias')
          .select()
          .order('ordem', ascending: true)
          .order('id');

      final categorias = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => EditProductDialog(
          produto: produto,
          categorias: categorias,
          onProductUpdated: () {
            _loadProdutosComDesconto();
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

  Future<void> _showDeleteConfirmation(Map<String, dynamic> produto) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir o produto "${produto['nome']}"?',
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
      await _deleteProduct(produto);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> produto) async {
    try {
      await Supabase.instance.client
          .from('produtos')
          .delete()
          .eq('id', produto['id']);

      CatalogSyncService.instance.notifyCatalogChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadProdutosComDesconto();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir produto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double _getDiscountPercentage(Map<String, dynamic> produto) {
    final priceInfo = _getDisplayPriceInfo(produto);
    final previousPrice = priceInfo['previousPrice'] as double?;
    final currentPrice = priceInfo['currentPrice'] as double?;

    if (previousPrice == null || currentPrice == null || previousPrice <= 0) {
      return 0;
    }

    return _calcularPercentualDesconto(previousPrice, currentPrice);
  }

  List<Map<String, dynamic>> get _sortedProdutosComDesconto {
    final produtos = List<Map<String, dynamic>>.from(_produtosComDesconto);

    produtos.sort((a, b) {
      final aPriority = a['ativo'] == false ? 1 : 0;
      final bPriority = b['ativo'] == false ? 1 : 0;
      final availabilityCompare = aPriority.compareTo(bPriority);
      if (availabilityCompare != 0) {
        return availabilityCompare;
      }

      switch (_sortOption) {
        case DiscountSortOption.alphabetical:
          return (a['nome']?.toString() ?? '').toLowerCase().compareTo(
            (b['nome']?.toString() ?? '').toLowerCase(),
          );
        case DiscountSortOption.latest:
          final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
          final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        case DiscountSortOption.biggestDiscount:
          final discountCompare = _getDiscountPercentage(
            b,
          ).compareTo(_getDiscountPercentage(a));
          if (discountCompare != 0) {
            return discountCompare;
          }
          final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
          final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
      }
    });

    return produtos;
  }

  Future<void> _buyNow(Map<String, dynamic> produto) async {
    if (!_isProductAvailable(produto)) {
      _showUnavailableProductMessage();
      return;
    }

    await ProductActionHelper.buyNow(
      context: context,
      cartService: _cartService,
      produto: produto,
    );
  }

  Widget _buildDiscountProductCard(Map<String, dynamic> produto) {
    final rawCategoria = produto['categorias'];
    final categoria = rawCategoria is Map
        ? Map<String, dynamic>.from(rawCategoria)
        : produto['categoria_nome'] != null
        ? {
            'nome': produto['categoria_nome'],
            'icone': produto['categoria_icone'],
          }
        : null;
    final isAvailable = _isProductAvailable(produto);
    final priceInfo = _getDisplayPriceInfo(produto);
    final precoAtual = priceInfo['currentPrice'] as double?;
    final precoAnterior = priceInfo['previousPrice'] as double?;
    final hasDiscount = priceInfo['hasDiscount'] as bool;
    final hasMultiplePrices = priceInfo['hasMultiplePrices'] as bool;
    final flavorCount = ProductVariantUtils.extractFlavors(
      produto['sabores'],
    ).length;
    final percentualDesconto = hasDiscount && precoAtual != null
        ? _calcularPercentualDesconto(precoAnterior, precoAtual)
        : 0.0;
    final discountLabel = hasDiscount
        ? '${percentualDesconto.toInt()}% OFF'
        : 'OFERTA';

    final isAdmin = AdminStatusProvider.of(context)?.isAdmin ?? false;

    return GestureDetector(
      onTap: () => _navigateToProductDetail(produto),
      onLongPress: isAdmin ? () => _showAdminOptions(produto) : null,
      child: ColorFiltered(
        colorFilter: isAvailable
            ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
            : const ColorFilter.matrix(_grayscaleMatrix),
        child: Opacity(
          opacity: isAvailable ? 1 : 0.82,
          child: Card(
            margin: const EdgeInsets.only(bottom: 14),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageSize = constraints.maxWidth < 360 ? 92.0 : 108.0;

                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildDiscountProductImage(
                            produto: produto,
                            categoria: categoria,
                            size: imageSize,
                          ),
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[700],
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                discountLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: produto['nome'] ?? 'Produto',
                                        ),
                                        if (flavorCount > 1)
                                          flavorCountBadgeSpan(
                                            flavorCount,
                                            fontSize: 10,
                                            iconSize: 11,
                                          ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      height: 1.15,
                                      decoration: isAvailable
                                          ? TextDecoration.none
                                          : TextDecoration.lineThrough,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (categoria != null) ...[
                                  const SizedBox(width: 8),
                                  _buildDiscountCategoryChip(categoria),
                                ],
                              ],
                            ),
                            if (produto['descricao'] != null &&
                                produto['descricao']
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                produto['descricao'].toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            _buildDiscountPriceBlock(
                              precoAtual: precoAtual,
                              precoAnterior: precoAnterior,
                              hasDiscount: hasDiscount,
                              hasMultiplePrices: hasMultiplePrices,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 38,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _buyNow(produto),
                                      icon: const Icon(
                                        Icons.shopping_bag,
                                        size: 15,
                                      ),
                                      label: const Text('Comprar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 38,
                                  width: 48,
                                  child: OutlinedButton(
                                    onPressed: () => _addToCart(produto),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black,
                                      side: const BorderSide(
                                        color: Colors.black,
                                      ),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.add_shopping_cart,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountCategoryChip(Map<String, dynamic> categoria) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CategoryIconWidget(
              icone: categoria['icone'] ?? '📦',
              categoryName: categoria['nome']?.toString(),
              size: 13,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              categoria['nome'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountProductImage({
    required Map<String, dynamic> produto,
    required Map<String, dynamic>? categoria,
    required double size,
  }) {
    final images = ProductVariantUtils.productImages(produto);
    final categoryPlaceholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.58,
          height: size * 0.58,
          child: CategoryIconWidget(
            icone: categoria?['icone'] ?? produto['categoria_icone'] ?? '🍰',
            categoryName:
                categoria?['nome']?.toString() ??
                produto['categoria_nome']?.toString(),
            size: 58,
          ),
        ),
      ),
    );

    if (images.isEmpty) return categoryPlaceholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[50],
        child: Image.network(
          images.first,
          fit: BoxFit.contain,
          cacheWidth: (size * 2).round(),
          cacheHeight: (size * 2).round(),
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => categoryPlaceholder,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDiscountPriceBlock({
    required double? precoAtual,
    required double? precoAnterior,
    required bool hasDiscount,
    required bool hasMultiplePrices,
  }) {
    if (precoAtual == null) {
      return const Text(
        'Sem preço',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDiscount && precoAnterior != null)
              Text(
                _formatPrice(precoAnterior),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            Text(
              hasMultiplePrices ? 'A partir de' : 'Preço',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              _formatPrice(precoAtual),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: hasDiscount ? Colors.orange[800] : Colors.green[700],
                height: 1.08,
              ),
            ),
          ],
        ),
        if (hasDiscount && precoAnterior != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[100]!),
            ),
            child: Text(
              'Economize ${_formatPrice(precoAnterior - precoAtual)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green[800],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
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
      padding: EdgeInsets.zero,
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
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _loadProdutosComDesconto,
                  child: ListView.builder(
                    controller: _scrollController,
                    addRepaintBoundaries: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _sortedProdutosComDesconto.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            height: 50,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: ChoiceChip(
                                    selected:
                                        _sortOption ==
                                        DiscountSortOption.biggestDiscount,
                                    showCheckmark: false,
                                    label: const Text('Maiores descontos'),
                                    avatar: const Icon(
                                      Icons.local_fire_department,
                                      size: 18,
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        _sortOption =
                                            DiscountSortOption.biggestDiscount;
                                      });
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: ChoiceChip(
                                    selected:
                                        _sortOption ==
                                        DiscountSortOption.latest,
                                    showCheckmark: false,
                                    label: const Text('Últimos lançamentos'),
                                    avatar: const Icon(
                                      Icons.schedule,
                                      size: 18,
                                    ),
                                    onSelected: (_) {
                                      setState(() {
                                        _sortOption = DiscountSortOption.latest;
                                      });
                                    },
                                  ),
                                ),
                                ChoiceChip(
                                  selected:
                                      _sortOption ==
                                      DiscountSortOption.alphabetical,
                                  showCheckmark: false,
                                  label: const Text('Ordem alfabética'),
                                  avatar: const Icon(
                                    Icons.sort_by_alpha,
                                    size: 18,
                                  ),
                                  onSelected: (_) {
                                    setState(() {
                                      _sortOption =
                                          DiscountSortOption.alphabetical;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final produto = _sortedProdutosComDesconto[index - 1];
                      return _buildDiscountProductCard(produto);
                    },
                  ),
                ),
                if (_showScrollIndicator)
                  Positioned(
                    bottom: _scrollIndicatorBottomOffset(context),
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: ScrollDownIndicator(
                        animation: _scrollIndicatorController,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../providers/admin_status_provider.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';
import '../services/cart_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/main_navigation_service.dart';
import '../utils/product_action_helper.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

enum DiscountSortOption { biggestDiscount, latest, alphabetical }

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

class _DescontosScreenState extends State<DescontosScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _produtosComDesconto = [];
  bool _isLoading = true;
  final CartService _cartService = CartService();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _scrollIndicatorController;
  RealtimeChannel? _productsChannel;
  Timer? _realtimeDebounceTimer;
  bool _showScrollIndicator = true;
  bool _hasScrolledDown = false;
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
    _scrollIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
    _loadProdutosComDesconto();
    _setupRealtimeSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollIndicatorAvailabilityChecks();
    });
  }

  @override
  void dispose() {
    _realtimeDebounceTimer?.cancel();
    CatalogSyncService.instance.removeListener(_catalogSyncListener);
    if (_productsChannel != null) {
      Supabase.instance.client.removeChannel(_productsChannel!);
    }
    _scrollController.dispose();
    _scrollIndicatorController.dispose();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    try {
      _productsChannel = Supabase.instance.client
          .channel('descontos-produtos-changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'produtos',
            callback: (_) => _scheduleProductsRefresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Erro ao configurar realtime de descontos: $e');
    }
  }

  void _scheduleProductsRefresh() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _loadProdutosComDesconto();
      }
    });
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
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return safeBottom + 88;
  }

  Future<void> _loadProdutosComDesconto() async {
    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('produtos')
          .select('*, categorias!categoria_id(nome, icone)')
          .not('preco_anterior', 'is', null)
          .order('created_at', ascending: false);

      final produtos = List<Map<String, dynamic>>.from(response)
        ..sort((a, b) {
          final aPriority = a['ativo'] == false ? 1 : 0;
          final bPriority = b['ativo'] == false ? 1 : 0;
          return aPriority.compareTo(bPriority);
        });

      setState(() {
        _produtosComDesconto = produtos;
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

    _scrollIndicatorController.stop();
    setState(() => _showScrollIndicator = false);
  }

  void _updateScrollIndicatorAvailability() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_hasScrolledDown) return;

      final canScroll = _scrollController.position.maxScrollExtent > 24;
      if (canScroll && !_showScrollIndicator) {
        _scrollIndicatorController.repeat(reverse: true);
        setState(() => _showScrollIndicator = true);
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
    final tamanhos = produto['tamanhos'];
    final precoAnterior = produto['preco_anterior']?.toDouble();

    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      final precos = <double>{};
      for (final tamanho in tamanhos) {
        final precoTamanho = tamanho['preco']?.toDouble() ?? 0.0;
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

    final precoAtual = produto['preco']?.toDouble();
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
                      final categoria = produto['categorias'];
                      final isAvailable = _isProductAvailable(produto);
                      final priceInfo = _getDisplayPriceInfo(produto);
                      final precoAtual = priceInfo['currentPrice'] as double?;
                      final precoAnterior =
                          priceInfo['previousPrice'] as double?;
                      final hasDiscount = priceInfo['hasDiscount'] as bool;
                      final hasMultiplePrices =
                          priceInfo['hasMultiplePrices'] as bool;
                      final percentualDesconto =
                          hasDiscount && precoAtual != null
                          ? _calcularPercentualDesconto(
                              precoAnterior,
                              precoAtual,
                            )
                          : 0.0;

                      return GestureDetector(
                        onTap: () => _navigateToProductDetail(produto),
                        child: ColorFiltered(
                          colorFilter: isAvailable
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                )
                              : const ColorFilter.matrix(_grayscaleMatrix),
                          child: Opacity(
                            opacity: isAvailable ? 1 : 0.82,
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
                                    colors: [
                                      Colors.red[50]!,
                                      Colors.orange[50]!,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              hasDiscount
                                                  ? '${percentualDesconto.toInt()}% OFF'
                                                  : 'OFERTA',
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        _buildCategoryIconWidget(
                                                          categoria['icone'] ??
                                                              '📦',
                                                          size: 14,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    categoria['nome'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Center(
                                        child:
                                            (produto['imagens'] != null &&
                                                produto['imagens'] is List &&
                                                (produto['imagens'] as List)
                                                    .isNotEmpty)
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  (produto['imagens'] as List)
                                                      .first,
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 240,
                                                  cacheHeight: 240,
                                                  filterQuality:
                                                      FilterQuality.medium,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
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
                                                        if (loadingProgress ==
                                                            null) {
                                                          return child;
                                                        }
                                                        return Container(
                                                          width: 120,
                                                          height: 120,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey[200],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
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
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  produto['imagem_url'],
                                                  width: 120,
                                                  height: 120,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 240,
                                                  cacheHeight: 240,
                                                  filterQuality:
                                                      FilterQuality.medium,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Container(
                                                          width: 120,
                                                          height: 120,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey[200],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: const Icon(
                                                            Icons
                                                                .image_not_supported,
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
                                                        if (loadingProgress ==
                                                            null) {
                                                          return child;
                                                        }
                                                        return Container(
                                                          width: 120,
                                                          height: 120,
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey[200],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                ),
                                              )
                                            : _buildEmojiPlaceholder(categoria),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        produto['nome'] ?? 'Produto',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          decoration: isAvailable
                                              ? TextDecoration.none
                                              : TextDecoration.lineThrough,
                                        ),
                                      ),
                                      if (produto['descricao'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
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
                                      if (precoAtual == null)
                                        const Text(
                                          'Sem preço',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey,
                                          ),
                                        )
                                      else
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (hasDiscount &&
                                                    precoAnterior != null)
                                                  Text(
                                                    _formatPrice(precoAnterior),
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[600],
                                                      decoration: TextDecoration
                                                          .lineThrough,
                                                    ),
                                                  ),
                                                Text(
                                                  hasMultiplePrices
                                                      ? 'A partir de'
                                                      : 'Preço',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                Text(
                                                  _formatPrice(precoAtual),
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: hasDiscount
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const Spacer(),
                                            if (hasDiscount &&
                                                precoAnterior != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green[100],
                                                  borderRadius:
                                                      BorderRadius.circular(8),
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
                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 40,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    _buyNow(produto),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.black,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SizedBox(
                                              height: 40,
                                              child: OutlinedButton(
                                                onPressed: () =>
                                                    _addToCart(produto),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.black,
                                                  side: const BorderSide(
                                                    color: Colors.black,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: const [
                                                      Icon(
                                                        Icons.add_shopping_cart,
                                                        size: 16,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Carrinho',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
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
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_showScrollIndicator)
                  Positioned(
                    bottom: _scrollIndicatorBottomOffset(context),
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _scrollIndicatorController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              0,
                              -8 * _scrollIndicatorController.value,
                            ),
                            child: child,
                          );
                        },
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Role para baixo',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
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

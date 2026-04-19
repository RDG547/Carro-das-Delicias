import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/favorites_service.dart';
import '../utils/constants.dart';
import '../utils/app_snackbar.dart';
import '../widgets/favorite_heart_animation.dart';
import '../widgets/category_icon_widget.dart';
import '../widgets/scroll_down_indicator.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> produto;

  const ProductDetailScreen({super.key, required this.produto});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  final _observacoesController = TextEditingController();
  int _quantidade = 1;
  final _cartService = CartService();
  final _favoritesService = FavoritesService();
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentImageIndex = 0;
  bool _showScrollIndicator = true;
  bool _isScrollIndicatorAnimating = false;
  late final AnimationController _scrollIndicatorController;
  RealtimeChannel? _productsChannel;
  Timer? _similarProductsRefreshDebounce;
  late final VoidCallback _catalogSyncListener;
  bool _hasScrolledDown = false;
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

  // Tamanho selecionado (para produtos com múltiplos tamanhos)
  Map<String, dynamic>? _selectedSize;

  // Cache de produtos semelhantes para evitar recarregar
  List<Map<String, dynamic>>? _cachedSimilarProducts;

  @override
  void initState() {
    super.initState();
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
    // Se o produto tem tamanhos, selecionar o primeiro por padrão
    final tamanhos = widget.produto['tamanhos'];
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      _selectedSize = tamanhos[0];
    }
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.loadFavorites();
    _catalogSyncListener = () {
      _scheduleSimilarProductsRefresh();
    };
    CatalogSyncService.instance.addListener(_catalogSyncListener);
    _setupRealtimeSubscription();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollIndicatorAvailabilityChecks();
    });
  }

  @override
  void dispose() {
    _favoritesService.removeListener(_onFavoritesChanged);
    CatalogSyncService.instance.removeListener(_catalogSyncListener);
    _similarProductsRefreshDebounce?.cancel();
    if (_productsChannel != null) {
      Supabase.instance.client.removeChannel(_productsChannel!);
    }
    _observacoesController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _scrollIndicatorController.dispose();
    super.dispose();
  }

  String _getObservacaoPlaceholder() {
    return 'Escreva uma observação... (opcional)';
  }

  void _onFavoritesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setupRealtimeSubscription() {
    try {
      _productsChannel = Supabase.instance.client
          .channel('product-detail-products-changes-${widget.produto['id']}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'produtos',
            callback: (_) => _scheduleSimilarProductsRefresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Erro ao configurar realtime dos detalhes: $e');
    }
  }

  void _scheduleSimilarProductsRefresh() {
    _similarProductsRefreshDebounce?.cancel();
    _similarProductsRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () {
        if (!mounted) return;

        setState(() {
          _cachedSimilarProducts = null;
        });
        _scheduleScrollIndicatorAvailabilityChecks();
      },
    );
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

  bool _isFavorite(Map<String, dynamic> produto) {
    return _favoritesService.isFavorite(produto['id'].toString());
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
    setState(() {
      _showScrollIndicator = false;
    });
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
          setState(() {
            _showScrollIndicator = true;
          });
        }
        _startScrollIndicatorHint();
      } else if (!canScroll && _showScrollIndicator) {
        _hideScrollIndicator();
      }
    });
  }

  void _showAddedToCartSnackBar(String message) {
    AppSnackBar.showCartAdded(
      context,
      message: message,
      onViewCart: () => Navigator.of(context).pop('go_to_cart'),
      bottomSpacing: 8,
    );
  }

  Future<void> _toggleFavorite(Map<String, dynamic> produto) async {
    final productId = produto['id'].toString();
    final wasFavorite = _favoritesService.isFavorite(productId);
    final overlay = Overlay.of(context);

    await _favoritesService.toggleFavorite(productId);

    if (mounted) {
      FavoriteHeartAnimation.showWithOverlay(
        overlay,
        isFavoriting: !wasFavorite,
      );

      AppSnackBar.showTop(
        context,
        duration: const Duration(seconds: 2),
        backgroundColor: wasFavorite ? Colors.grey.shade700 : Colors.pink,
        topSpacing: 36,
        content: Row(
          children: [
            Icon(
              wasFavorite ? Icons.heart_broken : Icons.favorite,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                wasFavorite
                    ? 'Removido dos favoritos'
                    : '${produto['nome']} adicionado aos favoritos!',
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // App Bar com imagem do produto
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: Colors.black,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildProductImage(),
                ),
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isFavorite(widget.produto)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _isFavorite(widget.produto)
                            ? Colors.pink
                            : Colors.black87,
                      ),
                      onPressed: () => _toggleFavorite(widget.produto),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share, color: Colors.black87),
                      onPressed: _shareProduct,
                    ),
                  ),
                ],
              ),

              // Conteúdo principal
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Indicador visual
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Nome e categoria
                        _buildProductHeader(),
                        const SizedBox(height: 16),

                        // Seletor de tamanho (se houver múltiplos tamanhos)
                        _buildSizeSelector(),

                        // Preço
                        _buildPriceSection(),
                        const SizedBox(height: 16),

                        // Badges (mais vendido, novidade, promoção)
                        _buildBadges(),
                        const SizedBox(height: 16),

                        // Descrição
                        _buildDescription(),
                        const SizedBox(height: 20),

                        // Contador de quantidade
                        _buildQuantitySelector(),
                        const SizedBox(height: 24),

                        // Campo de observações
                        _buildObservationsField(),
                        const SizedBox(height: 24),

                        // Produtos semelhantes
                        _buildSimilarProducts(),
                        const SizedBox(height: 20), // Espaço para o botão fixo
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showScrollIndicator && !keyboardVisible)
            Positioned(
              bottom: 16,
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
      bottomNavigationBar: keyboardVisible ? null : _buildBottomBar(),
    );
  }

  Widget _buildProductImage() {
    // Obter lista de imagens
    final List<String> imagens = [];

    // Adicionar imagens do array 'imagens'
    if (widget.produto['imagens'] != null &&
        widget.produto['imagens'] is List) {
      for (var img in widget.produto['imagens']) {
        if (img != null && img.toString().isNotEmpty) {
          imagens.add(img.toString());
        }
      }
    }

    // Se não houver imagens no array, usar imagem_url
    if (imagens.isEmpty &&
        widget.produto['imagem_url'] != null &&
        widget.produto['imagem_url'].toString().isNotEmpty) {
      imagens.add(widget.produto['imagem_url'].toString());
    }

    // Se não houver imagens, mostrar placeholder
    if (imagens.isEmpty) {
      return _buildPlaceholderImage();
    }

    // Se houver apenas uma imagem, mostrar diretamente
    if (imagens.length == 1) {
      return GestureDetector(
        onTap: () => _showImageFullScreen(imagens[0]),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.grey[100]!, Colors.white],
            ),
          ),
          child: Image.network(
            imagens[0],
            fit: BoxFit.cover,
            cacheWidth: 800,
            cacheHeight: 800,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholderImage(),
          ),
        ),
      );
    }

    // Se houver múltiplas imagens, usar PageView
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentImageIndex = index;
            });
          },
          itemCount: imagens.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _showImageFullScreen(imagens[index]),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.grey[100]!, Colors.white],
                  ),
                ),
                child: Image.network(
                  imagens[index],
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  cacheHeight: 800,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildPlaceholderImage(),
                ),
              ),
            );
          },
        ),

        // Indicador de página
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              imagens.length,
              (index) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentImageIndex == index
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[100]!, Colors.pink[100]!],
        ),
      ),
      child: const Center(
        child: Icon(Icons.fastfood, size: 80, color: Colors.white),
      ),
    );
  }

  Widget _buildProductHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Categoria acima do nome, centralizada
        if (widget.produto['categoria_nome'] != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CategoryIconWidget(
                      icone: widget.produto['categoria_icone'] ?? '📦',
                      categoryName: widget.produto['categoria_nome'],
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.produto['categoria_nome'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Nome do produto
        Text(
          widget.produto['nome'] ?? 'Produto sem nome',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),

        // Divisória
        Divider(thickness: 1, color: Colors.grey[300], height: 1),
      ],
    );
  }

  Widget _buildSizeSelector() {
    final tamanhos = widget.produto['tamanhos'];

    // Se não tem tamanhos, não mostrar nada
    if (tamanhos == null || tamanhos is! List || tamanhos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Escolha o tamanho',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tamanhos.map<Widget>((tamanho) {
            final isSelected = _selectedSize == tamanho;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSize = tamanho;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.purple[100] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.purple : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      tamanho['nome'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected ? Colors.purple[700] : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.format(tamanho['preco'] ?? 0.0),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.purple[700]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPriceSection() {
    final tamanhos = widget.produto['tamanhos'];
    final preco = widget.produto['preco'];
    final precoAnterior = widget.produto['preco_anterior'];

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Sem preço',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black54,
            ),
          ),
        );
      }

      // Verificar se o PRODUTO tem desconto (não os tamanhos individuais)
      final produtoPreco = preco?.toDouble();
      final produtoPrecoAnterior = precoAnterior?.toDouble();
      final hasDesconto =
          produtoPrecoAnterior != null &&
          produtoPreco != null &&
          produtoPrecoAnterior > produtoPreco;

      // Calcular percentual de desconto baseado no produto principal
      int percentualDesconto = 0;
      if (hasDesconto) {
        percentualDesconto =
            ((produtoPrecoAnterior - produtoPreco) / produtoPrecoAnterior * 100)
                .toInt();
      }

      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Coluna com "A partir de" e preço
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'A partir de',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasDesconto
                          ? [Colors.orange, Colors.deepOrange]
                          : [Colors.green, Colors.teal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (hasDesconto ? Colors.orange : Colors.green)
                            .withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    CurrencyFormatter.format(menorPreco),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
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
            ),
            // Badge ao lado do preço
            if (hasDesconto) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$percentualDesconto% OFF',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Se não há preço, retorna sem preço
    if (preco == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Sem preço',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
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

      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preço anterior riscado
            Text(
              CurrencyFormatter.format(precoAnterior),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(height: 4),
            // Preço com desconto e badge ao lado
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    CurrencyFormatter.format(precoAtual),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
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
                const SizedBox(width: 8),
                // Badge de desconto ao lado
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$percentualDesconto% OFF',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Preço normal
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          CurrencyFormatter.format(precoAtual),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
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
    );
  }

  Widget _buildBadges() {
    List<Widget> badges = [];

    if (widget.produto['mais_vendido'] == true) {
      badges.add(_buildBadge('🔥 Mais Vendido', Colors.red));
    }

    if (widget.produto['novidade'] == true) {
      badges.add(_buildBadge('✨ Novidade', Colors.purple));
    }

    // Removido badge de promoção pois já é mostrado ao lado do preço

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: badges);
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildDescription() {
    final description = widget.produto['descricao']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Descrição',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description.isNotEmpty
              ? description
              : 'Este delicioso produto é preparado com ingredientes especiais e muito carinho para proporcionar uma experiência única.',
          style: TextStyle(fontSize: 16, color: Colors.grey[700], height: 1.5),
        ),
      ],
    );
  }

  Widget _buildQuantitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quantidade',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildQuantityButton(
              icon: Icons.remove,
              onPressed: _quantidade > 1
                  ? () {
                      setState(() {
                        _quantidade--;
                      });
                    }
                  : null,
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _quantidade.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildQuantityButton(
              icon: Icons.add,
              onPressed: () {
                setState(() {
                  _quantidade++;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: onPressed != null ? Colors.orange[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: onPressed != null ? Colors.orange[700] : Colors.grey[400],
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildObservationsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Observações',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: _observacoesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: _getObservacaoPlaceholder(),
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimilarProducts() {
    final categoriaId = widget.produto['categoria_id'];
    final produtoAtualId = widget.produto['id'];

    if (categoriaId == null) {
      return const SizedBox.shrink();
    }

    // Se já carregou produtos, usar cache
    if (_cachedSimilarProducts != null) {
      _scheduleScrollIndicatorAvailabilityChecks();
      return _buildSimilarProductsWidget(_cachedSimilarProducts!);
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchSimilarProducts(categoriaId, produtoAtualId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint(
            'Erro ao carregar produtos semelhantes: ${snapshot.error}',
          );
          return const SizedBox.shrink();
        }

        final produtos = snapshot.data ?? [];
        // Armazenar em cache
        _cachedSimilarProducts = produtos;
        _scheduleScrollIndicatorAvailabilityChecks();

        return _buildSimilarProductsWidget(produtos);
      },
    );
  }

  Widget _buildSimilarProductsWidget(List<Map<String, dynamic>> produtos) {
    if (produtos.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Produtos Semelhantes',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Nenhum produto semelhante encontrado nesta categoria.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Produtos Semelhantes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 312,
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: 0,
            maxWidth: MediaQuery.of(context).size.width,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 20, right: 20),
                itemCount: produtos.length,
                itemBuilder: (context, index) {
                  final produto = produtos[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 8,
                      right: index == produtos.length - 1 ? 0 : 8,
                    ),
                    child: SizedBox(
                      width: 200,
                      child: _buildSimilarProductCard(produto),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSimilarProducts(
    int categoriaId,
    int produtoAtualId,
  ) async {
    try {
      debugPrint('📡 Buscando produtos semelhantes da categoria $categoriaId');
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('produtos')
          .select(
            'id, nome, descricao, preco, preco_anterior, promocao, imagens, tamanhos, categoria_id, ativo',
          )
          .eq('categoria_id', categoriaId)
          .neq('id', produtoAtualId)
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(10);

      final produtos = (response as List).cast<Map<String, dynamic>>()
        ..sort((a, b) {
          final aPriority = a['ativo'] == false ? 1 : 0;
          final bPriority = b['ativo'] == false ? 1 : 0;
          return aPriority.compareTo(bPriority);
        });
      debugPrint('✅ Encontrados ${produtos.length} produtos semelhantes');
      return produtos;
    } catch (e) {
      debugPrint('❌ Erro ao buscar produtos semelhantes: $e');
    }
    return [];
  }

  Widget _buildSimilarProductCard(Map<String, dynamic> produto) {
    final imagens = produto['imagens'];
    final hasImage = imagens is List && imagens.isNotEmpty;
    final isAvailable = _isProductAvailable(produto);

    return GestureDetector(
      onTap: () async {
        if (!isAvailable) {
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
          Navigator.of(context).pop('go_to_cart');
        }
      },
      child: ColorFiltered(
        colorFilter: isAvailable
            ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
            : const ColorFilter.matrix(_grayscaleMatrix),
        child: Opacity(
          opacity: isAvailable ? 1 : 0.82,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagem
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: hasImage
                          ? Image.network(
                              imagens[0],
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 120,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.orange[100]!,
                                        Colors.pink[100]!,
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.fastfood,
                                      size: 50,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.orange[100]!,
                                    Colors.pink[100]!,
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.fastfood,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => _toggleFavorite(produto),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isFavorite(produto)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _isFavorite(produto)
                                ? Colors.pink
                                : Colors.grey,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nome
                        Text(
                          produto['nome'] ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            decoration: isAvailable
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Descrição
                        if (produto['descricao'] != null &&
                            produto['descricao'].toString().isNotEmpty)
                          Text(
                            produto['descricao'],
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        // Preço
                        _buildSimilarProductPrice(produto),
                        const Spacer(),
                        // Botão adicionar
                        SizedBox(
                          width: double.infinity,
                          height: 30,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (!isAvailable) {
                                _showUnavailableProductMessage();
                                return;
                              }

                              try {
                                await _cartService.addItem(
                                  produto,
                                  quantidade: 1,
                                );
                                if (mounted) {
                                  _showAddedToCartSnackBar(
                                    '${produto['nome']} adicionado ao carrinho!',
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao adicionar: $e'),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_shopping_cart, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Adicionar',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
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
    );
  }

  Widget _buildSimilarProductPrice(Map<String, dynamic> produto) {
    final priceInfo = _getDisplayPriceInfo(produto);
    final currentPrice = priceInfo['currentPrice'] as double?;
    final previousPrice = priceInfo['previousPrice'] as double?;
    final hasDiscount = priceInfo['hasDiscount'] as bool;
    final hasMultiplePrices = priceInfo['hasMultiplePrices'] as bool;
    final isPromotion = priceInfo['isPromotion'] as bool;
    final discountPercentage = priceInfo['discountPercentage'] as int?;

    if (currentPrice == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Sem preço',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (previousPrice != null)
          Text(
            CurrencyFormatter.format(previousPrice),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              decoration: TextDecoration.lineThrough,
            ),
          ),
        Text(
          hasMultiplePrices ? 'A partir de' : 'Preço',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: hasDiscount || isPromotion
                      ? [Colors.orange, Colors.deepOrange]
                      : [Colors.green, Colors.teal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color:
                        (hasDiscount || isPromotion
                                ? Colors.orange
                                : Colors.green)
                            .withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                CurrencyFormatter.format(currentPrice),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
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
            const SizedBox(width: 8),
            if (hasDiscount && discountPercentage != null)
              _buildCompactDiscountChip('$discountPercentage% OFF')
            else if (isPromotion)
              _buildCompactDiscountChip('PROMOÇÃO', color: Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactDiscountChip(String text, {Color color = Colors.orange}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Map<String, dynamic> _getDisplayPriceInfo(Map<String, dynamic> produto) {
    final tamanhos = _extractSizes(produto['tamanhos']);
    final precoAnterior = _toDouble(produto['preco_anterior']);
    final precoAtual = _toDouble(produto['preco']);
    final isPromotion = produto['promocao'] == true;

    if (tamanhos.isNotEmpty) {
      final precos = <double>{};
      for (final tamanho in tamanhos) {
        final precoTamanho = _toDouble(tamanho['preco']) ?? 0.0;
        if (precoTamanho > 0) {
          precos.add(precoTamanho);
        }
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
      final discountPercentage = hasDiscount
          ? ((precoAnterior - menorPreco) / precoAnterior * 100).round()
          : null;

      return {
        'currentPrice': menorPreco,
        'previousPrice': hasDiscount ? precoAnterior : null,
        'hasDiscount': hasDiscount,
        'hasMultiplePrices': tamanhos.length > 1 || precos.length > 1,
        'isPromotion': isPromotion,
        'discountPercentage': discountPercentage,
      };
    }

    final hasDiscount =
        precoAnterior != null &&
        precoAtual != null &&
        precoAnterior > precoAtual;
    final discountPercentage = hasDiscount
        ? ((precoAnterior - precoAtual) / precoAnterior * 100).round()
        : null;

    return {
      'currentPrice': precoAtual,
      'previousPrice': hasDiscount ? precoAnterior : null,
      'hasDiscount': hasDiscount,
      'hasMultiplePrices': false,
      'isPromotion': isPromotion,
      'discountPercentage': discountPercentage,
    };
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  List<Map<String, dynamic>> _extractSizes(dynamic rawSizes) {
    dynamic parsed = rawSizes;

    if (parsed is String && parsed.trim().isNotEmpty) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return const [];
      }
    }

    if (parsed is! List) {
      return const [];
    }

    return parsed
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Botão Adicionar ao Carrinho
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _addToCart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add_shopping_cart, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Carrinho',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Botão Comprar
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _buyNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag, size: 20),
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            // Calcular preço baseado no tamanho selecionado
                            final tamanhos = widget.produto['tamanhos'];
                            double precoUnitario;

                            if (tamanhos != null &&
                                tamanhos is List &&
                                tamanhos.isNotEmpty &&
                                _selectedSize != null) {
                              precoUnitario =
                                  _selectedSize!['preco']?.toDouble() ?? 0.0;
                            } else {
                              precoUnitario =
                                  widget.produto['preco']?.toDouble() ?? 0.0;
                            }

                            return Text(
                              'Comprar • ${CurrencyFormatter.format(precoUnitario * _quantidade)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageFullScreen(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Imagem em tela cheia
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            // Botão de fechar
            Positioned(
              top: 40,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart() async {
    try {
      if (!_isProductAvailable(widget.produto)) {
        _showUnavailableProductMessage();
        return;
      }

      // Preparar produto com tamanho selecionado se houver
      final produtoParaCarrinho = Map<String, dynamic>.from(widget.produto);

      // Se tem tamanhos e um está selecionado, adicionar informações do tamanho
      final tamanhos = widget.produto['tamanhos'];
      if (tamanhos != null &&
          tamanhos is List &&
          tamanhos.isNotEmpty &&
          _selectedSize != null) {
        produtoParaCarrinho['tamanho_selecionado'] = _selectedSize!['nome'];
        produtoParaCarrinho['preco'] = _selectedSize!['preco'];
      }

      await _cartService.addItem(
        produtoParaCarrinho,
        quantidade: _quantidade,
        observacoes: _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
      );

      if (mounted) {
        final tamanhoText = produtoParaCarrinho['tamanho_selecionado'] != null
            ? ' (${produtoParaCarrinho['tamanho_selecionado']})'
            : '';
        _showAddedToCartSnackBar(
          '${widget.produto['nome']}$tamanhoText adicionado ao carrinho!',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar ao carrinho: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _buyNow() async {
    try {
      if (!_isProductAvailable(widget.produto)) {
        _showUnavailableProductMessage();
        return;
      }

      // Preparar produto com tamanho selecionado se houver
      final produtoParaCarrinho = Map<String, dynamic>.from(widget.produto);

      // Se tem tamanhos e um está selecionado, adicionar informações do tamanho
      final tamanhos = widget.produto['tamanhos'];
      if (tamanhos != null &&
          tamanhos is List &&
          tamanhos.isNotEmpty &&
          _selectedSize != null) {
        produtoParaCarrinho['tamanho_selecionado'] = _selectedSize!['nome'];
        produtoParaCarrinho['preco'] = _selectedSize!['preco'];
      }

      // Adiciona ao carrinho com flag isBuyNow = true
      await _cartService.addItem(
        produtoParaCarrinho,
        quantidade: _quantidade,
        observacoes: _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
        isBuyNow: true,
      );

      if (mounted) {
        // Navega direto para o checkout
        final result = await Navigator.pushNamed(context, '/checkout');

        // Se o usuário voltou do checkout sem finalizar (result == null),
        // remove o item do carrinho
        if (result == null && mounted) {
          await _cartService.clearBuyNowItems();
        }
      }
    } catch (e) {
      debugPrint('Erro ao processar compra: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar compra: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _shareProduct() async {
    final produto = widget.produto;
    final nome = produto['nome'] ?? 'Produto delicioso';
    final preco = produto['preco'] != null
        ? CurrencyFormatter.format(produto['preco'].toDouble())
        : 'Consulte o preço';

    // Gerar link do produto para deep linking
    final produtoId = produto['id'] ?? '';
    final deepLink = 'https://carrodasdelicias.app/produto/$produtoId';

    final texto =
        '''
🍰 Carro das Delícias 🍰

Confira este delicioso produto:

$nome
💰 $preco

👉 Veja mais detalhes e faça seu pedido:
$deepLink

Entre em contato conosco para fazer seu pedido!
    '''
            .trim();

    try {
      // Compartilhar usando o sistema nativo (WhatsApp, Facebook, etc.)
      await Share.share(texto, subject: 'Produto: $nome');
    } catch (e) {
      // Em caso de erro, mostrar mensagem
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao compartilhar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

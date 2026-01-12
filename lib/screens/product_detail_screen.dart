import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/cart_service.dart';
import '../utils/constants.dart';
import '../widgets/main_navigation_provider.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> produto;

  const ProductDetailScreen({super.key, required this.produto});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _observacoesController = TextEditingController();
  int _quantidade = 1;
  final _cartService = CartService();
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  // Tamanho selecionado (para produtos com múltiplos tamanhos)
  Map<String, dynamic>? _selectedSize;

  @override
  void initState() {
    super.initState();
    // Se o produto tem tamanhos, selecionar o primeiro por padrão
    final tamanhos = widget.produto['tamanhos'];
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      _selectedSize = tamanhos[0];
    }
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _getObservacaoPlaceholder() {
    final categoria =
        widget.produto['categoria_nome']?.toString().toLowerCase() ?? '';

    if (categoria.contains('bolo') ||
        categoria.contains('torta') ||
        categoria.contains('sobremesa')) {
      return 'Ex: Sem cobertura, massa de chocolate, aniversário do João, etc.';
    } else if (categoria.contains('salgado') ||
        categoria.contains('lanche') ||
        categoria.contains('hambúrger')) {
      return 'Ex: Sem cebola, ponto da carne mal passado, sem maionese, etc.';
    } else if (categoria.contains('pizza')) {
      return 'Ex: Massa fina, sem azeitona, borda recheada, etc.';
    } else if (categoria.contains('bebida') || categoria.contains('suco')) {
      return 'Ex: Sem açúcar, com gelo, temperatura ambiente, etc.';
    } else if (categoria.contains('doce') || categoria.contains('açaí')) {
      return 'Ex: Pouco doce, sem granola, sem leite condensado, etc.';
    } else if (categoria.contains('salada') || categoria.contains('natural')) {
      return 'Ex: Sem tomate, molho à parte, sem cebola roxa, etc.';
    } else {
      return 'Ex: Observações especiais sobre o preparo, ingredientes, etc.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App Bar com imagem do produto
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(background: _buildProductImage()),
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
                    const SizedBox(height: 24),

                    // Badges (mais vendido, novidade, promoção)
                    _buildBadges(),
                    const SizedBox(height: 24),

                    // Descrição
                    _buildDescription(),
                    const SizedBox(height: 24),

                    // Contador de quantidade
                    _buildQuantitySelector(),
                    const SizedBox(height: 24),

                    // Campo de observações
                    _buildObservationsField(),
                    const SizedBox(height: 100), // Espaço para o botão fixo
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
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
      return Container(
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
            return Container(
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nome do produto
        Text(
          widget.produto['nome'] ?? 'Produto sem nome',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),

        // Categoria
        if (widget.produto['categoria_nome'] != null) ...[
          Row(
            children: [
              Icon(Icons.category, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${widget.produto['categoria_icone'] ?? '📦'} ${widget.produto['categoria_nome']}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
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
    double preco;

    // Se tem tamanhos, usar o preço do tamanho selecionado
    if (tamanhos != null &&
        tamanhos is List &&
        tamanhos.isNotEmpty &&
        _selectedSize != null) {
      preco = _selectedSize!['preco']?.toDouble() ?? 0.0;
    } else {
      preco = widget.produto['preco']?.toDouble() ?? 0.0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: Colors.green[700], size: 32),
          const SizedBox(width: 12),
          Text(
            CurrencyFormatter.format(preco),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
            ),
          ),
        ],
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

    if (widget.produto['promocao'] == true) {
      badges.add(_buildBadge('🏷️ Promoção', Colors.orange));
    }

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
                        Icon(Icons.shopping_cart_outlined, size: 20),
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

  Future<void> _addToCart() async {
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.produto['nome']}$tamanhoText adicionado ao carrinho!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'Ver Carrinho',
              textColor: Colors.white,
              onPressed: () {
                // Navega para o carrinho usando o PageView do MainScreen
                final provider = MainNavigationProvider.of(context);
                if (provider?.navigateToPageDirect != null) {
                  provider!.navigateToPageDirect!(2); // Índice 2 = Carrinho
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar ao carrinho: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
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

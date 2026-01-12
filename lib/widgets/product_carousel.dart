import 'package:flutter/material.dart';

class ProductCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String title;
  final Color titleColor;
  final Color backgroundColor;
  final Function(Map<String, dynamic>)? onItemTap;

  const ProductCarousel({
    super.key,
    required this.items,
    required this.title,
    this.titleColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.onItemTap,
  });

  @override
  State<ProductCarousel> createState() => _ProductCarouselState();
}

class _ProductCarouselState extends State<ProductCarousel> {
  final PageController _pageController = PageController(viewportFraction: 0.8);
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: widget.backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título do carrossel
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: widget.titleColor,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Carrossel de produtos
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return RepaintBoundary(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      debugPrint(
                        '👆 Tap no card do carrossel - navegando para detalhes',
                      );
                      if (widget.onItemTap != null) {
                        widget.onItemTap!(item);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [Colors.white, Colors.grey[50]!],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: Colors.grey[200]!, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // Conteúdo do card
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Imagem ou Ícone da categoria
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange[200]!,
                                      ),
                                    ),
                                    child:
                                        item['imagem_url'] != null &&
                                            item['imagem_url']
                                                .toString()
                                                .isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.network(
                                              item['imagem_url'],
                                              fit: BoxFit.cover,
                                              cacheWidth: 100,
                                              cacheHeight: 100,
                                              filterQuality:
                                                  FilterQuality.medium,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Center(
                                                    child: Text(
                                                      item['categoria_icone'] ??
                                                          '🍰',
                                                      style: const TextStyle(
                                                        fontSize: 24,
                                                      ),
                                                    ),
                                                  ),
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
                                                    return const Center(
                                                      child: SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              item['categoria_icone'] ?? '🍰',
                                              style: const TextStyle(
                                                fontSize: 24,
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Nome do produto
                                  Expanded(
                                    child: Text(
                                      item['nome'] ?? 'Produto sem nome',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  // Preço
                                  if (item['preco'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Colors.green, Colors.teal],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'R\$ ${item['preco'].toStringAsFixed(2).replaceAll('.', ',')}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // Badge de status no canto superior direito
                            if (item['promocao'] == true)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
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
                              ),

                            if (item['mais_vendido'] == true)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'MAIS VENDIDO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
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

          // Indicadores de página
          if (widget.items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.items.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentIndex == index ? 12 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentIndex == index
                          ? Colors.black
                          : Colors.grey[400],
                      borderRadius: BorderRadius.circular(3),
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

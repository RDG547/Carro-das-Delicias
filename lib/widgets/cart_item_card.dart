import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/cart_service.dart';
import '../utils/constants.dart';

class CartItemCard extends StatelessWidget {
  final CartItem item;
  final CartService cartService;
  final EdgeInsetsGeometry margin;

  const CartItemCard({
    super.key,
    required this.item,
    required this.cartService,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildProductImage(),
            const SizedBox(width: 16),
            Expanded(child: _buildProductInfo()),
            _buildQuantitySummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    return Container(
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
    );
  }

  Widget _buildProductInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.nome,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (item.categoriaNome != null) ...[
          const SizedBox(height: 4),
          Text(
            item.categoriaNome!,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
        if (item.tamanhoSelecionado != null) ...[
          const SizedBox(height: 4),
          _buildOptionChip(
            'Tamanho: ${_formatOption(item.tamanhoSelecionado!)}',
          ),
        ],
        if (item.saborSelecionado != null) ...[
          const SizedBox(height: 4),
          _buildOptionChip(
            'Sabor: ${_formatOption(item.saborSelecionado!)}',
            color: Colors.orange,
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
    );
  }

  Widget _buildQuantitySummary() {
    return Column(
      children: [
        _buildQuantityControls(),
        const SizedBox(height: 8),
        Text(
          CurrencyFormatter.format(item.subtotal),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
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

  Widget _buildQuantityControls() {
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
                onPressed: () => cartService.updateQuantity(
                  item.cartKey,
                  item.quantidade - 1,
                ),
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
                onPressed: () => cartService.updateQuantity(
                  item.cartKey,
                  item.quantidade + 1,
                ),
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

  Widget _buildOptionChip(String text, {Color color = Colors.black}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color == Colors.black ? Colors.black87 : color,
        ),
      ),
    );
  }

  String _formatOption(String optionJson) {
    try {
      final option = json.decode(optionJson);
      if (option is Map<String, dynamic>) {
        return option['nome'] ?? option['name'] ?? optionJson;
      }
      return optionJson;
    } catch (_) {
      return optionJson;
    }
  }
}

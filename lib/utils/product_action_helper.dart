import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/checkout_screen.dart';
import '../services/cart_service.dart';
import '../utils/app_snackbar.dart';
import '../widgets/size_selector_dialog.dart';

class ProductActionHelper {
  static Future<void> addToCart({
    required BuildContext context,
    required CartService cartService,
    required Map<String, dynamic> produto,
    required VoidCallback onViewCart,
    bool avoidAdminFab = false,
  }) async {
    final tamanhos = _extractSizes(produto['tamanhos']);

    if (tamanhos.isNotEmpty) {
      final produtoComTamanhos = Map<String, dynamic>.from(produto)
        ..['tamanhos'] = tamanhos;

      await showDialog(
        context: context,
        builder: (_) => SizeSelectorDialog(
          produto: produtoComTamanhos,
          action: SizeSelectionAction.addToCart,
          onSizeSelected: (selectedSize) async {
            final produtoComTamanho = Map<String, dynamic>.from(produto)
              ..['preco'] = _toDouble(selectedSize['preco'])
              ..['tamanho_selecionado'] = selectedSize['nome'];

            await cartService.addItem(produtoComTamanho);

            if (!context.mounted) return;

            AppSnackBar.showCartAdded(
              context,
              message:
                  '${produto['nome']} (${selectedSize['nome']}) adicionado ao carrinho!',
              onViewCart: onViewCart,
              avoidAdminFab: avoidAdminFab,
            );
          },
        ),
      );
      return;
    }

    final preco = _toDouble(produto['preco']);
    if (preco == null) {
      if (!context.mounted) return;
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

    await cartService.addItem(produto, quantidade: 1);

    if (!context.mounted) return;

    AppSnackBar.showCartAdded(
      context,
      message: '${produto['nome']} adicionado ao carrinho!',
      onViewCart: onViewCart,
      avoidAdminFab: avoidAdminFab,
    );
  }

  static Future<void> buyNow({
    required BuildContext context,
    required CartService cartService,
    required Map<String, dynamic> produto,
  }) async {
    final tamanhos = _extractSizes(produto['tamanhos']);

    if (tamanhos.isNotEmpty) {
      final produtoComTamanhos = Map<String, dynamic>.from(produto)
        ..['tamanhos'] = tamanhos;

      await showDialog(
        context: context,
        builder: (_) => SizeSelectorDialog(
          produto: produtoComTamanhos,
          action: SizeSelectionAction.buyNow,
          onSizeSelected: (selectedSize) async {
            final produtoComTamanho = Map<String, dynamic>.from(produto)
              ..['preco'] = _toDouble(selectedSize['preco'])
              ..['tamanho_selecionado'] = selectedSize['nome'];

            await _finishBuyNow(
              context: context,
              cartService: cartService,
              produto: produtoComTamanho,
            );
          },
        ),
      );
      return;
    }

    final preco = _toDouble(produto['preco']);
    if (preco == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto sem preço não pode ser comprado'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _finishBuyNow(
      context: context,
      cartService: cartService,
      produto: produto,
    );
  }

  static Future<void> _finishBuyNow({
    required BuildContext context,
    required CartService cartService,
    required Map<String, dynamic> produto,
  }) async {
    await cartService.addItem(produto, isBuyNow: true);

    if (!context.mounted) return;

    dynamic result;

    try {
      result = await Navigator.of(context).pushNamed('/checkout');
    } catch (_) {
      if (!context.mounted) return;
      result = await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
    }

    if (result == null && context.mounted) {
      await cartService.clearBuyNowItems();
    }
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value
          .replaceAll('R\$', '')
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  static List<Map<String, dynamic>> _extractSizes(dynamic rawSizes) {
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
}

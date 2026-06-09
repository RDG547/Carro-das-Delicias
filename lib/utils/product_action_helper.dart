import 'package:flutter/material.dart';

import '../screens/checkout_screen.dart';
import '../services/cart_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/product_variant_utils.dart';
import '../widgets/size_selector_dialog.dart';

class ProductActionHelper {
  static Future<void> addToCart({
    required BuildContext context,
    required CartService cartService,
    required Map<String, dynamic> produto,
    required VoidCallback onViewCart,
    bool avoidAdminFab = false,
  }) async {
    final tamanhos = ProductVariantUtils.extractSizes(produto['tamanhos']);
    final sabores = ProductVariantUtils.extractFlavors(produto['sabores']);

    if (tamanhos.isNotEmpty || sabores.isNotEmpty) {
      final produtoComOpcoes = Map<String, dynamic>.from(produto)
        ..['tamanhos'] = tamanhos
        ..['sabores'] = sabores;

      await showDialog(
        context: context,
        builder: (_) => SizeSelectorDialog(
          produto: produtoComOpcoes,
          action: SizeSelectionAction.addToCart,
          onOptionsSelected: (selection) async {
            final produtoSelecionado = ProductVariantUtils.applySelections(
              produto,
              selectedSize: selection.selectedSize,
              selectedFlavor: selection.selectedFlavor,
            );
            if (ProductVariantUtils.toDouble(produtoSelecionado['preco']) ==
                null) {
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

            await cartService.addItem(produtoSelecionado);

            if (!context.mounted) return;

            final sizeName = ProductVariantUtils.optionName(
              selection.selectedSize,
            );
            final flavorName = ProductVariantUtils.optionName(
              selection.selectedFlavor,
            );
            final suffix = ProductVariantUtils.selectionSuffix(
              sizeName: sizeName,
              flavorName: flavorName,
            );

            AppSnackBar.showCartAdded(
              context,
              message: '${produto['nome']}$suffix adicionado ao carrinho!',
              onViewCart: onViewCart,
              avoidAdminFab: avoidAdminFab,
            );
          },
        ),
      );
      return;
    }

    final preco = ProductVariantUtils.toDouble(produto['preco']);
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
    final tamanhos = ProductVariantUtils.extractSizes(produto['tamanhos']);
    final sabores = ProductVariantUtils.extractFlavors(produto['sabores']);

    if (tamanhos.isNotEmpty || sabores.isNotEmpty) {
      final produtoComOpcoes = Map<String, dynamic>.from(produto)
        ..['tamanhos'] = tamanhos
        ..['sabores'] = sabores;

      await showDialog(
        context: context,
        builder: (_) => SizeSelectorDialog(
          produto: produtoComOpcoes,
          action: SizeSelectionAction.buyNow,
          onOptionsSelected: (selection) async {
            final produtoSelecionado = ProductVariantUtils.applySelections(
              produto,
              selectedSize: selection.selectedSize,
              selectedFlavor: selection.selectedFlavor,
            );
            if (ProductVariantUtils.toDouble(produtoSelecionado['preco']) ==
                null) {
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
              produto: produtoSelecionado,
            );
          },
        ),
      );
      return;
    }

    final preco = ProductVariantUtils.toDouble(produto['preco']);
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
}

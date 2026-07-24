import 'dart:convert';

import 'package:carrodasdelicias/services/cart_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CartService().clearCart();
  });

  test('restaura itens salvos localmente no carrinho', () async {
    SharedPreferences.setMockInitialValues({
      'cart_items': json.encode([
        {
          'id': 'produto-1',
          'nome': 'Brigadeiro',
          'preco': 4.5,
          'imagemUrl': null,
          'categoriaId': 'doces',
          'categoriaNome': 'Doces',
          'categoriaIcone': '🍬',
          'quantidade': 2,
          'observacoes': 'Sem granulado',
          'isBuyNow': false,
          'tamanhoSelecionado': null,
          'saborSelecionado': null,
        },
      ]),
    });

    await CartService().loadCart();

    expect(CartService().totalItems, 2);
    expect(CartService().items.single.nome, 'Brigadeiro');
    expect(CartService().items.single.categoriaIcone, '🍬');
    expect(CartService().items.single.observacoes, 'Sem granulado');
    expect(CartService().orderObservation, isNull);
  });

  test('mantém observações do item e do pedido separadas', () async {
    await CartService().addItem({
      'id': 'produto-2',
      'nome': 'Empada',
      'preco': 8.0,
      'categoria_nome': 'Salgado',
      'categoria_icone': 'asset:assets/icons/salgado_category.png',
    }, observacoes: 'Bem assada');

    await CartService().updateOrderObservation('Entregar na portaria');

    final prefs = await SharedPreferences.getInstance();
    expect(CartService().orderObservation, 'Entregar na portaria');
    expect(CartService().items.single.observacoes, 'Bem assada');
    expect(prefs.getString('cart_order_observation'), 'Entregar na portaria');
    expect(
      CartService().items.single.categoriaIcone,
      'asset:assets/icons/salgado_category.png',
    );
  });
}

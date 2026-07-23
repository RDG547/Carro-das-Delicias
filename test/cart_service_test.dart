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
          'quantidade': 2,
          'observacoes': 'Campo legado ignorado',
          'isBuyNow': false,
          'tamanhoSelecionado': null,
          'saborSelecionado': null,
        },
      ]),
    });

    await CartService().loadCart();

    expect(CartService().totalItems, 2);
    expect(CartService().items.single.nome, 'Brigadeiro');
  });
}

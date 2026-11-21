import 'package:carrodasdelicias/utils/category_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final all = <Map<String, dynamic>>[
    for (var i = 1; i <= 4; i++)
      {'id': i, 'nome': 'Categoria $i', 'ordem': i - 1},
  ];
  test('reordenar com busca mantém a posição das categorias ocultas', () {
    final result = CategoryOrder.mergeVisible(all, [all[2], all[0]]);
    expect(result.map((c) => c['id']), [3, 2, 1, 4]);
    expect(result.map((c) => c['ordem']), [0, 1, 2, 3]);
    expect(result.map((c) => c['order']), [0, 1, 2, 3]);
    expect(all.map((c) => c['id']), [1, 2, 3, 4]);
  });
  test(
    'reordenar a lista inteira mantém todas as categorias e posições únicas',
    () {
      final result = CategoryOrder.mergeVisible(all, all.reversed.toList());
      expect(result.map((c) => c['id']), [4, 3, 2, 1]);
      expect(result.map((c) => c['ordem']).toSet().length, 4);
    },
  );
  test('categoria removida ou duplicada é rejeitada', () {
    expect(
      () => CategoryOrder.mergeVisible(all, [all[0], all[0]]),
      throwsArgumentError,
    );
    expect(
      () => CategoryOrder.mergeVisible(all, [
        {'id': 99},
      ]),
      throwsArgumentError,
    );
  });
}

import 'package:carrodasdelicias/widgets/category_reorder_list.dart';
import 'package:carrodasdelicias/utils/category_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'atualizar várias vezes preserva a ordem visual e não salva um arraste',
    (tester) async {
      final server = [
        for (var i = 1; i <= 9; i++)
          {'id': i, 'nome': 'Categoria $i', 'ordem': i - 1},
      ];
      var categories = CategoryOrder.sorted(server);
      var revision = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    categories = CategoryOrder.sorted(server.reversed);
                    revision++;
                  });
                },
                child: CategoryReorderList(
                  categories: categories,
                  revision: revision,
                  itemBuilder: (c, i) =>
                      ListTile(title: Text(c['nome'] as String)),
                  onReordered: (_) => saves++,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(ReorderableListView),
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.text('Categoria 1')).dy,
          lessThan(tester.getCenter(find.text('Categoria 2')).dy),
        );
        expect(categories.map((c) => c['id']), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(saves, 0);
      }
      expect(revision, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

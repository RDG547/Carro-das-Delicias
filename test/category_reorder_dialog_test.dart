import 'package:carrodasdelicias/widgets/category_reorder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final categories = [
    for (var i = 1; i <= 9; i++)
      {'id': i, 'nome': 'Categoria $i', 'icone': '🎂'},
  ];
  for (final size in [
    const Size(320, 640),
    const Size(440, 900),
    const Size(844, 390),
  ]) {
    testWidgets(
      'reordenar: rolar e pressionar o nome não mudam a ordem em $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<int>? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CategoryReorderDialog(
                categories: categories,
                onSave: (list) async {
                  saved = list.map((c) => c['id'] as int).toList();
                  return false;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cardPress = await tester.startGesture(
          tester.getCenter(find.text('Categoria 1')),
        );
        await tester.pump(const Duration(milliseconds: 700));
        await cardPress.moveBy(const Offset(0, 140));
        await tester.pump(const Duration(milliseconds: 300));
        await cardPress.up();
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(ReorderableListView),
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
        final label = tester.renderObject<RenderParagraph>(
          find.text('Salvar ordem'),
        );
        expect(label.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Salvar ordem'));
        await tester.pumpAndSettle();
        expect(saved, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('somente o puxador reordena e salvar persiste a nova ordem', (
    tester,
  ) async {
    List<int>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryReorderDialog(
            categories: categories.take(3).toList(),
            onSave: (list) async {
              saved = list.map((c) => c['id'] as int).toList();
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(CategoryDragHandle).first),
    );
    await tester.pump();
    await drag.moveBy(const Offset(0, 20));
    await tester.pump();
    await drag.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 500));
    await drag.moveBy(const Offset(0, 10));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar ordem'));
    await tester.pumpAndSettle();
    expect(saved, [2, 1, 3]);
  });
}

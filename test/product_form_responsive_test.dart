import 'package:carrodasdelicias/widgets/edit_product_dialog.dart';
import 'package:carrodasdelicias/widgets/form_dialogs.dart';
import 'package:carrodasdelicias/widgets/product_form_dialog_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final categories = <Map<String, dynamic>>[
    {'id': 1, 'nome': 'Bolos', 'icone': '🎂'},
  ];
  for (final size in [
    const Size(320, 640),
    const Size(440, 900),
    const Size(900, 1000),
  ]) {
    for (final editing in [false, true]) {
      testWidgets(
        '${editing ? "editar" : "adicionar"} produto em ${size.width.toInt()}px com teclado',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Widget form() => editing
              ? EditProductDialog(
                  produto: {
                    'id': 1,
                    'nome': 'Bolo de Cenoura',
                    'descricao': 'Bolo caseiro',
                    'preco': 12.5,
                    'categoria_id': 1,
                  },
                  categorias: categories,
                  onProductUpdated: () {},
                )
              : AddProductDialog(categorias: categories, onProductAdded: () {});
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => form(),
                      ),
                      child: const Text('Abrir'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir'));
          await tester.pumpAndSettle();
          expect(find.byType(ProductFormDialogHeader), findsOneWidget);
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final shell = tester.getRect(find.byType(ProductFormDialogShell));
          expect(shell.bottom, lessThanOrEqualTo(size.height));
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}

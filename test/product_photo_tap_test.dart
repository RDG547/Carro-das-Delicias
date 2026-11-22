import 'package:carrodasdelicias/widgets/product_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final hasPhoto in [true, false]) {
    testWidgets(
      'tocar no quadrante ${hasPhoto ? "abre a foto" : "mantém a ação do card sem foto"}',
      (tester) async {
        var cardTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                onTap: () => cardTaps++,
                child: ProductPhotoTap(
                  images: hasPhoto ? ['https://example.test/photo.png'] : [],
                  child: const SizedBox(
                    width: 80,
                    height: 80,
                    child: ColoredBox(color: Colors.orange),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(ProductPhotoTap));
        await tester.pumpAndSettle();
        expect(
          find.byType(ProductImageViewerDialog),
          hasPhoto ? findsOneWidget : findsNothing,
        );
        expect(cardTaps, hasPhoto ? 0 : 1);
        if (hasPhoto) {
          expect(find.byType(InteractiveViewer), findsOneWidget);
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(find.byType(ProductImageViewerDialog), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

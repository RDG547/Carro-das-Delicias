import 'package:carrodasdelicias/widgets/delivery_date_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('ações da data centralizadas, com ícones e fonte $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: 224,
                  child: DeliveryDateActions(onCancel: () {}, onConfirm: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      final cancel = tester.getRect(find.byType(TextButton));
      final confirm = tester.getRect(find.byType(ElevatedButton));
      expect(cancel.center.dy, closeTo(confirm.center.dy, .01));
      expect(cancel.width, closeTo(confirm.width, .01));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

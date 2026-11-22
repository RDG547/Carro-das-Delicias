import 'package:carrodasdelicias/widgets/tracking_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'barra curva expande e leva o indicativo para baixo do endereço',
    (tester) async {
      var expanded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topCenter,
                child: TrackingInfoSheet(
                  expanded: expanded,
                  expandedHeight: 280,
                  onChanged: (value) => setState(() => expanded = value),
                  child: const Text('Localização Atual'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('Arraste para baixo'), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(
        tester.getCenter(find.text('Arraste para cima')).dy,
        greaterThan(tester.getCenter(find.text('Localização Atual')).dy),
      );
      await tester.drag(find.text('Arraste para cima'), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(expanded, isFalse);
      expect(find.text('Arraste para baixo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

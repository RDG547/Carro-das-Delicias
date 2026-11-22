import 'package:carrodasdelicias/widgets/report_export_actions.dart';
import 'package:carrodasdelicias/services/admin_report_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [260.0, 320.0, 600.0]) {
    testWidgets('exportar: três botões iguais na mesma linha em $width px', (
      tester,
    ) async {
      AdminReportFormat? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ReportExportActions(
                  onExport: (format) => selected = format,
                ),
              ),
            ),
          ),
        ),
      );
      final buttons = find.byType(ElevatedButton);
      final rects = [for (var i = 0; i < 3; i++) tester.getRect(buttons.at(i))];
      for (final rect in rects.skip(1)) {
        expect(rect.width, closeTo(rects.first.width, .01));
        expect(rect.height, closeTo(rects.first.height, .01));
        expect(rect.top, rects.first.top);
      }
      await tester.tap(find.text('PDF'));
      expect(selected, AdminReportFormat.pdf);
      expect(tester.takeException(), isNull);
    });
  }
}

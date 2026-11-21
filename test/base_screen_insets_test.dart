import 'package:carrodasdelicias/widgets/base_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bottom in [24.0, 48.0]) {
    testWidgets('conteúdo respeita barra do sistema de $bottom pixels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.padding = FakeViewPadding(top: 30, bottom: bottom);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        const MaterialApp(
          home: BaseScreen(
            title: 'Teste',
            child: SizedBox.expand(key: Key('content')),
          ),
        ),
      );
      final content = tester.getRect(find.byKey(const Key('content')));
      expect(content.bottom, lessThanOrEqualTo(600 - bottom));
      expect(content.top, greaterThanOrEqualTo(30 + 48));
      expect(tester.takeException(), isNull);
    });
  }
}

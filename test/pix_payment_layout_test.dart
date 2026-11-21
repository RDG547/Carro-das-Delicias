import 'package:carrodasdelicias/screens/abacatepay_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 440.0]) {
    testWidgets(
      'status PIX aparece acima de copiar código em ${width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(
            home: AbacatePayPaymentScreen(
              pedidoId: 'test-order',
              amount: 10,
              description: 'Pedido de teste',
              initialChargeId: 'test-charge',
              initialPaymentPayload: {'pix_code': '000201-PAGAMENTO-TESTE'},
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.getTopLeft(find.text('Aguardando pagamento...')).dy,
          lessThan(tester.getTopLeft(find.text('Copiar Código PIX')).dy),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

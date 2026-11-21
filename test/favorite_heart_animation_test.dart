import 'package:carrodasdelicias/widgets/favorite_heart_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  testWidgets(
    'coração partido continua no overlay quando o card favorito é removido',
    (tester) async {
      final visible = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, show, _) => show
                  ? IconButton(
                      icon: const Icon(Icons.favorite),
                      onPressed: () {
                        FavoriteHeartAnimation.showBreak(context);
                        visible.value = false;
                      },
                    )
                  : const Text('Sem favoritos'),
            ),
          ),
        ),
      );
      await tester.runAsync(FavoriteHeartAnimation.preload);
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sem favoritos'), findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<Lottie>(find.byType(Lottie)).controller!.value,
        greaterThan(0),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(Lottie), findsNothing);
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
    },
  );
}

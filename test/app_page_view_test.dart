import 'package:carrodasdelicias/widgets/app_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AnimatedPage extends StatefulWidget {
  const _AnimatedPage({
    super.key,
    required this.index,
    required this.onCreated,
  });
  final int index;
  final ValueChanged<int> onCreated;
  @override
  State<_AnimatedPage> createState() => _AnimatedPageState();
}

class _AnimatedPageState extends State<_AnimatedPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController fade;
  late final AnimationController pulse;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    widget.onCreated(widget.index);
    fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    fade.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FadeTransition(
      opacity: fade,
      child: Center(child: Text('Página ${widget.index}')),
    );
  }
}

void main() {
  testWidgets(
    'admin fica visível com navbar sem seleção e não monta telas intermediárias',
    (tester) async {
      final controller = PageController();
      final navbarIndex = ValueNotifier(0);
      final created = <int>[];
      final keys = List.generate(8, (_) => GlobalKey<_AnimatedPageState>());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        navbarIndex.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: navbarIndex,
            builder: (context, selected, _) => Scaffold(
              body: AppPageView(
                controller: controller,
                onPageChanged: (page) =>
                    navbarIndex.value = page >= 4 ? -1 : page,
                children: List.generate(
                  8,
                  (index) => _AnimatedPage(
                    key: keys[index],
                    index: index,
                    onCreated: created.add,
                  ),
                ),
              ),
              bottomNavigationBar: selected < 0
                  ? null
                  : Text('Navbar $selected'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      AppPageView.navigateTo(controller, 6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(navbarIndex.value, -1);
      expect(find.text('Navbar -1'), findsNothing);
      expect(created, [0, 6]);
      expect(keys[6].currentState!.fade.value, 1);
      expect(TickerMode.of(keys[6].currentContext!), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pedidos, perfil, carrinho e demais páginas mantêm animações ativas',
    (tester) async {
      final controller = PageController();
      final keys = List.generate(8, (_) => GlobalKey<_AnimatedPageState>());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageView(
              controller: controller,
              children: List.generate(
                8,
                (index) => _AnimatedPage(
                  key: keys[index],
                  index: index,
                  onCreated: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      for (final page in [2, 3, 4, 5, 6, 7, 0]) {
        AppPageView.navigateTo(controller, page);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(controller.page, page.toDouble());
        expect(
          TickerMode.of(keys[page].currentContext!),
          isTrue,
          reason: 'Página $page',
        );
        expect(
          keys[page].currentState!.fade.value,
          1,
          reason: 'Página $page deve aparecer',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animação em segundo plano pausa e volta a funcionar ao retornar',
    (tester) async {
      final controller = PageController();
      final keys = List.generate(8, (_) => GlobalKey<_AnimatedPageState>());
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPageView(
              controller: controller,
              children: List.generate(
                8,
                (index) => _AnimatedPage(
                  key: keys[index],
                  index: index,
                  onCreated: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      AppPageView.navigateTo(controller, 6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final paused = keys[0].currentState!.pulse.value;
      expect(TickerMode.of(keys[0].currentContext!), isFalse);
      await tester.pump(const Duration(milliseconds: 700));
      expect(keys[0].currentState!.pulse.value, paused);
      AppPageView.navigateTo(controller, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(TickerMode.of(keys[0].currentContext!), isTrue);
      expect(keys[0].currentState!.pulse.value, isNot(paused));
    },
  );
}

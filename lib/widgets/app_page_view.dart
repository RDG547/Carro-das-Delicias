import 'package:flutter/material.dart';

/// Mantém as animações da página visível independentes da seleção da navbar.
class AppPageView extends StatefulWidget {
  const AppPageView({
    super.key,
    required this.controller,
    required this.children,
    this.onPageChanged,
  });

  final PageController controller;
  final List<Widget> children;
  final ValueChanged<int>? onPageChanged;

  static void navigateTo(PageController controller, int pageIndex) {
    if (!controller.hasClients || pageIndex < 0) return;
    final currentPage = controller.page ?? controller.initialPage.toDouble();
    if ((currentPage - pageIndex).abs() > 1) {
      // Evita montar e consultar todas as telas intermediárias.
      // As telas de destino preservam suas próprias animações de entrada.
      controller.jumpToPage(pageIndex);
    } else {
      controller.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  State<AppPageView> createState() => _AppPageViewState();
}

class _AppPageViewState extends State<AppPageView> {
  late int _visiblePage = widget.controller.initialPage;

  @override
  Widget build(BuildContext context) => PageView(
    controller: widget.controller,
    physics: const NeverScrollableScrollPhysics(),
    onPageChanged: (index) {
      setState(() => _visiblePage = index);
      widget.onPageChanged?.call(index);
    },
    children: [
      for (var index = 0; index < widget.children.length; index++)
        TickerMode(
          enabled: index == _visiblePage,
          child: widget.children[index],
        ),
    ],
  );
}

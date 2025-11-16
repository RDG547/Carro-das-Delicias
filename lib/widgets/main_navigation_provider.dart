import 'package:flutter/material.dart';

class MainNavigationProvider extends InheritedWidget {
  final VoidCallback navigateToHome;
  final void Function(int)? navigateToPage;
  final void Function(int)?
  navigateToPageDirect; // Navega diretamente para índice do PageView

  const MainNavigationProvider({
    super.key,
    required this.navigateToHome,
    this.navigateToPage,
    this.navigateToPageDirect,
    required super.child,
  });

  static MainNavigationProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainNavigationProvider>();
  }

  @override
  bool updateShouldNotify(MainNavigationProvider oldWidget) {
    return navigateToHome != oldWidget.navigateToHome ||
        navigateToPage != oldWidget.navigateToPage ||
        navigateToPageDirect != oldWidget.navigateToPageDirect;
  }
}

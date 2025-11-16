import 'package:flutter/material.dart';

/// Provider para compartilhar o status de admin em todo o app
class AdminStatusProvider extends InheritedWidget {
  final bool isAdmin;
  final bool isLoading;

  const AdminStatusProvider({
    super.key,
    required this.isAdmin,
    required this.isLoading,
    required super.child,
  });

  static AdminStatusProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminStatusProvider>();
  }

  @override
  bool updateShouldNotify(AdminStatusProvider oldWidget) {
    return isAdmin != oldWidget.isAdmin || isLoading != oldWidget.isLoading;
  }
}

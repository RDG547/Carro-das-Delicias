import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppSnackBar {
  static void showTop(
    BuildContext context, {
    required Widget content,
    Color backgroundColor = Colors.black87,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
    double toolbarHeight = kToolbarHeight,
    double topSpacing = 24,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final topOffset = mediaQuery.padding.top + toolbarHeight + topSpacing;
    final bottomOffset = math.max(
      24.0,
      mediaQuery.size.height - topOffset - 72,
    );

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: content,
          backgroundColor: backgroundColor,
          duration: duration,
          action: action,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, topOffset, 16, bottomOffset),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  static void showCartAdded(
    BuildContext context, {
    required String message,
    required VoidCallback onViewCart,
    bool avoidAdminFab = false,
    double bottomSpacing = 110,
    Duration duration = const Duration(seconds: 3),
  }) {
    final mediaQuery = MediaQuery.of(context);
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            avoidAdminFab ? 92 : 16,
            mediaQuery.padding.bottom + bottomSpacing,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onViewCart();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility, color: Colors.white, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'Ver Carrinho',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

    Future.delayed(duration, () {
      messenger.hideCurrentSnackBar();
    });
  }
}

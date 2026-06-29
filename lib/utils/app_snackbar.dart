import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppSnackBar {
  static OverlayEntry? _cartOverlayEntry;

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

  static void showCartAddedOverlay(
    BuildContext context, {
    required String message,
    required VoidCallback onViewCart,
    double bottomSpacing = 24,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _cartOverlayEntry?.remove();
    _cartOverlayEntry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return Positioned(
          left: 16,
          right: 16,
          bottom: mediaQuery.padding.bottom + bottomSpacing,
          child: _CartAddedOverlayCard(
            message: message,
            onViewCart: () {
              entry.remove();
              if (_cartOverlayEntry == entry) {
                _cartOverlayEntry = null;
              }
              onViewCart();
            },
          ),
        );
      },
    );

    _cartOverlayEntry = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_cartOverlayEntry == entry && entry.mounted) {
        entry.remove();
        _cartOverlayEntry = null;
      }
    });
  }
}

class _CartAddedOverlayCard extends StatelessWidget {
  const _CartAddedOverlayCard({
    required this.message,
    required this.onViewCart,
  });

  final String message;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onViewCart,
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
      ),
    );
  }
}

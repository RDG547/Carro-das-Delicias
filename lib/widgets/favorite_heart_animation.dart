import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Mostra animações Lottie de coração ao favoritar/desfavoritar um produto.
/// A animação é exibida como overlay centralizado na tela e desaparece automaticamente.
class FavoriteHeartAnimation {
  static OverlayEntry? _currentOverlay;

  /// Exibe a animação de coração (favoritar).
  static void show(BuildContext context) {
    _showWithOverlay(Overlay.of(context), isFavoriting: true);
  }

  /// Exibe a animação de coração partido (desfavoritar).
  static void showBreak(BuildContext context) {
    _showWithOverlay(Overlay.of(context), isFavoriting: false);
  }

  /// Versão que aceita o OverlayState diretamente (para uso após async gaps).
  static void showWithOverlay(OverlayState overlay, {bool isFavoriting = true}) {
    _showWithOverlay(overlay, isFavoriting: isFavoriting);
  }

  static void _showWithOverlay(OverlayState overlay, {required bool isFavoriting}) {
    // Remover animação anterior se existir
    _currentOverlay?.remove();
    _currentOverlay = null;

    _currentOverlay = OverlayEntry(
      builder: (context) => _HeartAnimationOverlay(isFavoriting: isFavoriting),
    );

    overlay.insert(_currentOverlay!);
  }
}

class _HeartAnimationOverlay extends StatefulWidget {
  final bool isFavoriting;

  const _HeartAnimationOverlay({required this.isFavoriting});

  @override
  State<_HeartAnimationOverlay> createState() => _HeartAnimationOverlayState();
}

class _HeartAnimationOverlayState extends State<_HeartAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Iniciar a animação e remover o overlay quando terminar
    _controller.forward().then((_) {
      FavoriteHeartAnimation._currentOverlay?.remove();
      FavoriteHeartAnimation._currentOverlay = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = widget.isFavoriting
        ? 'assets/animations/heart_favorite.json'
        : 'assets/animations/heart_break.json';

    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Fade out nos últimos 30%
                final fadeValue = _controller.value > 0.7
                    ? 1.0 - ((_controller.value - 0.7) / 0.3)
                    : 1.0;
                // Scale up nos primeiros 50%
                final scaleValue = _controller.value < 0.5
                    ? 0.5 + (_controller.value / 0.5) * 0.7
                    : 1.2;

                return Opacity(
                  opacity: fadeValue.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scaleValue,
                    child: child,
                  ),
                );
              },
              child: Lottie.asset(
                assetPath,
                width: 150,
                height: 150,
                controller: _controller,
                fit: BoxFit.contain,
                frameRate: FrameRate(30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

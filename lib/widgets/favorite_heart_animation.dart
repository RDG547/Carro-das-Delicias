import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class FavoriteHeartAnimation {
  static OverlayEntry? _currentOverlay;
  static final Map<bool, Future<LottieComposition>> _compositions = {};
  static final Map<bool, LottieComposition> _loadedCompositions = {};
  static Future<LottieComposition> _composition(bool favoriting) {
    final loaded = _loadedCompositions[favoriting];
    if (loaded != null) return SynchronousFuture(loaded);
    return _compositions.putIfAbsent(
      favoriting,
      () =>
          AssetLottie(
            favoriting
                ? 'assets/animations/heart_favorite.json'
                : 'assets/animations/heart_break.json',
          ).load().then((composition) {
            _loadedCompositions[favoriting] = composition;
            return composition;
          }),
    );
  }

  static Future<void> preload() async {
    try {
      await _composition(false);
      await _composition(true);
    } catch (_) {
      // The overlay provides an animated icon if an asset cannot be decoded.
    }
  }

  static void show(BuildContext context) => _showWithOverlay(
    Overlay.of(context, rootOverlay: true),
    isFavoriting: true,
  );
  static void showBreak(BuildContext context) => _showWithOverlay(
    Overlay.of(context, rootOverlay: true),
    isFavoriting: false,
  );
  static void showWithOverlay(
    OverlayState overlay, {
    bool isFavoriting = true,
  }) => _showWithOverlay(overlay, isFavoriting: isFavoriting);
  static void _showWithOverlay(
    OverlayState overlay, {
    required bool isFavoriting,
  }) {
    if (!overlay.mounted) return;
    _currentOverlay?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _HeartAnimationOverlay(
        isFavoriting: isFavoriting,
        onComplete: () {
          if (_currentOverlay != entry) return;
          entry.remove();
          _currentOverlay = null;
        },
      ),
    );
    _currentOverlay = entry;
    overlay.insert(entry);
  }
}

class _HeartAnimationOverlay extends StatefulWidget {
  const _HeartAnimationOverlay({
    required this.isFavoriting,
    required this.onComplete,
  });
  final bool isFavoriting;
  final VoidCallback onComplete;
  @override
  State<_HeartAnimationOverlay> createState() => _HeartAnimationOverlayState();
}

class _HeartAnimationOverlayState extends State<_HeartAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Future<LottieComposition> _composition;
  Timer? _timeout;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onComplete();
        });
    _composition = FavoriteHeartAnimation._composition(widget.isFavoriting);
    _timeout = Timer(const Duration(seconds: 5), widget.onComplete);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: Center(
          child: FutureBuilder<LottieComposition>(
            future: _composition,
            builder: (_, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(width: 150, height: 150);
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    !_controller.isAnimating &&
                    _controller.value == 0) {
                  _controller.forward();
                }
              });
              return AnimatedBuilder(
                animation: _controller,
                child: snapshot.hasData
                    ? Lottie(
                        composition: snapshot.data!,
                        controller: _controller,
                        width: 150,
                        height: 150,
                        fit: BoxFit.contain,
                        frameRate: FrameRate(30),
                        repeat: false,
                      )
                    : Icon(
                        widget.isFavoriting
                            ? Icons.favorite
                            : Icons.heart_broken,
                        color: Colors.pink,
                        size: 120,
                      ),
                builder: (_, child) {
                  final value = _controller.value;
                  final fade = value > 0.7 ? 1 - (value - 0.7) / 0.3 : 1.0;
                  final scale = value < 0.5 ? 0.5 + value / 0.5 * 0.7 : 1.2;
                  return Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

class ProductPhotoTap extends StatelessWidget {
  const ProductPhotoTap({super.key, required this.images, required this.child});
  final List<String> images;
  final Widget child;
  @override
  Widget build(BuildContext context) => images.isEmpty
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => ProductImageViewerDialog(imageUrls: images),
          ),
          child: Semantics(
            button: true,
            label: 'Ampliar foto do produto',
            child: child,
          ),
        );
}

class ProductImageViewerDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ProductImageViewerDialog({
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ProductImageViewerDialog> createState() =>
      ProductImageViewerDialogState();
}

class ProductImageViewerDialogState extends State<ProductImageViewerDialog> {
  static const int _initialPageBase = 10000;
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final safeInitialIndex = widget.imageUrls.isEmpty
        ? 0
        : widget.initialIndex % widget.imageUrls.length;
    _currentIndex = safeInitialIndex;
    _pageController = PageController(
      initialPage: _alignedInitialPage(
        widget.imageUrls.length,
        safeInitialIndex,
      ),
    );
  }

  int _alignedInitialPage(int imageCount, int imageIndex) {
    if (imageCount <= 1) return 0;
    return _initialPageBase - (_initialPageBase % imageCount) + imageIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() {
                _currentIndex = page % widget.imageUrls.length;
              });
            },
            itemBuilder: (context, page) {
              final imageIndex = page % widget.imageUrls.length;
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    widget.imageUrls[imageIndex],
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.imageUrls.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: _currentIndex == index ? 18 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _currentIndex == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

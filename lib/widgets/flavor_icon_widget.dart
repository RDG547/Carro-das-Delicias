import 'package:flutter/material.dart';

import '../utils/product_variant_utils.dart';
import 'category_icon_widget.dart';

class FlavorIconWidget extends StatelessWidget {
  final String icon;
  final double size;
  final bool boxed;

  const FlavorIconWidget({
    super.key,
    required this.icon,
    this.size = 24,
    this.boxed = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = ProductVariantUtils.isImageIcon(icon)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(boxed ? 8 : 4),
            child: CategoryIconWidget(icone: icon, size: size),
          )
        : Text(icon, style: TextStyle(fontSize: size * 0.75));

    if (!boxed) return child;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

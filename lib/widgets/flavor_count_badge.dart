import 'package:flutter/material.dart';

import '../utils/product_variant_utils.dart';

class FlavorCountBadge extends StatelessWidget {
  final int flavorCount;
  final double fontSize;
  final double iconSize;
  final double horizontalPadding;
  final double iconSpacing;

  const FlavorCountBadge({
    super.key,
    required this.flavorCount,
    this.fontSize = 10,
    this.iconSize = 12,
    this.horizontalPadding = 6,
    this.iconSpacing = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ProductVariantUtils.flavorCountLabel(flavorCount),
            style: TextStyle(
              color: Colors.orange[800],
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

WidgetSpan flavorCountBadgeSpan(
  int flavorCount, {
  double leftPadding = 6,
  double fontSize = 10,
  double iconSize = 12,
  double horizontalPadding = 6,
  double iconSpacing = 3,
}) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: FlavorCountBadge(
        flavorCount: flavorCount,
        fontSize: fontSize,
        iconSize: iconSize,
        horizontalPadding: horizontalPadding,
        iconSpacing: iconSpacing,
      ),
    ),
  );
}

import 'package:flutter/widgets.dart';

double scrollIndicatorBottomOffset(
  BuildContext context, {
  double baseOffset = 80,
}) {
  final view = View.of(context);
  final rawBottomInset = view.viewPadding.bottom / view.devicePixelRatio;
  return baseOffset + rawBottomInset;
}

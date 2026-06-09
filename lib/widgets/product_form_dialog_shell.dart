import 'dart:math' as math;

import 'package:flutter/material.dart';

class ProductFormDialogShell extends StatefulWidget {
  final double width;
  final Widget title;
  final Widget body;
  final Widget actions;

  const ProductFormDialogShell({
    super.key,
    required this.width,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  State<ProductFormDialogShell> createState() => _ProductFormDialogShellState();
}

class _ProductFormDialogShellState extends State<ProductFormDialogShell>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext == null || !_scrollController.hasClients) return;

      Scrollable.ensureVisible(
        focusedContext,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final padding = MediaQuery.paddingOf(context);
    final keyboardHeight = viewInsets.bottom;
    final verticalInset = keyboardHeight > 0 ? 8.0 : 12.0;
    final availableHeight =
        size.height - keyboardHeight - padding.top - (verticalInset * 2);
    final maxHeight = math.min(
      size.height * 0.96,
      math.max(160.0, availableHeight),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: MediaQuery(
        data: mediaQuery.copyWith(viewInsets: EdgeInsets.zero),
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: verticalInset,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.width,
              maxWidth: widget.width,
              maxHeight: maxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: widget.title,
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: widget.body,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: widget.actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

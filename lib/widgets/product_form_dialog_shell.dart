import 'dart:math' as math;

import 'package:flutter/material.dart';

class ProductFormDialogHeader extends StatelessWidget {
  const ProductFormDialogHeader({
    super.key,
    required this.title,
    required this.icon,
    this.color = Colors.green,
  });
  final String title;
  final IconData icon;
  final MaterialColor color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color, color.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
      ],
    ),
  );
}

class ProductFormDialogActions extends StatelessWidget {
  const ProductFormDialogActions({
    super.key,
    required this.onSubmit,
    required this.submitLabel,
    required this.submitIcon,
    this.color = Colors.green,
  });
  final VoidCallback onSubmit;
  final String submitLabel;
  final IconData submitIcon;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 340;
      final fontSize = compact ? 14.0 : 16.0;
      final padding = EdgeInsets.symmetric(
        horizontal: compact ? 6 : 12,
        vertical: 14,
      );
      return Row(
        children: [
          Expanded(
            flex: 4,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
                padding: padding,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/icons/menu/cancel_button.png',
                    width: 18,
                    height: 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Cancelar',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fontSize),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: padding,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(submitIcon, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      submitLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

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
            child: maxHeight < 320
                ? SingleChildScrollView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          widget.title,
                          const SizedBox(height: 12),
                          widget.body,
                          const SizedBox(height: 12),
                          widget.actions,
                        ],
                      ),
                    ),
                  )
                : Column(
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

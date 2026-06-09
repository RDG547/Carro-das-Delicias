import 'dart:math' as math;

import 'package:flutter/material.dart';

class AdaptiveDropdownMenu<T> extends StatefulWidget {
  final List<T> items;
  final T? selectedItem;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext context, bool isOpen) buttonBuilder;
  final Widget Function(BuildContext context, T item, bool isSelected)
  itemBuilder;
  final double itemHeight;
  final int maxVisibleItems;
  final double menuWidth;
  final BorderRadius borderRadius;

  const AdaptiveDropdownMenu({
    super.key,
    required this.items,
    required this.selectedItem,
    required this.onSelected,
    required this.buttonBuilder,
    required this.itemBuilder,
    this.itemHeight = 52,
    this.maxVisibleItems = 5,
    this.menuWidth = 0,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<AdaptiveDropdownMenu<T>> createState() =>
      _AdaptiveDropdownMenuState<T>();
}

class _AdaptiveDropdownMenuState<T> extends State<AdaptiveDropdownMenu<T>> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  ScrollPosition? _scrollPosition;

  bool get _isOpen => _overlayEntry != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition == nextPosition) return;

    _scrollPosition?.isScrollingNotifier.removeListener(_handleAncestorScroll);
    _scrollPosition = nextPosition;
    _scrollPosition?.isScrollingNotifier.addListener(_handleAncestorScroll);
  }

  @override
  void dispose() {
    _scrollPosition?.isScrollingNotifier.removeListener(_handleAncestorScroll);
    _removeMenu(notify: false);
    super.dispose();
  }

  void _handleAncestorScroll() {
    if (_scrollPosition?.isScrollingNotifier.value == true) {
      _removeMenu();
    }
  }

  void _toggleMenu() {
    if (_isOpen) {
      _removeMenu();
    } else {
      _showMenu();
    }
  }

  void _removeMenu({bool notify = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  void _showMenu() {
    if (widget.items.isEmpty) return;

    final buttonContext = _buttonKey.currentContext;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final buttonBox = buttonContext?.findRenderObject() as RenderBox?;

    if (buttonContext == null || overlayBox == null || buttonBox == null) {
      return;
    }

    final mediaQuery = MediaQuery.of(context);
    final buttonOffset = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final buttonSize = buttonBox.size;
    const gap = 6.0;
    const screenMargin = 8.0;
    final visibleTop = mediaQuery.padding.top + screenMargin;
    final visibleBottom =
        overlayBox.size.height - mediaQuery.padding.bottom - screenMargin;
    final desiredHeight =
        math.min(widget.items.length, widget.maxVisibleItems) *
        widget.itemHeight;
    final spaceBelow =
        visibleBottom - buttonOffset.dy - buttonSize.height - gap;
    final spaceAbove = buttonOffset.dy - visibleTop - gap;
    final openDown = spaceBelow >= desiredHeight || spaceBelow >= spaceAbove;
    final availableHeight = math.max(
      widget.itemHeight,
      openDown ? spaceBelow : spaceAbove,
    );
    final menuHeight = math.min(desiredHeight, availableHeight);
    final menuWidth = widget.menuWidth > 0
        ? widget.menuWidth
        : buttonSize.width;
    final left = (buttonOffset.dx)
        .clamp(screenMargin, overlayBox.size.width - menuWidth - screenMargin)
        .toDouble();
    final top = openDown
        ? buttonOffset.dy + buttonSize.height + gap
        : buttonOffset.dy - gap - menuHeight;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeMenu,
              ),
            ),
            Positioned(
              left: left,
              top: top.clamp(visibleTop, visibleBottom - menuHeight),
              width: menuWidth,
              height: menuHeight,
              child: Material(
                color: Colors.white,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.20),
                borderRadius: widget.borderRadius,
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  thumbVisibility: widget.items.length > widget.maxVisibleItems,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemExtent: widget.itemHeight,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isSelected = item == widget.selectedItem;

                      return InkWell(
                        onTap: () {
                          widget.onSelected(item);
                          _removeMenu();
                        },
                        child: widget.itemBuilder(context, item, isSelected),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: _toggleMenu,
      child: widget.buttonBuilder(context, _isOpen),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';

/// Keyed by the authoritative sequence, so a refresh cannot retain an old gap.
/// A drop uses the category ID captured when the long press began.
class CategoryReorderList extends StatefulWidget {
  const CategoryReorderList({
    super.key,
    required this.categories,
    required this.itemBuilder,
    required this.onReordered,
    this.onDraggingChanged,
    this.revision = 0,
    this.enabled = true,
    this.shrinkWrap = false,
    this.padding,
  });
  final List<Map<String, dynamic>> categories;
  final Widget Function(Map<String, dynamic>, int) itemBuilder;
  final FutureOr<void> Function(List<Map<String, dynamic>>) onReordered;
  final ValueChanged<bool>? onDraggingChanged;
  final int revision;
  final bool enabled;
  final bool shrinkWrap;
  final EdgeInsets? padding;
  @override
  State<CategoryReorderList> createState() => _CategoryReorderListState();
}

class _CategoryReorderListState extends State<CategoryReorderList> {
  final _scroll = ScrollController();
  Object? _draggedId;
  Timer? _end;
  bool _savingDrop = false;

  void _finished() {
    _end?.cancel();
    _draggedId = null;
    widget.onDraggingChanged?.call(false);
  }

  @override
  void dispose() {
    _end?.cancel();
    if (_draggedId != null) {
      final notify = widget.onDraggingChanged;
      scheduleMicrotask(() => notify?.call(false));
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: (_) {
      if (_draggedId != null && !_savingDrop) _finished();
    },
    child: ReorderableListView.builder(
      key: ValueKey(
        Object.hashAll([
          widget.revision,
          ...widget.categories.map((c) => c['id']),
        ]),
      ),
      scrollController: _scroll,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      physics: const AlwaysScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) =>
          RepaintBoundary(child: child),
      itemCount: widget.categories.length,
      onReorderStart: (index) {
        _end?.cancel();
        _draggedId = widget.categories[index]['id'];
        widget.onDraggingChanged?.call(true);
      },
      onReorderEnd: (_) {
        // onReorderEnd precedes the drop animation and onReorderItem. Don't let
        // an incoming read replace the list between those two callbacks.
        _end?.cancel();
        _end = Timer(const Duration(milliseconds: 600), () {
          if (mounted && !_savingDrop) _finished();
        });
      },
      onReorderItem: (oldIndex, newIndex) async {
        final id = _draggedId;
        if (!widget.enabled || id == null || _savingDrop) return;
        final ordered = List<Map<String, dynamic>>.from(widget.categories);
        final source = ordered.indexWhere((c) => c['id'] == id);
        if (source < 0 || newIndex < 0 || newIndex >= ordered.length) {
          _finished();
          return;
        }
        _savingDrop = true;
        final moved = ordered.removeAt(source);
        ordered.insert(newIndex, moved);
        try {
          await widget.onReordered(ordered);
        } finally {
          _savingDrop = false;
          if (mounted) _finished();
        }
      },
      itemBuilder: (context, index) {
        final category = widget.categories[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(category['id']),
          index: index,
          enabled: widget.enabled,
          child: widget.itemBuilder(category, index),
        );
      },
    ),
  );
}

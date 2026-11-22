import 'package:flutter/material.dart';

class TrackingInfoSheet extends StatefulWidget {
  const TrackingInfoSheet({
    super.key,
    required this.expanded,
    required this.expandedHeight,
    required this.onChanged,
    required this.child,
  });
  final bool expanded;
  final double expandedHeight;
  final ValueChanged<bool> onChanged;
  final Widget child;
  @override
  State<TrackingInfoSheet> createState() => _TrackingInfoSheetState();
}

class _TrackingInfoSheetState extends State<TrackingInfoSheet> {
  double _distance = 0;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
    height: widget.expanded ? widget.expandedHeight : 60,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .15),
          blurRadius: 20,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.expanded)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: widget.child,
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(!widget.expanded),
          onVerticalDragStart: (_) => _distance = 0,
          onVerticalDragUpdate: (details) => _distance += details.delta.dy,
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 150 || _distance > 18) widget.onChanged(true);
            if (velocity < -150 || _distance < -18) widget.onChanged(false);
          },
          child: Semantics(
            button: true,
            label: widget.expanded
                ? 'Recolher informações'
                : 'Expandir informações',
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.expanded
                        ? 'Arraste para cima'
                        : 'Arraste para baixo',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

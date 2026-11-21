import 'package:flutter/material.dart';

import 'category_icon_widget.dart';

class CategoryReorderDialog extends StatefulWidget {
  const CategoryReorderDialog({
    super.key,
    required this.categories,
    required this.onSave,
  });

  final List<Map<String, dynamic>> categories;
  final Future<bool> Function(List<Map<String, dynamic>>) onSave;

  @override
  State<CategoryReorderDialog> createState() => _CategoryReorderDialogState();
}

class _CategoryReorderDialogState extends State<CategoryReorderDialog> {
  late final _categories = List<Map<String, dynamic>>.from(widget.categories);
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await widget.onSave(_categories);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Reordenar Categorias',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: _categories.length,
                  proxyDecorator: (child, index, animation) => child,
                  onReorderItem: (oldIndex, newIndex) {
                    if (_saving) return;
                    setState(() {
                      final category = _categories.removeAt(oldIndex);
                      _categories.insert(newIndex, category);
                    });
                  },
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Card(
                      key: ValueKey(category['id']),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 12,
                          right: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          foregroundColor: Colors.blue.shade700,
                          child: Text('${index + 1}'),
                        ),
                        title: Row(
                          children: [
                            CategoryIconWidget(
                              icone: category['icone'] ?? '📦',
                              categoryName: category['nome'],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(category['nome'] ?? '', maxLines: 2),
                            ),
                          ],
                        ),
                        trailing: CategoryDragHandle(
                          index: index,
                          enabled: !_saving,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                      ),
                      child: const Text(
                        'Cancelar',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        minimumSize: const Size(0, 48),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.save, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _saving ? 'Salvando…' : 'Salvar ordem',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Only this target starts a drag; pressing a card or scrolling never does.
class CategoryDragHandle extends StatelessWidget {
  const CategoryDragHandle({
    super.key,
    required this.index,
    this.enabled = true,
  });
  final int index;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    enabled: enabled,
    child: Semantics(
      label: 'Arraste para reordenar',
      child: const ColoredBox(
        color: Colors.transparent,
        child: SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle)),
      ),
    ),
  );
}

import 'category_reorder_list.dart';
import '../utils/category_order.dart';
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
  late final _categories = CategoryOrder.sorted(widget.categories);
  bool _saving = false;
  bool _dragging = false;

  Future<void> _save() async {
    if (_saving || _dragging) return;
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
    canPop: !_saving && !_dragging,
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
                child: CategoryReorderList(
                  categories: _categories,
                  shrinkWrap: true,
                  enabled: !_saving,
                  onDraggingChanged: (dragging) {
                    if (mounted) setState(() => _dragging = dragging);
                  },
                  onReordered: (ordered) {
                    if (_saving) return;
                    setState(() {
                      _categories.clear();
                      _categories.addAll(ordered);
                    });
                  },
                  itemBuilder: (category, index) {
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
                      onPressed: _saving || _dragging
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.all(8),
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
                          const Flexible(
                            child: Text(
                              'Cancelar',
                              textAlign: TextAlign.center,
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
                      onPressed: _saving || _dragging ? null : _save,
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

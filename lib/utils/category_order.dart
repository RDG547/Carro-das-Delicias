class CategoryOrder {
  static List<Map<String, dynamic>> sorted(
    Iterable<Map<String, dynamic>> categories,
  ) {
    int number(dynamic value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 2147483647;
    return List<Map<String, dynamic>>.from(categories)..sort((a, b) {
      final order = number(a['ordem']).compareTo(number(b['ordem']));
      return order == 0 ? number(a['id']).compareTo(number(b['id'])) : order;
    });
  }

  /// Reordena somente os itens visíveis, preservando os lugares dos ocultos.
  static List<Map<String, dynamic>> mergeVisible(
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> visible,
  ) {
    final ids = visible.map((item) => item['id']).toSet();
    if (ids.length != visible.length ||
        !ids.every((id) => all.any((item) => item['id'] == id))) {
      throw ArgumentError('A lista de categorias foi alterada.');
    }
    var index = 0;
    final ordered = all
        .map((item) => ids.contains(item['id']) ? visible[index++] : item)
        .toList();
    return [
      for (var i = 0; i < ordered.length; i++)
        {...ordered[i], 'ordem': i, 'order': i},
    ];
  }
}

/// Extracts display labels without leaking provider IDs or structured metadata.
class GeocodingText {
  static String? label(dynamic value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }
    if (value is num) return value.toString();
    if (value is Map) {
      for (final key in const ['name_preferred', 'name', 'text']) {
        final text = label(value[key]);
        if (text != null) return text;
      }
    }
    return null;
  }

  /// Key priority is independent of the order of properties in the response.
  static String? find(dynamic value, Iterable<String> keys) {
    for (final key in keys) {
      final found = _find(value, key, 0);
      if (found != null) return found;
    }
    return null;
  }

  static String? _find(dynamic value, String key, int depth) {
    if (depth > 6) return null;
    if (value is Map) {
      final direct = label(value[key]);
      if (direct != null) return direct;
      for (final entry in value.entries) {
        // Translations and identifiers aren't address components.
        if (entry.key == 'translations' || entry.key == 'geometry') continue;
        final found = _find(entry.value, key, depth + 1);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _find(item, key, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }
}

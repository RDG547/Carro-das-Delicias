/// Busca por palavras, prefixos e pequenos erros, exigindo todos os termos.
class FuzzySearchService {
  static const _stopWords = {
    'de',
    'da',
    'do',
    'das',
    'dos',
    'e',
    'com',
    'para',
  };
  static String removeAccents(String text) {
    const groups = {
      'a': 'àáâãäå',
      'e': 'èéêë',
      'i': 'ìíîï',
      'o': 'òóôõöø',
      'u': 'ùúûü',
      'c': 'ç',
      'n': 'ñ',
      'y': 'ÿ',
    };
    var result = text;
    for (final entry in groups.entries) {
      for (final char in entry.value.split('')) {
        result = result
            .replaceAll(char, entry.key)
            .replaceAll(char.toUpperCase(), entry.key.toUpperCase());
      }
    }
    return result;
  }

  static String normalize(String text) => removeAccents(
    text.toLowerCase(),
  ).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  static List<String> _words(String value) => normalize(
    value,
  ).split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  static List<String> _terms(String query) {
    final words = _words(query);
    final significant = words
        .where((word) => !_stopWords.contains(word))
        .toList();
    return significant.isEmpty ? words : significant;
  }

  static int levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final minimum = insertion < deletion ? insertion : deletion;
        current[j] = minimum < substitution ? minimum : substitution;
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }

  static bool isSubsequence(String query, String text) {
    var index = 0;
    for (var i = 0; i < text.length && index < query.length; i++) {
      if (text[i] == query[index]) index++;
    }
    return index == query.length;
  }

  static double _wordScore(String term, String word) {
    if (word == term) return 1;
    if (word.startsWith(term)) return 0.94;
    if (term.length < 4 || word.length < 4) return 0;
    final maxDistance = term.length >= 7 ? 2 : 1;
    if ((word.length - term.length).abs() > maxDistance) return 0;
    final distance = levenshteinDistance(term, word);
    return distance <= maxDistance ? 0.80 - distance * 0.08 : 0;
  }

  static double _bestWordScore(String term, List<String> words) {
    var best = 0.0;
    for (final word in words) {
      final score = _wordScore(term, word);
      if (score > best) best = score;
      if (best == 1) break;
    }
    return best;
  }

  static double calculateRelevance(String query, String text) {
    if (query.trim().isEmpty) return 1;
    final terms = _terms(query), words = _words(text);
    if (terms.isEmpty || words.isEmpty) return 0;
    var total = 0.0;
    for (final term in terms) {
      final score = _bestWordScore(term, words);
      if (score == 0) return 0;
      total += score;
    }
    final normalizedText = normalize(text), normalizedQuery = normalize(query);
    if (normalizedText == normalizedQuery) return 1;
    if (normalizedText.startsWith(normalizedQuery)) return 0.98;
    return total / terms.length * 0.92;
  }

  static List<Map<String, dynamic>> searchProducts(
    List<Map<String, dynamic>> products,
    String query,
  ) {
    if (query.trim().isEmpty) return List.of(products);
    final terms = _terms(query);
    if (terms.isEmpty) return List.of(products);
    final scored =
        <({Map<String, dynamic> product, double score, int index})>[];
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final name = product['nome']?.toString() ?? '';
      final nameWords = _words(name);
      final description = _words(product['descricao']?.toString() ?? '');
      final category = _words(
        product['categoria_nome']?.toString() ??
            (product['categorias'] is Map
                ? product['categorias']['nome']?.toString()
                : null) ??
            '',
      );
      var total = 0.0;
      var matches = true;
      for (final term in terms) {
        final nameMatch = _bestWordScore(term, nameWords);
        final categoryMatch = _bestWordScore(term, category) * 0.55;
        final descriptionMatch = _bestWordScore(term, description) * 0.45;
        var best = nameMatch > categoryMatch ? nameMatch : categoryMatch;
        if (descriptionMatch > best) best = descriptionMatch;
        if (best == 0) {
          matches = false;
          break;
        }
        total += best;
      }
      if (!matches) continue;
      final nameScore = calculateRelevance(query, name);
      final score = nameScore > 0
          ? 0.6 + nameScore * 0.4
          : total / terms.length * 0.55;
      scored.add((product: product, score: score, index: index));
    }
    scored.sort((a, b) {
      final relevance = b.score.compareTo(a.score);
      return relevance != 0 ? relevance : a.index.compareTo(b.index);
    });
    return scored.map((entry) => entry.product).toList();
  }
}

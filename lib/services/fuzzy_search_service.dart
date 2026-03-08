/// Serviço de busca fuzzy para pesquisa inteligente de produtos.
/// Suporta:
/// - Busca sem acentos
/// - Tolerância a erros de digitação (fuzzy matching)
/// - Ordenação por relevância
/// - Busca por subsequência (letras na ordem correta)
class FuzzySearchService {
  /// Remove acentos e caracteres especiais para busca normalizada.
  static String removeAccents(String text) {
    const withAccents =
        'àáâãäåòóôõöøèéêëçìíîïùúûüÿñÀÁÂÃÄÅÒÓÔÕÖØÈÉÊËÇÌÍÎÏÙÚÛÜŸÑ';
    const withoutAccents =
        'aaaaaaooooooeeeeciiiiuuuuynAAAAAAOOOOOOEEEECIIIIUUUUYN';

    String result = text;
    for (int i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result;
  }

  /// Calcula a distância de Levenshtein entre duas strings.
  /// Retorna o número mínimo de edições (inserções, deleções, substituições)
  /// para transformar [a] em [b].
  static int levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Otimização: usar apenas duas linhas da matrix
    List<int> previousRow = List<int>.generate(b.length + 1, (i) => i);
    List<int> currentRow = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      currentRow[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        currentRow[j] = [
          currentRow[j - 1] + 1, // inserção
          previousRow[j] + 1, // deleção
          previousRow[j - 1] + cost, // substituição
        ].reduce((a, b) => a < b ? a : b);
      }
      // Trocar as linhas
      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[b.length];
  }

  /// Verifica se [query] é uma subsequência de [text].
  /// Ex: "blo" é subsequência de "bolo" (b-o-l-o contém b-l-o na ordem).
  /// Na verdade, verifica se as letras da query aparecem em ordem no texto.
  static bool isSubsequence(String query, String text) {
    int qi = 0;
    for (int ti = 0; ti < text.length && qi < query.length; ti++) {
      if (text[ti] == query[qi]) {
        qi++;
      }
    }
    return qi == query.length;
  }

  /// Calcula um score de relevância [0.0..1.0] para um texto dado a query.
  /// Retorna 0.0 se não houver match, valores mais altos = mais relevante.
  static double calculateRelevance(String query, String text) {
    if (query.isEmpty) return 1.0;

    final normalizedQuery = removeAccents(query.toLowerCase());
    final normalizedText = removeAccents(text.toLowerCase());

    // Match exato — máxima relevância
    if (normalizedText == normalizedQuery) return 1.0;

    // Começa com a query — alta relevância
    if (normalizedText.startsWith(normalizedQuery)) return 0.95;

    // Contém a query como substring — boa relevância
    if (normalizedText.contains(normalizedQuery)) return 0.9;

    // Verificar match por palavras individuais
    final queryWords = normalizedQuery.split(RegExp(r'\s+'));
    final textWords = normalizedText.split(RegExp(r'\s+'));
    int matchedWords = 0;
    for (final qw in queryWords) {
      for (final tw in textWords) {
        if (tw.contains(qw) || tw.startsWith(qw)) {
          matchedWords++;
          break;
        }
      }
    }
    if (matchedWords == queryWords.length) return 0.85;

    // Subsequência — as letras da query aparecem na ordem no texto
    if (isSubsequence(normalizedQuery, normalizedText)) return 0.7;

    // Fuzzy match por palavras — tolera 1-2 erros
    for (final tw in textWords) {
      for (final qw in queryWords) {
        final maxDistance = qw.length <= 3 ? 1 : 2;
        final distance = levenshteinDistance(qw, tw);
        if (distance <= maxDistance) {
          return 0.6 - (distance * 0.1);
        }
        // Verificar se alguma palavra do texto começa parecido
        if (tw.length >= qw.length) {
          final prefix = tw.substring(0, qw.length);
          final prefixDist = levenshteinDistance(qw, prefix);
          if (prefixDist <= maxDistance) {
            return 0.55 - (prefixDist * 0.1);
          }
        }
      }
    }

    // Fuzzy match no texto completo — para queries curtas
    if (normalizedQuery.length <= 5) {
      final distance = levenshteinDistance(normalizedQuery, normalizedText);
      final maxAllowed = normalizedQuery.length <= 3 ? 1 : 2;
      if (distance <= maxAllowed) {
        return 0.4;
      }
    }

    return 0.0; // Sem match
  }

  /// Filtra e ordena uma lista de produtos por relevância à query.
  /// Retorna os produtos que têm algum match, ordenados do mais relevante
  /// para o menos relevante.
  static List<Map<String, dynamic>> searchProducts(
    List<Map<String, dynamic>> products,
    String query,
  ) {
    if (query.isEmpty) return products;

    final scored = <MapEntry<Map<String, dynamic>, double>>[];

    for (final produto in products) {
      final nome = produto['nome']?.toString() ?? '';
      final descricao = produto['descricao']?.toString() ?? '';
      final categoriaNome = produto['categoria_nome']?.toString() ?? '';

      // Calcular relevância para nome (peso maior), descrição e categoria
      final nomeScore = calculateRelevance(query, nome);
      final descricaoScore = calculateRelevance(query, descricao) * 0.6;
      final categoriaScore = calculateRelevance(query, categoriaNome) * 0.4;

      // Pegar o melhor score
      final bestScore = [nomeScore, descricaoScore, categoriaScore]
          .reduce((a, b) => a > b ? a : b);

      if (bestScore > 0.0) {
        scored.add(MapEntry(produto, bestScore));
      }
    }

    // Ordenar por relevância (mais relevante primeiro)
    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.map((e) => e.key).toList();
  }
}

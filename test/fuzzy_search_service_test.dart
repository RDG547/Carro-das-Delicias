import 'package:carrodasdelicias/services/fuzzy_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final products = <Map<String, dynamic>>[
    {
      'id': 1,
      'nome': 'Goiabada Cascão',
      'descricao': 'Feita com pedaços de goiaba',
    },
    {'id': 2, 'nome': 'Mel de Abelha', 'descricao': 'Mel puro, sabor natural'},
    {'id': 3, 'nome': 'Bolo de Chocolate', 'categoria_nome': 'Bolos'},
    {'id': 4, 'nome': 'Bolo de Cenoura', 'categoria_nome': 'Bolos'},
    {
      'id': 5,
      'nome': 'Bolo de Cenoura com Chocolate',
      'categoria_nome': 'Bolos',
    },
  ];
  test(
    'busca parcial exige todos os termos e exclui resultados sem relação',
    () {
      expect(
        FuzzySearchService.searchProducts(
          products,
          'bolo de cenou',
        ).map((p) => p['id']),
        [4, 5],
      );
    },
  );
  test('aceita acentos, caixa, espaços e um erro de digitação', () {
    expect(
      FuzzySearchService.searchProducts(
        products,
        '  BÔLO de cenora  ',
      ).map((p) => p['id']),
      [4, 5],
    );
  });
  test('um termo coincidente não basta para uma busca composta', () {
    expect(
      FuzzySearchService.searchProducts(products, 'bolo de morango'),
      isEmpty,
    );
  });
  test('nome exato tem prioridade sobre coincidência na descrição', () {
    final results = FuzzySearchService.searchProducts([
      {
        'id': 1,
        'nome': 'Caixa de Doces',
        'descricao': 'Inclui bolo de cenoura',
      },
      products[3],
    ], 'bolo de cenoura');
    expect(results.first['id'], 4);
  });
  test('termos curtos não aceitam correspondências vagas', () {
    expect(
      FuzzySearchService.searchProducts(products, 'mel').map((p) => p['id']),
      [2],
    );
  });
  test('busca vazia mantém a ordem original', () {
    expect(FuzzySearchService.searchProducts(products, '   '), products);
  });
}

import 'package:carrodasdelicias/utils/product_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gera link público em domínio existente', () {
    expect(
      ProductLinks.forProduct(67).toString(),
      'https://carrodasdelicias.vercel.app/produto/67',
    );
  });
  test('aceita o app link e o esquema nativo usado pelo fallback', () {
    for (final value in [
      'https://carrodasdelicias.vercel.app/produto/67',
      'carrodasdelicias://produto/67',
      'carrodasdelicias:///produto/67',
    ]) {
      expect(ProductLinks.productIdFrom(Uri.parse(value)), '67');
    }
  });
  test(
    'rejeita domínio inesperado, callback auth e identificadores inválidos',
    () {
      for (final value in [
        'https://outro.example/produto/67',
        'carrodasdelicias://auth-callback',
        'https://carrodasdelicias.vercel.app/produto/0',
        'carrodasdelicias://produto/nulo',
      ]) {
        expect(ProductLinks.productIdFrom(Uri.parse(value)), isNull);
      }
    },
  );
}

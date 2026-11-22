import 'package:carrodasdelicias/utils/support_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email de suporte mantém espaços, acentos e os dados da conta', () {
    final uri = SupportEmail.compose(
      name: 'Ana Júlia',
      email: 'ana+app@example.test',
    );
    expect(uri.path, 'arrodasdelicias@rdtech.dev.br');
    expect(uri.toString(), isNot(contains('+')));
    expect(uri.queryParameters['subject'], 'Suporte - Carro das Delícias');
    expect(
      uri.queryParameters['body'],
      'Nome: Ana Júlia\nE-mail da conta: ana+app@example.test\nNúmero do pedido (se houver):\nMensagem:\n',
    );
  });
  test('visitante recebe somente os campos básicos, sem dados nulos', () {
    final body = SupportEmail.compose().queryParameters['body']!;
    expect(body, isNot(contains('null')));
    expect(body.split('\n').length, 5);
  });
}

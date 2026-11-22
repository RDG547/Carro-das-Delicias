class SupportEmail {
  static const address = 'arrodasdelicias@rdtech.dev.br';

  static Uri compose({String? name, String? email}) {
    final fields = {
      'subject': 'Suporte - Carro das Delícias',
      'body':
          'Nome: ${name?.trim() ?? ''}\n'
          'E-mail da conta: ${email?.trim() ?? ''}\n'
          'Número do pedido (se houver):\n'
          'Mensagem:\n',
    };
    // mailto uses percent encoding, not HTML form encoding (+ for spaces).
    return Uri(
      scheme: 'mailto',
      path: address,
      query: fields.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&'),
    );
  }
}

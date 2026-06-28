import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/base_screen.dart';

class SupportLegalScreen extends StatelessWidget {
  const SupportLegalScreen({super.key});

  static const _supportEmail = 'contato@carrodasdelicias.com.br';

  Future<void> _openSupportEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'Suporte - Carro das Delícias',
        'body':
            'Olá, preciso de ajuda com o app Carro das Delícias.\n\nNome:\nE-mail da conta:\nNúmero do pedido, se houver:\nMensagem:',
      },
    );

    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o app de e-mail.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Ajuda e Políticas',
      showBackButton: true,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.black, Colors.grey],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.policy_outlined, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Suporte, termos de uso e privacidade em um só lugar.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _InfoSection(
            icon: Icons.support_agent,
            title: 'Ajuda e Suporte',
            color: Colors.green,
            paragraphs: const [
              'Se precisar de ajuda com login, cadastro, pedidos, pagamentos, entrega ou rastreamento da Kombi, entre em contato com o suporte.',
              'Para agilizar o atendimento, informe o nome cadastrado no app, e-mail da conta e o número do pedido quando existir.',
            ],
            action: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openSupportEmail(context),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Entrar em contato'),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _InfoSection(
            icon: Icons.privacy_tip_outlined,
            title: 'Política de Privacidade',
            color: Colors.purple,
            paragraphs: [
              'Coletamos dados de cadastro como nome, e-mail, telefone, endereço e foto de perfil para login, identificação, atendimento e entrega dos pedidos.',
              'Dados de pedidos, pagamento e entrega são usados para processar compras, confirmar informações e prestar suporte. Não armazenamos dados completos de cartão de crédito.',
              'A localização da Kombi é usada para mostrar o rastreamento quando o recurso estiver ativo. A localização do usuário só é usada quando necessária para recursos do app e permissões concedidas.',
              'Podemos compartilhar dados estritamente necessários com serviços de autenticação, banco de dados, notificações, pagamentos e entrega, sempre para funcionamento do aplicativo.',
              'Você pode solicitar correção, atualização ou exclusão dos seus dados pelo suporte.',
            ],
          ),
          const SizedBox(height: 14),
          const _InfoSection(
            icon: Icons.description_outlined,
            title: 'Termos de Uso',
            color: Colors.blue,
            paragraphs: [
              'Ao usar o Carro das Delícias, você concorda em informar dados verdadeiros e atualizados para cadastro, contato, entrega e pagamento.',
              'Produtos, preços, promoções, categorias, disponibilidade e prazos podem mudar conforme estoque, operação da Kombi e região atendida.',
              'Pedidos dependem da confirmação de pagamento e da disponibilidade operacional. Dados incorretos de contato ou endereço podem impedir a entrega.',
              'É proibido usar o app para fraude, acesso indevido, tentativa de burlar pagamentos ou prejudicar a operação do serviço.',
              'O uso contínuo do aplicativo após atualizações indica concordância com a versão vigente destes termos.',
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<String> paragraphs;
  final Widget? action;

  const _InfoSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.paragraphs,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...paragraphs.map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                paragraph,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

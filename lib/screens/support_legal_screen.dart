import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/support_email.dart';

import '../widgets/base_screen.dart';
import '../widgets/main_navigation_provider.dart';

enum _SupportLegalTab { support, privacy, terms }

class SupportLegalScreen extends StatefulWidget {
  const SupportLegalScreen({super.key});

  @override
  State<SupportLegalScreen> createState() => _SupportLegalScreenState();
}

class _SupportLegalScreenState extends State<SupportLegalScreen> {
  _SupportLegalTab _selectedTab = _SupportLegalTab.support;

  Future<void> _openSupportEmail(BuildContext context) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    var name = (user?.userMetadata?['name'] ?? user?.userMetadata?['full_name'])
        ?.toString();
    if (user != null) {
      try {
        final profile = await client
            .from('profiles')
            .select('name')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 3));
        if (profile?['name']?.toString().trim().isNotEmpty == true)
          name = profile!['name'].toString();
      } catch (_) {
        // Account metadata remains available when the profile cannot be fetched.
      }
    }
    if (!context.mounted) return;
    final uri = SupportEmail.compose(name: name, email: user?.email);

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
    final navigation = MainNavigationProvider.of(context);
    final bottomPadding = 132.0 + MediaQuery.viewPaddingOf(context).bottom;

    return BaseScreen(
      title: 'Ajuda e Políticas',
      showBackButton: true,
      onBackPressed: navigation?.navigateToHome,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: [
          _LegalSegmentedControl(
            selectedTab: _selectedTab,
            onChanged: (tab) => setState(() => _selectedTab = tab),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildSelectedSection(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSection(BuildContext context) {
    switch (_selectedTab) {
      case _SupportLegalTab.support:
        return _InfoSection(
          key: const ValueKey('support'),
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
        );
      case _SupportLegalTab.privacy:
        return const _InfoSection(
          key: ValueKey('privacy'),
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
        );
      case _SupportLegalTab.terms:
        return const _InfoSection(
          key: ValueKey('terms'),
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
        );
    }
  }
}

class _LegalSegmentedControl extends StatelessWidget {
  final _SupportLegalTab selectedTab;
  final ValueChanged<_SupportLegalTab> onChanged;

  const _LegalSegmentedControl({
    required this.selectedTab,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LegalTabButton(
              selected: selectedTab == _SupportLegalTab.support,
              icon: Icons.support_agent,
              label: 'Ajuda',
              onTap: () => onChanged(_SupportLegalTab.support),
            ),
          ),
          Expanded(
            child: _LegalTabButton(
              selected: selectedTab == _SupportLegalTab.privacy,
              icon: Icons.privacy_tip_outlined,
              label: 'Privacidade',
              onTap: () => onChanged(_SupportLegalTab.privacy),
            ),
          ),
          Expanded(
            child: _LegalTabButton(
              selected: selectedTab == _SupportLegalTab.terms,
              icon: Icons.description_outlined,
              label: 'Termos',
              onTap: () => onChanged(_SupportLegalTab.terms),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LegalTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.black : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.black,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
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
    super.key,
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

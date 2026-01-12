import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../providers/admin_status_provider.dart';
import '../widgets/app_menu.dart';

class NovidadesScreen extends StatefulWidget {
  const NovidadesScreen({super.key});

  @override
  State<NovidadesScreen> createState() => _NovidadesScreenState();
}

class _NovidadesScreenState extends State<NovidadesScreen> {
  // Lista mock de novidades
  final List<Map<String, dynamic>> _novidades = [
    {
      'id': 1,
      'titulo': 'Novo Açaí Premium',
      'descricao': 'Experimente nosso novo açaí premium com granola especial',
      'data': '15 de setembro de 2025',
      'imagem': 'assets/images/acai_premium.jpg',
      'novo': true,
    },
    {
      'id': 2,
      'titulo': 'Promoção Especial',
      'descricao': 'Compre 2 açaís e ganhe 1 adicional grátis',
      'data': '10 de setembro de 2025',
      'imagem': 'assets/images/promocao.jpg',
      'novo': false,
    },
    {
      'id': 3,
      'titulo': 'Nova Cobertura: Nutella',
      'descricao': 'Agora você pode adicionar Nutella ao seu açaí',
      'data': '5 de setembro de 2025',
      'imagem': 'assets/images/nutella.jpg',
      'novo': false,
    },
  ];

  void _goToHome() {
    debugPrint('🔙 Botão de voltar pressionado na tela de novidades');
    // Pop até a primeira rota OU apenas um pop se já estiver próximo
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuestMode = user == null;
    final adminProvider = AdminStatusProvider.of(context);
    final isAdmin = adminProvider?.isAdmin ?? false;

    return BaseScreen(
      title: 'Novidades',
      showBackButton: true,
      onBackPressed: _goToHome,
      actions: [AppMenu(isGuestMode: isGuestMode, isAdmin: isAdmin)],
      backgroundColor: Colors.grey[50],
      padding: EdgeInsets.zero,
      child: ListView.builder(
        addRepaintBoundaries: true,
        padding: const EdgeInsets.all(16),
        itemCount: _novidades.length,
        itemBuilder: (context, index) {
          final novidade = _novidades[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge "NOVO" se aplicável
                if (novidade['novo'])
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[600],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'NOVO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                // Conteúdo
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    novidade['novo'] ? 0 : 16,
                    16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        novidade['titulo'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        novidade['descricao'],
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            novidade['data'],
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

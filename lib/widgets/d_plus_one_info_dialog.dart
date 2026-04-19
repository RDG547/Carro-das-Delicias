import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DPlusOneInfoDialog extends StatefulWidget {
  const DPlusOneInfoDialog({super.key});

  static const String prefKey = 'hide_d_plus_one_info';

  /// Mostra o dialog apenas se o usuário não tiver marcado para não mostrar novamente.
  /// Se [forceShow] for true, ignora a preferência e mostra mesmo assim (para o botão de info).
  static Future<void> show(
    BuildContext context, {
    bool forceShow = false,
  }) async {
    if (!forceShow) {
      final prefs = await SharedPreferences.getInstance();
      final shouldHide = prefs.getBool(prefKey) ?? false;
      if (shouldHide) return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => const DPlusOneInfoDialog(),
      );
    }
  }

  @override
  State<DPlusOneInfoDialog> createState() => _DPlusOneInfoDialogState();
}

class _DPlusOneInfoDialogState extends State<DPlusOneInfoDialog> {
  bool _doNotShowAgain = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(DPlusOneInfoDialog.prefKey) ?? false;
    if (mounted && saved != _doNotShowAgain) {
      setState(() => _doNotShowAgain = saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      title: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue[700]),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Política de Entrega (D+1)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(color: Colors.black87, fontSize: 16),
                children: [TextSpan(text: 'Trabalhamos com prazo D+1')],
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionTitle('O que isso significa?'),
            const Text(
              'A sigla D+1 define o prazo de execução de uma tarefa após um evento inicial.',
            ),
            const SizedBox(height: 8),
            _buildBulletPoint(
              'D (Dia)',
              'Dia em que o pedido/pagamento ocorreu.',
            ),
            _buildBulletPoint('+1', 'Prazo de 1 dia útil após o dia "D".'),
            const SizedBox(height: 12),
            _buildSectionTitle('Como funciona na prática?'),
            const Text(
              'Se você comprar hoje, o produto será enviado no próximo dia útil.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Exemplos de envio (D+1):',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            _buildExampleRow('Segunda-feira', 'Terça-feira'),
            _buildExampleRow('Terça-feira', 'Quarta-feira'),
            _buildExampleRow('Quinta-feira', 'Sexta-feira ou Sábado'),
            _buildExampleRow('Sexta/Sáb/Dom', 'Segunda-feira'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(color: Colors.black87, fontSize: 13),
                      children: [
                        TextSpan(text: '⚠️ '),
                        TextSpan(
                          text: 'Entregas nos finais de semana:',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Não realizamos entregas aos domingos.\n'
                    '• Pedidos feitos na quinta: entrega sexta ou sábado (você escolhe).\n'
                    '• Pedidos feitos sexta, sábado ou domingo serão entregues na segunda-feira.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                border: Border.all(color: Colors.amber),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  children: [
                    TextSpan(
                      text: 'Importante: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    TextSpan(
                      text:
                          'O prazo começa a contar a partir da confirmação do pagamento.',
                    ),
                  ],
                ),
              ),
            ),
            ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _doNotShowAgain,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      setState(() {
                        _doNotShowAgain = value ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _doNotShowAgain = !_doNotShowAgain;
                        });
                      },
                      child: const Text(
                        'Não mostrar esta mensagem novamente',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(DPlusOneInfoDialog.prefKey, _doNotShowAgain);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.check_circle),
          label: const Text(
            'Entendi',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.blue[700]),
      ),
    );
  }

  Widget _buildBulletPoint(String boldText, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            const TextSpan(text: '• '),
            TextSpan(
              text: '$boldText: ',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleRow(String diaD, String diaEnvio) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          Text(diaD, style: const TextStyle(fontSize: 13)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
          ),
          Expanded(
            child: Text(
              diaEnvio,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/abacatepay_service.dart';

class AbacatePayPaymentScreen extends StatefulWidget {
  final String pedidoId;
  final double amount;
  final String description;

  const AbacatePayPaymentScreen({
    super.key,
    required this.pedidoId,
    required this.amount,
    required this.description,
  });

  @override
  State<AbacatePayPaymentScreen> createState() =>
      _AbacatePayPaymentScreenState();
}

class _AbacatePayPaymentScreenState extends State<AbacatePayPaymentScreen> {
  final _abacatePayService = AbacatePayService();
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isPaid = false;
  String? _qrCode;
  String? _pixCode;
  String? _chargeId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _createPixCharge();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _createPixCharge() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _abacatePayService.createPixCharge(
        amount: widget.amount,
        description: widget.description,
        externalReference: widget.pedidoId,
      );

      if (result['success'] == true) {
        debugPrint('✅ PIX criado com sucesso!');
        debugPrint('ID: ${result['id']}');
        debugPrint('QR Code URL: ${result['qr_code_url']}');
        debugPrint('PIX Code: ${result['pix_code']}');

        setState(() {
          _chargeId = result['id'];
          _qrCode = result['qr_code_url'];
          _pixCode = result['pix_code'];
          _isLoading = false;
        });

        debugPrint(
          'Estado atualizado - _qrCode: $_qrCode, _pixCode: $_pixCode',
        );

        // Iniciar polling de status a cada 5 segundos
        _startPolling();
      } else {
        debugPrint('❌ Erro ao criar PIX: ${result['message']}');
        setState(() {
          _error = result['message'] ?? 'Erro ao gerar código PIX';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erro ao conectar com servidor de pagamento';
        _isLoading = false;
      });
      debugPrint('Erro ao criar cobrança PIX: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _chargeId == null) {
        timer.cancel();
        return;
      }

      try {
        final status = await _abacatePayService.checkPaymentStatus(_chargeId!);

        if (status['status'] == 'PAID' || status['status'] == 'CONFIRMED') {
          timer.cancel();
          setState(() {
            _isPaid = true;
          });

          // Aguardar 2 segundos para mostrar mensagem de sucesso
          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.of(context).pop({'success': true, 'chargeId': _chargeId});
          }
        }
      } catch (e) {
        debugPrint('Erro ao verificar status do pagamento: $e');
      }
    });
  }

  void _copyPixCode() {
    if (_pixCode != null) {
      Clipboard.setData(ClipboardData(text: _pixCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Código PIX copiado!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _pollingTimer?.cancel();
          Navigator.of(context).pop({'success': false});
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Pagamento PIX',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Gerando código PIX...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _createPixCharge,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar Novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isPaid) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pagamento confirmado!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Redirecionando...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Valor
          Text(
            'R\$ ${widget.amount.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // QR Code - sempre mostrar se temos o código PIX
          if (_pixCode != null && _pixCode!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: _pixCode!,
                version: QrVersions.auto,
                size: 250,
                backgroundColor: Colors.white,
              ),
            )
          else
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text(
                  'Código PIX não disponível',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Instruções
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Como pagar:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '1. Abra o app do seu banco\n'
                  '2. Escolha pagar via PIX\n'
                  '3. Escaneie o QR Code acima\n'
                  '4. Confirme o pagamento',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Código PIX copiável
          if (_pixCode != null && _pixCode!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code,
                        color: Colors.grey.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Código PIX:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _pixCode!,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),

          if (_pixCode != null && _pixCode!.isNotEmpty)
            const SizedBox(height: 16),

          // Botão Copiar Código - sempre mostrar se temos o código
          if (_pixCode != null && _pixCode!.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _copyPixCode,
                icon: const Icon(Icons.copy),
                label: const Text('Copiar Código PIX'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.copy),
                label: const Text('Código não disponível'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Status de verificação
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aguardando pagamento...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Botão Cancelar
          TextButton(
            onPressed: () {
              _pollingTimer?.cancel();
              Navigator.of(context).pop({'success': false});
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

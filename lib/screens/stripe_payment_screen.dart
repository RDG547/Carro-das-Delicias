import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/stripe_service.dart';

class StripePaymentScreen extends StatefulWidget {
  final String pedidoId;
  final double amount;
  final String description;
  final String customerEmail;

  const StripePaymentScreen({
    super.key,
    required this.pedidoId,
    required this.amount,
    required this.description,
    required this.customerEmail,
  });

  @override
  State<StripePaymentScreen> createState() => _StripePaymentScreenState();
}

class _StripePaymentScreenState extends State<StripePaymentScreen> {
  final _stripeService = StripeService();
  late WebViewController _webViewController;
  bool _isLoading = true;
  bool _isPaid = false;
  String? _checkoutUrl;
  String? _sessionId;
  String? _error;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _createCheckoutSession();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _createCheckoutSession() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _stripeService.createCheckoutSession(
        amount: widget.amount,
        description: widget.description,
        customerEmail: widget.customerEmail,
        metadata: {'pedido_id': widget.pedidoId},
      );

      if (result['success'] == true) {
        setState(() {
          _sessionId = result['session_id'];
          _checkoutUrl = result['url'];
          _isLoading = false;
        });

        // Inicializar WebView
        _initWebView();

        // Iniciar polling de status
        _startPolling();
      } else {
        setState(() {
          _error = result['message'] ?? 'Erro ao criar sessão de pagamento';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erro ao conectar com servidor de pagamento';
        _isLoading = false;
      });
      debugPrint('Erro ao criar checkout session: $e');
    }
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('Navegação iniciada: $url');

            // Verificar se voltou para success_url
            if (url.contains('/success')) {
              _handlePaymentSuccess();
            } else if (url.contains('/cancel')) {
              _handlePaymentCancel();
            }
          },
          onPageFinished: (String url) {
            debugPrint('Página carregada: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Erro no WebView: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(_checkoutUrl!));
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _sessionId == null) {
        timer.cancel();
        return;
      }

      try {
        final status = await _stripeService.checkSessionStatus(_sessionId!);

        if (status['status'] == 'complete') {
          timer.cancel();
          _handlePaymentSuccess();
        }
      } catch (e) {
        debugPrint('Erro ao verificar status do pagamento: $e');
      }
    });
  }

  void _handlePaymentSuccess() async {
    if (_isPaid) return;

    setState(() {
      _isPaid = true;
    });

    // Aguardar 1 segundo para mostrar mensagem de sucesso
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.of(context).pop({'success': true, 'sessionId': _sessionId});
    }
  }

  void _handlePaymentCancel() {
    _pollingTimer?.cancel();
    Navigator.of(context).pop({'success': false});
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
            'Pagamento com Cartão',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _handlePaymentCancel,
          ),
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
              'Carregando checkout...',
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
                onPressed: _createCheckoutSession,
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
              decoration: const BoxDecoration(
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

    // WebView com checkout Stripe
    return WebViewWidget(controller: _webViewController);
  }
}

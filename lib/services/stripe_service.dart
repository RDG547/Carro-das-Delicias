import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Serviço para integração com o Stripe para pagamentos com cartão
class StripeService {
  static const String _secretKey = String.fromEnvironment('STRIPE_SECRET_KEY');
  static const String _baseUrl = 'https://api.stripe.com/v1';

  // URLs de retorno (substituir por URLs reais em produção)
  static const String _successUrl = 'https://carrodasdelicias.com/success';
  static const String _cancelUrl = 'https://carrodasdelicias.com/cancel';

  /// Cria um Payment Intent no Stripe
  ///
  /// [amount] - Valor em centavos (ex: 1000 = R$ 10,00)
  /// [currency] - Moeda (padrão: BRL)
  /// [metadata] - Metadados customizados para o pagamento
  Future<Map<String, dynamic>?> createPaymentIntent({
    required int amount,
    String currency = 'brl',
    Map<String, String>? metadata,
  }) async {
    try {
      debugPrint('💳 Criando Payment Intent no Stripe...');
      debugPrint('💰 Valor: R\$ ${amount / 100}');

      final response = await http.post(
        Uri.parse('$_baseUrl/payment_intents'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'amount': amount.toString(),
          'currency': currency,
          'payment_method_types[]': 'card',
          if (metadata != null)
            ...metadata.map((key, value) => MapEntry('metadata[$key]', value)),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Payment Intent criado: ${data['id']}');
        return data;
      } else {
        debugPrint('❌ Erro ao criar Payment Intent: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar Payment Intent: $e');
      return null;
    }
  }

  /// Confirma o pagamento de um Payment Intent
  ///
  /// [paymentIntentId] - ID do Payment Intent
  /// [paymentMethodId] - ID do método de pagamento (cartão)
  Future<Map<String, dynamic>?> confirmPayment({
    required String paymentIntentId,
    required String paymentMethodId,
  }) async {
    try {
      debugPrint('🔒 Confirmando pagamento...');

      final response = await http.post(
        Uri.parse('$_baseUrl/payment_intents/$paymentIntentId/confirm'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'payment_method': paymentMethodId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Pagamento confirmado: ${data['status']}');
        return data;
      } else {
        debugPrint('❌ Erro ao confirmar pagamento: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao confirmar pagamento: $e');
      return null;
    }
  }

  /// Verifica o status de um Payment Intent
  ///
  /// [paymentIntentId] - ID do Payment Intent
  Future<String?> checkPaymentStatus(String paymentIntentId) async {
    try {
      debugPrint('🔍 Verificando status do pagamento...');

      final response = await http.get(
        Uri.parse('$_baseUrl/payment_intents/$paymentIntentId'),
        headers: {'Authorization': 'Bearer $_secretKey'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String;
        debugPrint('📊 Status do pagamento: $status');
        return status;
      } else {
        debugPrint('❌ Erro ao verificar status: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao verificar status: $e');
      return null;
    }
  }

  /// Converte valor em Reais para centavos
  ///
  /// [valor] - Valor em reais (ex: 10.50)
  /// Retorna o valor em centavos (ex: 1050)
  static int formatRealToCentavos(double valor) {
    return (valor * 100).round();
  }

  /// Cancela um Payment Intent
  Future<bool> cancelPaymentIntent(String paymentIntentId) async {
    try {
      debugPrint('🚫 Cancelando Payment Intent...');

      final response = await http.post(
        Uri.parse('$_baseUrl/payment_intents/$paymentIntentId/cancel'),
        headers: {'Authorization': 'Bearer $_secretKey'},
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Payment Intent cancelado');
        return true;
      } else {
        debugPrint('❌ Erro ao cancelar: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao cancelar: $e');
      return false;
    }
  }

  /// Criar sessão de checkout Stripe (para uso em WebView)
  ///
  /// [amount] - Valor em reais (será convertido para centavos)
  /// [description] - Descrição do produto/pedido
  /// [customerEmail] - Email do cliente
  /// [metadata] - Metadados customizados
  Future<Map<String, dynamic>> createCheckoutSession({
    required double amount,
    required String description,
    required String customerEmail,
    Map<String, String>? metadata,
  }) async {
    try {
      final amountInCents = (amount * 100).round();

      debugPrint('💳 Criando Checkout Session no Stripe...');
      debugPrint('💰 Valor: R\$ ${amount.toStringAsFixed(2)}');

      final body = <String, String>{
        'payment_method_types[0]': 'card',
        'line_items[0][price_data][currency]': 'brl',
        'line_items[0][price_data][product_data][name]': description,
        'line_items[0][price_data][unit_amount]': amountInCents.toString(),
        'line_items[0][quantity]': '1',
        'mode': 'payment',
        'success_url': _successUrl,
        'cancel_url': _cancelUrl,
        'customer_email': customerEmail,
      };

      // Adicionar metadata se fornecido
      if (metadata != null) {
        metadata.forEach((key, value) {
          body['metadata[$key]'] = value;
        });
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/checkout/sessions'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Checkout Session criada: ${data['id']}');

        return {'success': true, 'session_id': data['id'], 'url': data['url']};
      } else {
        debugPrint('❌ Erro ao criar Checkout Session: ${response.body}');
        return {
          'success': false,
          'message': 'Erro ao criar sessão de pagamento',
        };
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar Checkout Session: $e');
      return {'success': false, 'message': 'Erro ao conectar com servidor'};
    }
  }

  /// Verificar status da sessão de checkout
  ///
  /// [sessionId] - ID da sessão retornado ao criar checkout
  Future<Map<String, dynamic>> checkSessionStatus(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/checkout/sessions/$sessionId'),
        headers: {'Authorization': 'Bearer $_secretKey'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return {
          'status':
              data['payment_status'], // 'paid', 'unpaid', 'no_payment_required'
          'payment_intent': data['payment_intent'],
        };
      } else {
        debugPrint('❌ Erro ao verificar status: ${response.body}');
        return {'status': 'error'};
      }
    } catch (e) {
      debugPrint('❌ Exceção ao verificar status: $e');
      return {'status': 'error'};
    }
  }
}

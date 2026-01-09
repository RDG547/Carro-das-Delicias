import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Serviço para integração com o Stripe para pagamentos com cartão
class StripeService {
  // IMPORTANTE: Nunca commitar chaves de produção!
  // Configure as chaves em um arquivo .env ou nas variáveis de ambiente
  // Estas são chaves de exemplo - substitua pelas suas chaves reais localmente
  // ignore: unused_field
  static const String _publishableKey = 'pk_live_INSIRA_SUA_CHAVE_PUBLICAVEL_AQUI';
  static const String _secretKey = 'sk_live_INSIRA_SUA_CHAVE_SECRETA_AQUI';
  static const String _baseUrl = 'https://api.stripe.com/v1';

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

  /// Cria uma Checkout Session para pagamento hospedado
  ///
  /// Esta é a forma mais simples de integração, onde o Stripe cuida
  /// de toda a interface de pagamento
  Future<Map<String, dynamic>?> createCheckoutSession({
    required int amount,
    required String customerEmail,
    required String successUrl,
    required String cancelUrl,
    Map<String, String>? metadata,
  }) async {
    try {
      debugPrint('🛒 Criando Checkout Session...');

      final response = await http.post(
        Uri.parse('$_baseUrl/checkout/sessions'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'payment_method_types[]': 'card',
          'line_items[0][price_data][currency]': 'brl',
          'line_items[0][price_data][product_data][name]':
              'Pedido Carro das Delícias',
          'line_items[0][price_data][unit_amount]': amount.toString(),
          'line_items[0][quantity]': '1',
          'mode': 'payment',
          'success_url': successUrl,
          'cancel_url': cancelUrl,
          'customer_email': customerEmail,
          if (metadata != null)
            ...metadata.map((key, value) => MapEntry('metadata[$key]', value)),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Checkout Session criada: ${data['id']}');
        debugPrint('🔗 URL: ${data['url']}');
        return data;
      } else {
        debugPrint('❌ Erro ao criar Checkout Session: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Exceção ao criar Checkout Session: $e');
      return null;
    }
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
}

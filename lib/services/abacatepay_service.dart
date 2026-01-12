import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço para integração com o gateway de pagamento AbacatePay
class AbacatePayService {
  static const String _baseUrl = 'https://api.abacatepay.com/v1';
  static const String _apiKey = String.fromEnvironment(
    'ABACATEPAY_API_KEY',
    defaultValue: '',
  );

  /// Criar QR Code PIX para pagamento
  ///
  /// [amount] - Valor em centavos (ex: 1000 = R$ 10,00)
  /// [description] - Descrição da cobrança
  /// [expiresIn] - Tempo de expiração em segundos (padrão: 3600 = 1 hora)
  /// [customerName] - Nome do cliente
  /// [customerCellphone] - Telefone do cliente
  /// [customerEmail] - Email do cliente
  /// [customerTaxId] - CPF/CNPJ do cliente
  /// [metadata] - Dados adicionais (ex: pedidoId)
  Future<Map<String, dynamic>?> createPixQrCode({
    required int amount,
    required String description,
    int expiresIn = 3600,
    String? customerName,
    String? customerCellphone,
    String? customerEmail,
    String? customerTaxId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final body = <String, dynamic>{
        'amount': amount,
        'expiresIn': expiresIn,
        'description': description,
      };

      // Adicionar dados do cliente se fornecidos
      if (customerName != null &&
          customerCellphone != null &&
          customerEmail != null &&
          customerTaxId != null) {
        body['customer'] = {
          'name': customerName,
          'cellphone': customerCellphone,
          'email': customerEmail,
          'taxId': customerTaxId,
        };
      }

      // Adicionar metadata se fornecidos
      if (metadata != null) {
        body['metadata'] = metadata;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/pixQrCode/create'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['data'];
      } else {
        debugPrint('Erro ao criar PIX QR Code: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Erro ao criar PIX QR Code: $e');
      return null;
    }
  }

  /// Criar cobrança com suporte a múltiplos métodos (PIX e/ou CARD)
  ///
  /// [products] - Lista de produtos com nome, quantidade e preço
  /// [methods] - Métodos de pagamento aceitos (ex: ["PIX", "CARD"])
  /// [customerName] - Nome do cliente
  /// [customerCellphone] - Telefone do cliente
  /// [customerEmail] - Email do cliente
  /// [customerTaxId] - CPF/CNPJ do cliente
  /// [returnUrl] - URL para voltar caso cliente cancele
  /// [completionUrl] - URL para redirecionar após pagamento
  /// [metadata] - Dados adicionais (ex: pedidoId)
  ///
  /// Retorna um Map com 'id', 'url' (para checkout), 'status', etc.
  Future<Map<String, dynamic>?> createBilling({
    required List<Map<String, dynamic>> products,
    required List<String> methods,
    String? customerName,
    String? customerCellphone,
    String? customerEmail,
    String? customerTaxId,
    String? returnUrl,
    String? completionUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final body = <String, dynamic>{
        'frequency': 'ONE_TIME',
        'methods': methods,
        'products': products,
      };

      // Adicionar dados do cliente se fornecidos
      if (customerName != null &&
          customerCellphone != null &&
          customerEmail != null &&
          customerTaxId != null) {
        body['customer'] = {
          'name': customerName,
          'cellphone': customerCellphone,
          'email': customerEmail,
          'taxId': customerTaxId,
        };
      }

      // Adicionar URLs de retorno e conclusão
      if (returnUrl != null) {
        body['returnUrl'] = returnUrl;
      }
      if (completionUrl != null) {
        body['completionUrl'] = completionUrl;
      }

      // Adicionar metadata se fornecidos
      if (metadata != null) {
        body['metadata'] = metadata;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/billing/create'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['data'];
      } else {
        debugPrint('Erro ao criar billing: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Erro ao criar billing: $e');
      return null;
    }
  }

  ///
  /// [pixId] - ID do PIX retornado ao criar o QR Code
  Future<Map<String, dynamic>?> checkPixStatus(String pixId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pixQrCode/check?id=$pixId'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'];
      } else {
        debugPrint('Erro ao verificar status do PIX: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Erro ao verificar status do PIX: $e');
      return null;
    }
  }

  /// Simular pagamento (apenas modo DEV)
  ///
  /// [pixId] - ID do QR Code PIX
  Future<bool> simulatePayment(String pixId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/pixQrCode/simulate-payment?id=$pixId'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({'metadata': {}}),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Pagamento simulado com sucesso');
        return true;
      } else {
        debugPrint('Erro ao simular pagamento: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Erro ao simular pagamento: $e');
      return false;
    }
  }

  /// Criar cobrança PIX simplificada
  ///
  /// [amount] - Valor em reais (será convertido para centavos)
  /// [description] - Descrição da cobrança
  /// [externalReference] - Referência externa (ex: pedidoId)
  Future<Map<String, dynamic>> createPixCharge({
    required double amount,
    required String description,
    String? externalReference,
  }) async {
    try {
      final amountInCents = formatRealToCentavos(amount);

      final body = <String, dynamic>{
        'amount': amountInCents,
        'description': description,
        'expiresIn': 3600, // 1 hora
      };

      if (externalReference != null) {
        body['metadata'] = {'externalReference': externalReference};
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/pixQrCode/create'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      debugPrint('📡 Resposta AbacatePay:');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        debugPrint('Data decodificado: $data');

        final pixData = data['data'];
        debugPrint('PixData: $pixData');

        return {
          'success': true,
          'id': pixData['id'],
          'qr_code_url': pixData['brCodeBase64'],
          'pix_code': pixData['brCode'],
          'expires_at': pixData['expiresAt'],
        };
      } else {
        debugPrint('Erro ao criar PIX: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return {'success': false, 'message': 'Erro ao gerar código PIX'};
      }
    } catch (e) {
      debugPrint('Erro ao criar PIX: $e');
      return {'success': false, 'message': 'Erro ao conectar com servidor'};
    }
  }

  /// Verificar status do pagamento
  ///
  /// [chargeId] - ID da cobrança retornado ao criar o PIX
  Future<Map<String, dynamic>> checkPaymentStatus(String chargeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/pixQrCode/check?id=$chargeId'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pixData = data['data'];

        return {
          'status': pixData['status'], // PENDING, PAID, EXPIRED, CANCELLED
          'paid_at': pixData['paidAt'],
        };
      } else {
        debugPrint('Erro ao verificar status: ${response.statusCode}');
        return {'status': 'ERROR'};
      }
    } catch (e) {
      debugPrint('Erro ao verificar status: $e');
      return {'status': 'ERROR'};
    }
  }

  /// Formatar valor de centavos para real
  static String formatCentavosToReal(int centavos) {
    final reais = centavos / 100;
    return 'R\$ ${reais.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Formatar valor de real para centavos
  static int formatRealToCentavos(double reais) {
    return (reais * 100).round();
  }
}

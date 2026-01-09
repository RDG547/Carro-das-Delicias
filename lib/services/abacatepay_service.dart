import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço para integração com o gateway de pagamento AbacatePay
class AbacatePayService {
  static const String _baseUrl = 'https://api.abacatepay.com/v1';
  // IMPORTANTE: Nunca commitar chaves de produção!
  // Configure a chave em um arquivo .env ou nas variáveis de ambiente
  // Esta é uma chave de exemplo - substitua pela sua chave real localmente
  static const String _apiKey = 'abc_prod_INSIRA_SUA_CHAVE_AQUI';

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

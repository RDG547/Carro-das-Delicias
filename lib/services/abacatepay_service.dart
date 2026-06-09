import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../config/env_config.dart';

/// Serviço para integração com o gateway de pagamento AbacatePay.
///
/// A API v2 usa o envelope `{data, error, success}` em todas as respostas.
/// Este serviço mantém o formato que as telas já consomem, mas envia os
/// contratos novos da v2 para a AbacatePay.
class AbacatePayService {
  static const String _baseUrl = 'https://api.abacatepay.com/v2';

  static String get _apiKey {
    final dotenvValue = dotenv.env['ABACATEPAY_API_KEY'];
    if (dotenvValue != null && dotenvValue.isNotEmpty) {
      return dotenvValue;
    }
    return EnvConfig.get('ABACATEPAY_API_KEY');
  }

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
  };

  /// Criar QR Code PIX para pagamento via Checkout Transparente v2.
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
    final chargeData = <String, dynamic>{
      'amount': amount,
      'expiresIn': expiresIn,
      'description': description,
    };

    final customer = _customerPayload(
      name: customerName,
      cellphone: customerCellphone,
      email: customerEmail,
      taxId: customerTaxId,
    );
    if (customer.isNotEmpty) {
      chargeData['customer'] = customer;
    }

    if (metadata != null && metadata.isNotEmpty) {
      chargeData['metadata'] = metadata;
    }

    return _createTransparentPix(chargeData);
  }

  /// Criar checkout hospedado v2.
  ///
  /// Na v2, os produtos precisam existir antes do checkout. Envie em [products]
  /// mapas com `id` (ID do produto na AbacatePay) e `quantity`.
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
      final items = <Map<String, dynamic>>[];
      for (final product in products) {
        final item = _checkoutItemFromProduct(product);
        if (item == null) {
          debugPrint(
            'AbacatePay checkout v2 exige products com id/productId e quantity.',
          );
          return null;
        }
        items.add(item);
      }

      final body = <String, dynamic>{
        'items': items,
        if (methods.isNotEmpty)
          'methods': methods.map(_normalizeMethod).toList(),
      };

      if (customerEmail != null && customerEmail.trim().isNotEmpty) {
        final customer = await createCustomer(
          email: customerEmail,
          name: customerName,
          cellphone: customerCellphone,
          taxId: customerTaxId,
        );
        final customerId = customer?['id']?.toString();
        if (customerId != null && customerId.isNotEmpty) {
          body['customerId'] = customerId;
        }
      }

      if (returnUrl != null && returnUrl.isNotEmpty) {
        body['returnUrl'] = returnUrl;
      }
      if (completionUrl != null && completionUrl.isNotEmpty) {
        body['completionUrl'] = completionUrl;
      }
      if (metadata != null && metadata.isNotEmpty) {
        body['metadata'] = metadata;
        final externalId = metadata['externalId'] ?? metadata['pedidoId'];
        if (externalId != null) {
          body['externalId'] = externalId.toString();
        }
      }

      return _post('/checkouts/create', body, operation: 'Criar checkout');
    } catch (e) {
      debugPrint('Erro ao criar checkout AbacatePay: $e');
      return null;
    }
  }

  /// Cadastra ou recupera um cliente para pré-preencher checkouts hospedados.
  Future<Map<String, dynamic>?> createCustomer({
    required String email,
    String? name,
    String? cellphone,
    String? taxId,
    String? zipCode,
    Map<String, dynamic>? metadata,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      if (name != null && name.trim().isNotEmpty) 'name': name,
      if (cellphone != null && cellphone.trim().isNotEmpty)
        'cellphone': cellphone,
      if (taxId != null && taxId.trim().isNotEmpty) 'taxId': taxId,
      if (zipCode != null && zipCode.trim().isNotEmpty) 'zipCode': zipCode,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };

    return _post('/customers/create', body, operation: 'Criar cliente');
  }

  /// Cria um produto avulso ou recorrente para uso em checkouts hospedados.
  Future<Map<String, dynamic>?> createProduct({
    required String externalId,
    required String name,
    required int priceInCents,
    String currency = 'BRL',
    String? description,
    String? imageUrl,
    String? cycle,
  }) async {
    final body = <String, dynamic>{
      'externalId': externalId,
      'name': name,
      'price': priceInCents,
      'currency': currency,
      if (description != null && description.trim().isNotEmpty)
        'description': description,
      if (imageUrl != null && imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl,
      if (cycle != null && cycle.trim().isNotEmpty) 'cycle': cycle,
    };

    return _post('/products/create', body, operation: 'Criar produto');
  }

  ///
  /// [pixId] - ID do Checkout Transparente retornado ao criar o QR Code.
  Future<Map<String, dynamic>?> checkPixStatus(String pixId) async {
    return _get(
      '/transparents/check',
      queryParameters: {'id': pixId},
      operation: 'Verificar status do PIX',
    );
  }

  /// Simular pagamento (apenas modo DEV).
  ///
  /// [pixId] - ID do Checkout Transparente PIX.
  Future<bool> simulatePayment(String pixId) async {
    final data = await _post(
      '/transparents/simulate-payment',
      {'metadata': <String, dynamic>{}},
      queryParameters: {'id': pixId},
      operation: 'Simular pagamento',
    );
    return data != null;
  }

  /// Criar cobrança PIX simplificada.
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

      final chargeData = <String, dynamic>{
        'amount': amountInCents,
        'description': description,
        'expiresIn': 3600,
      };

      if (externalReference != null && externalReference.isNotEmpty) {
        chargeData['externalId'] = externalReference;
        chargeData['metadata'] = {
          'pedidoId': externalReference,
          'externalReference': externalReference,
        };
      }

      final pixData = await _createTransparentPix(chargeData);
      if (pixData == null) {
        return {'success': false, 'message': 'Erro ao gerar código PIX'};
      }

      return {
        'success': true,
        'id': pixData['id'],
        'qr_code_url': pixData['brCodeBase64'],
        'pix_code': pixData['brCode'],
        'expires_at': pixData['expiresAt'],
        'status': pixData['status'],
        'receipt_url': pixData['receiptUrl'],
        'raw': pixData,
      };
    } catch (e) {
      debugPrint('Erro ao criar PIX: $e');
      return {'success': false, 'message': 'Erro ao conectar com servidor'};
    }
  }

  /// Verificar status do pagamento.
  ///
  /// [chargeId] - ID da cobrança retornado ao criar o PIX.
  Future<Map<String, dynamic>> checkPaymentStatus(String chargeId) async {
    try {
      final pixData = await checkPixStatus(chargeId);
      if (pixData == null) {
        return {'status': 'ERROR'};
      }

      return {
        'status': pixData['status'],
        'paid_at': pixData['paidAt'],
        'expires_at': pixData['expiresAt'],
      };
    } catch (e) {
      debugPrint('Erro ao verificar status: $e');
      return {'status': 'ERROR'};
    }
  }

  /// Formatar valor de centavos para real.
  static String formatCentavosToReal(int centavos) {
    final reais = centavos / 100;
    return 'R\$ ${reais.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Formatar valor de real para centavos.
  static int formatRealToCentavos(double reais) {
    return (reais * 100).round();
  }

  Future<Map<String, dynamic>?> _createTransparentPix(
    Map<String, dynamic> data,
  ) {
    return _post('/transparents/create', {
      'method': 'PIX',
      'data': data,
    }, operation: 'Criar PIX');
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParameters,
    required String operation,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('ABACATEPAY_API_KEY não configurada.');
      return null;
    }

    try {
      final response = await http.post(
        _uri(path, queryParameters: queryParameters),
        headers: _headers,
        body: json.encode(body),
      );

      return _parseResponseData(response, operation);
    } catch (e) {
      debugPrint('$operation falhou: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, String>? queryParameters,
    required String operation,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('ABACATEPAY_API_KEY não configurada.');
      return null;
    }

    try {
      final response = await http.get(
        _uri(path, queryParameters: queryParameters),
        headers: _headers,
      );

      return _parseResponseData(response, operation);
    } catch (e) {
      debugPrint('$operation falhou: $e');
      return null;
    }
  }

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final uri = Uri.parse('$_baseUrl$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: queryParameters);
  }

  Map<String, dynamic>? _parseResponseData(
    http.Response response,
    String operation,
  ) {
    final statusCode = response.statusCode;
    Map<String, dynamic>? decoded;

    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        decoded = body;
      } else if (body is Map) {
        decoded = body.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      debugPrint('$operation retornou JSON inválido. Status: $statusCode.');
      return null;
    }

    if (decoded == null) {
      debugPrint(
        '$operation retornou resposta inesperada. Status: $statusCode.',
      );
      return null;
    }

    final success = decoded['success'];
    if (statusCode < 200 || statusCode >= 300 || success == false) {
      debugPrint(
        '$operation falhou. Status: $statusCode. '
        'Erro: ${_errorMessage(decoded['error'])}',
      );
      return null;
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  Map<String, dynamic> _customerPayload({
    String? name,
    String? cellphone,
    String? email,
    String? taxId,
  }) {
    return {
      if (name != null && name.trim().isNotEmpty) 'name': name,
      if (cellphone != null && cellphone.trim().isNotEmpty)
        'cellphone': cellphone,
      if (email != null && email.trim().isNotEmpty) 'email': email,
      if (taxId != null && taxId.trim().isNotEmpty) 'taxId': taxId,
    };
  }

  Map<String, dynamic>? _checkoutItemFromProduct(Map<String, dynamic> product) {
    final id = product['id'] ?? product['productId'];
    if (id == null || id.toString().isEmpty) {
      return null;
    }

    final quantity = _parseQuantity(
      product['quantity'] ?? product['quantidade'],
    );
    return {'id': id.toString(), 'quantity': quantity};
  }

  int _parseQuantity(dynamic value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed > 0) return parsed;
    return 1;
  }

  String _normalizeMethod(String method) {
    final normalized = method.trim().toUpperCase();
    if (normalized == 'CREDIT' || normalized == 'CREDITO') {
      return 'CARD';
    }
    return normalized;
  }

  String _errorMessage(dynamic error) {
    if (error == null) return 'sem detalhes';
    if (error is String && error.trim().isNotEmpty) return error;
    if (error is Map) {
      final message = error['message'] ?? error['error'] ?? error['detail'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return error.toString();
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'abacatepay_service.dart';
import 'notification_service.dart';
import 'stripe_service.dart';

class OrderPaymentService {
  static const String statusPagamentoPendente = 'pagamento_pendente';
  static const String statusPendente = 'pendente';
  static const String statusPago = 'pago';
  static const String statusCancelado = 'cancelado';

  static const String paymentStatusPending = 'pending';
  static const String paymentStatusUnpaid = 'unpaid';
  static const String paymentStatusPaid = 'paid';
  static const String paymentStatusExpired = 'expired';
  static const String paymentStatusCancelled = 'cancelled';

  static const String providerPix = 'abacatepay';
  static const String providerCard = 'stripe';

  // Cache para evitar chamadas repetidas de syncPaymentStatus
  static final Map<dynamic, DateTime> _lastSyncTime = {};
  static const Duration _minSyncInterval = Duration(seconds: 30);

  static SupabaseClient get _supabase => Supabase.instance.client;

  static bool requiresOnlinePayment(String? method) {
    return method == 'pix' || method == 'credito';
  }

  /// Verifica se há conexão de rede disponível
  static Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool canResumePayment(Map<String, dynamic> pedido) {
    final status = pedido['status']?.toString().toLowerCase();
    final method = pedido['metodo_pagamento']?.toString().toLowerCase();
    final paymentStatus = pedido['payment_status']?.toString().toLowerCase();
    return status == statusPagamentoPendente &&
        requiresOnlinePayment(method) &&
        paymentStatus != paymentStatusCancelled;
  }

  static String resolvedPaymentStatus(Map<String, dynamic> pedido) {
    final paymentStatus =
        pedido['payment_status']?.toString().toLowerCase().trim() ?? '';
    if (paymentStatus.isNotEmpty) {
      return paymentStatus;
    }

    final status = pedido['status']?.toString().toLowerCase().trim() ?? '';
    if (status == statusPago) {
      return paymentStatusPaid;
    }
    if (status == statusPagamentoPendente) {
      return paymentStatusPending;
    }
    if (status == statusCancelado) {
      return paymentStatusCancelled;
    }
    return '';
  }

  static Map<String, dynamic> parsePaymentPayload(dynamic rawPayload) {
    if (rawPayload is Map<String, dynamic>) {
      return rawPayload;
    }
    if (rawPayload is Map) {
      return rawPayload.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> createOrderWithItems({
    required Map<String, dynamic> pedidoData,
    required List<Map<String, dynamic>> itens,
  }) async {
    final response = await _supabase
        .from('pedidos')
        .insert(pedidoData)
        .select()
        .single();

    final pedidoId = response['id'];
    if (itens.isNotEmpty) {
      final itensComPedido = itens
          .map((item) => {...item, 'pedido_id': pedidoId})
          .toList();
      await _supabase.from('pedido_itens').insert(itensComPedido);
    }

    return Map<String, dynamic>.from(response);
  }

  static Future<Map<String, dynamic>?> fetchOrderById(dynamic pedidoId) async {
    try {
      final response = await _supabase
          .from('pedidos')
          .select('*')
          .eq('id', pedidoId)
          .maybeSingle();
      if (response == null) return null;
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('Erro ao buscar pedido $pedidoId: $error');
      return null;
    }
  }

  static Future<void> savePendingPayment({
    required dynamic pedidoId,
    required String paymentProvider,
    String? paymentReference,
    String? paymentUrl,
    Map<String, dynamic>? paymentPayload,
    DateTime? paymentExpiresAt,
    String paymentStatus = paymentStatusPending,
  }) async {
    final updateData = <String, dynamic>{
      'status': statusPagamentoPendente,
      'payment_status': paymentStatus,
      'payment_provider': paymentProvider,
      'payment_reference': paymentReference,
      'payment_url': paymentUrl,
      'payment_payload': paymentPayload ?? <String, dynamic>{},
      'payment_expires_at': paymentExpiresAt?.toIso8601String(),
      'payment_confirmed_at': null,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _supabase.from('pedidos').update(updateData).eq('id', pedidoId);
  }

  static Future<void> markPaymentState({
    required dynamic pedidoId,
    required String paymentStatus,
  }) async {
    final updateData = <String, dynamic>{
      'payment_status': paymentStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (paymentStatus == paymentStatusCancelled) {
      updateData['status'] = statusCancelado;
    } else {
      updateData['status'] = statusPagamentoPendente;
    }

    await _supabase.from('pedidos').update(updateData).eq('id', pedidoId);
  }

  static Future<void> markOrderAsPaid(dynamic pedidoId) async {
    final pedido = await fetchOrderById(pedidoId);
    if (pedido == null) return;

    final currentStatus = pedido['status']?.toString().toLowerCase();
    final currentPaymentStatus = resolvedPaymentStatus(pedido);
    if (currentStatus == statusPago &&
        currentPaymentStatus == paymentStatusPaid) {
      return;
    }

    await _supabase
        .from('pedidos')
        .update({
          'status': statusPago,
          'payment_status': paymentStatusPaid,
          'payment_confirmed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', pedidoId);

    final orderIdInt = _parseOrderId(pedido['id']);
    final total = (pedido['total'] as num?)?.toDouble();
    final customerName = pedido['cliente_nome']?.toString().trim();

    if (orderIdInt != null && total != null && customerName != null) {
      try {
        await NotificationService.notifyAdminsNewOrder(
          orderId: orderIdInt,
          customerName: customerName.isEmpty ? 'Cliente' : customerName,
          total: total,
        );
      } catch (error) {
        debugPrint(
          'Erro ao notificar admins sobre pagamento confirmado: $error',
        );
      }
    }
  }

  static Future<Map<String, dynamic>?> syncPaymentStatus(
    Map<String, dynamic> pedido, {
    bool force = false,
  }) async {
    if (!canResumePayment(pedido)) {
      return pedido;
    }

    final orderId = pedido['id'];

    // Evitar chamadas repetidas dentro do intervalo mínimo
    if (!force) {
      final lastSync = _lastSyncTime[orderId];
      if (lastSync != null &&
          DateTime.now().difference(lastSync) < _minSyncInterval) {
        return pedido;
      }
    }

    // Verificar conectividade antes de chamar APIs externas
    if (!await _hasNetworkConnectivity()) {
      return pedido;
    }

    _lastSyncTime[orderId] = DateTime.now();

    final method = pedido['metodo_pagamento']?.toString().toLowerCase();
    final paymentReference = pedido['payment_reference']?.toString();
    if (paymentReference == null || paymentReference.isEmpty) {
      return pedido;
    }

    try {
      if (method == 'pix') {
        final status = await AbacatePayService().checkPaymentStatus(
          paymentReference,
        );
        final normalizedStatus = status['status']?.toString().toUpperCase();

        if (normalizedStatus == 'PAID' || normalizedStatus == 'CONFIRMED') {
          await markOrderAsPaid(pedido['id']);
        } else if (normalizedStatus == 'EXPIRED') {
          await markPaymentState(
            pedidoId: pedido['id'],
            paymentStatus: paymentStatusExpired,
          );
        } else if (normalizedStatus == 'CANCELLED') {
          await markPaymentState(
            pedidoId: pedido['id'],
            paymentStatus: paymentStatusCancelled,
          );
        }
      } else if (method == 'credito') {
        final status = await StripeService().checkSessionStatus(
          paymentReference,
        );
        final normalizedStatus = status['status']?.toString().toLowerCase();

        if (normalizedStatus == paymentStatusPaid) {
          await markOrderAsPaid(pedido['id']);
        } else if (normalizedStatus == paymentStatusUnpaid) {
          // Verificar status atual no banco antes de sobrescrever
          final freshOrder = await fetchOrderById(pedido['id']);
          final freshStatus = freshOrder?['status']?.toString().toLowerCase();
          if (freshStatus == statusCancelado || freshStatus == 'rejeitado') {
            return freshOrder;
          }
          await savePendingPayment(
            pedidoId: pedido['id'],
            paymentProvider: providerCard,
            paymentReference: paymentReference,
            paymentUrl: pedido['payment_url']?.toString(),
            paymentPayload: parsePaymentPayload(pedido['payment_payload']),
            paymentExpiresAt: _parseDateTime(pedido['payment_expires_at']),
            paymentStatus: paymentStatusUnpaid,
          );
        }
      }

      return fetchOrderById(pedido['id']);
    } catch (error) {
      debugPrint(
        'Erro ao sincronizar pagamento do pedido ${pedido['id']}: $error',
      );
      return pedido;
    }
  }

  static Future<void> syncPendingPaymentsForCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('pedidos')
          .select(
            'id, status, metodo_pagamento, payment_status, payment_reference, payment_url, payment_payload, payment_expires_at',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(15);

      final pedidos = List<Map<String, dynamic>>.from(response);
      for (final pedido in pedidos) {
        if (canResumePayment(pedido)) {
          await syncPaymentStatus(pedido);
        }
      }
    } catch (error) {
      debugPrint('Erro ao sincronizar pagamentos pendentes do usuario: $error');
    }
  }

  static int? _parseOrderId(dynamic value) {
    if (value is int) return value;
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

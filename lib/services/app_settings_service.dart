import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CashPaymentAvailability { allUsers, minimumCompletedOrders }

class CashPaymentSettings {
  final CashPaymentAvailability availability;
  final int minimumCompletedOrders;

  const CashPaymentSettings({
    required this.availability,
    this.minimumCompletedOrders = 5,
  });

  const CashPaymentSettings.defaults()
    : availability = CashPaymentAvailability.minimumCompletedOrders,
      minimumCompletedOrders = 5;

  bool get enabledForAllUsers =>
      availability == CashPaymentAvailability.allUsers;

  bool canUse({required bool isGuest, required int completedOrders}) {
    if (isGuest) return false;
    if (enabledForAllUsers) return true;
    return completedOrders >= minimumCompletedOrders;
  }

  String get modeStorageValue =>
      enabledForAllUsers ? 'all_users' : 'minimum_completed_orders';

  Map<String, dynamic> toStorage() => {
    'mode': modeStorageValue,
    'minimum_completed_orders': minimumCompletedOrders,
  };

  factory CashPaymentSettings.fromStorage(dynamic storage) {
    if (storage is! Map) {
      return const CashPaymentSettings.defaults();
    }

    final storageMap = Map<String, dynamic>.from(storage);
    final rawMode = storageMap['mode']?.toString();
    final rawMinimum = storageMap['minimum_completed_orders'];
    final minimumCompletedOrders = rawMinimum is num
        ? rawMinimum.toInt()
        : int.tryParse(rawMinimum?.toString() ?? '') ?? 5;

    return CashPaymentSettings(
      availability: rawMode == 'all_users'
          ? CashPaymentAvailability.allUsers
          : CashPaymentAvailability.minimumCompletedOrders,
      minimumCompletedOrders: minimumCompletedOrders < 1
          ? 5
          : minimumCompletedOrders,
    );
  }
}

class AppSettingsService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _tableName = 'app_settings';
  static const String _cashPaymentKey = 'cash_payment';

  static Future<CashPaymentSettings> getCashPaymentSettings() async {
    try {
      final response = await _supabase
          .from(_tableName)
          .select('value')
          .eq('key', _cashPaymentKey)
          .maybeSingle();

      return CashPaymentSettings.fromStorage(response?['value']);
    } catch (error) {
      debugPrint(
        'Erro ao carregar configuração de pagamento em dinheiro: $error',
      );
      return const CashPaymentSettings.defaults();
    }
  }

  static Future<void> saveCashPaymentSettings(
    CashPaymentSettings settings,
  ) async {
    await _supabase.from(_tableName).upsert({
      'key': _cashPaymentKey,
      'value': settings.toStorage(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
  }
}

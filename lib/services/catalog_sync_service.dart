import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';

class CatalogSyncService extends ChangeNotifier with WidgetsBindingObserver {
  CatalogSyncService._();

  static final CatalogSyncService instance = CatalogSyncService._();

  int _revision = 0;
  bool _started = false;
  int _generation = 0;
  int _retryCount = 0;
  RealtimeChannel? _channel;
  Timer? _retry;
  Timer? _debounce;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _retry?.cancel();
    final client = Supabase.instance.client;
    final old = _channel;
    _channel = null;
    if (old != null) await client.removeChannel(old);
    if (!_started || generation != _generation) return;
    var channel = client.channel('shared-catalog');
    for (final table in ['produtos', 'categorias', 'app_settings']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          if (table == 'app_settings') {
            unawaited(AppSettingsService.loadCatalogVisibility());
          }
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(milliseconds: 150),
            notifyCatalogChanged,
          );
        },
      );
    }
    _channel = channel.subscribe((status, error) {
      if (!_started || generation != _generation) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        _retryCount = 0;
        debugPrint('Catálogo conectado ao tempo real');
        unawaited(AppSettingsService.loadCatalogVisibility());
        notifyCatalogChanged();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _retry?.cancel();
        final delay = (2 << _retryCount.clamp(0, 4)).clamp(2, 30);
        _retryCount++;
        _retry = Timer(Duration(seconds: delay), () => unawaited(_connect()));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_connect());
  }

  int get revision => _revision;

  void notifyCatalogChanged() {
    _revision++;
    notifyListeners();
  }
}

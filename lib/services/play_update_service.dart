import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PlayUpdateClient {
  Future<Map<String, dynamic>> installation();
  Future<Map<String, dynamic>> check();
  Future<bool> update();
  Future<void> openStore();
}

class NativePlayUpdateClient implements PlayUpdateClient {
  static const _channel = MethodChannel('com.rdtech.carrodasdelicias/updates');

  @override
  Future<Map<String, dynamic>> installation() async =>
      await _channel.invokeMapMethod<String, dynamic>('getInstallation') ?? {};
  @override
  Future<Map<String, dynamic>> check() async =>
      await _channel.invokeMapMethod<String, dynamic>('checkForUpdate') ?? {};
  @override
  Future<bool> update() async =>
      await _channel.invokeMethod<bool>('startImmediateUpdate') ?? false;
  @override
  Future<void> openStore() => _channel.invokeMethod<void>('openStore');
}

/// Persists only an offer confirmed by Play for this user, never a global version.
class PlayUpdateService extends ChangeNotifier with WidgetsBindingObserver {
  PlayUpdateService({PlayUpdateClient? client, bool? supported})
    : _client = client ?? NativePlayUpdateClient(),
      _supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const preferenceKey = 'play_confirmed_update_version';
  final PlayUpdateClient _client;
  final bool _supported;
  SharedPreferences? _preferences;
  Timer? _timer;
  Future<void>? _checking;
  bool _started = false;
  bool _disposed = false;
  bool _eligible = false;
  bool _immediateAllowed = false;
  bool _updating = false;
  bool _resumeAttempted = false;
  int _installed = 0;
  int _required = 0;
  String? _message;

  bool get updateRequired => _eligible && _required > _installed;
  bool get updating => _updating;
  String? get message => _message;

  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await check();
    if (_disposed) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(check());
      }
    });
  }

  Future<void> check() {
    if (_disposed || !_supported) return Future.value();
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    try {
      final installation = await _client.installation().timeout(
        const Duration(seconds: 6),
      );
      if (_disposed) return;
      _eligible = installation['playStore'] == true;
      _installed = (installation['versionCode'] as num?)?.toInt() ?? 0;
      _preferences ??= await SharedPreferences.getInstance();
      if (_disposed) return;
      _required = _preferences!.getInt(preferenceKey) ?? 0;
      if (!_eligible || _required <= _installed) {
        _required = 0;
        await _preferences!.remove(preferenceKey);
      }
      _notify();
      if (!_eligible || _disposed) return;

      final offer = await _client.check().timeout(const Duration(seconds: 8));
      if (_disposed) return;
      final availability = offer['availability'];
      final target = (offer['versionCode'] as num?)?.toInt() ?? 0;
      if ((availability == 2 || availability == 3) && target > _installed) {
        _required = target;
        _immediateAllowed =
            offer['immediateAllowed'] == true || availability == 3;
        await _preferences!.setInt(preferenceKey, target);
        _message = null;
        _notify();
        if (availability == 3 && !_updating && !_resumeAttempted) {
          _resumeAttempted = true;
          unawaited(update());
        }
      } else if (availability == 1) {
        // A withdrawn offer or completed installation must not trap the user.
        _required = 0;
        _message = null;
        await _preferences!.remove(preferenceKey);
        _notify();
      }
    } catch (_) {
      // Network/Play failures don't invent an update. A confirmed offer survives.
      if (updateRequired) {
        _message =
            'Conecte-se à internet para concluir a atualização pela Play Store.';
        _notify();
      }
    }
  }

  Future<void> update() async {
    if (_updating || !updateRequired || _disposed) return;
    _updating = true;
    _message = null;
    _notify();
    try {
      if (_immediateAllowed) {
        final accepted = await _client.update();
        if (!accepted)
          _message =
              'A atualização é necessária para continuar. Tente novamente ou abra a Play Store.';
      } else {
        await _client.openStore();
      }
    } catch (_) {
      _message =
          'Não foi possível iniciar a atualização. Tente pela Play Store.';
    } finally {
      _updating = false;
      _notify();
      // Let an obsolete/withdrawn offer release the gate after a failed attempt.
      if (!_disposed) unawaited(check());
    }
  }

  Future<void> openStore() async {
    try {
      await _client.openStore();
    } catch (_) {
      _message =
          'Não foi possível abrir a Play Store. Verifique sua conexão e tente novamente.';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_updating)
      _resumeAttempted = false;
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

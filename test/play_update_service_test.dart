import 'package:carrodasdelicias/services/play_update_service.dart';
import 'package:carrodasdelicias/widgets/mandatory_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlay extends PlayUpdateClient {
  int installed = 100;
  bool playStore = true;
  int availability = 2;
  bool fail = false;
  int updates = 0;
  int storeOpens = 0;
  bool allowed = true;
  @override
  Future<Map<String, dynamic>> installation() async => {
    'versionCode': installed,
    'playStore': playStore,
  };
  @override
  Future<Map<String, dynamic>> check() async {
    if (fail) throw Exception('offline');
    return {
      'availability': availability,
      'versionCode': 101,
      'immediateAllowed': allowed,
    };
  }

  @override
  Future<bool> update() async {
    updates++;
    return false;
  }

  @override
  Future<void> openStore() async {
    storeOpens++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'somente oferta para este usuário exige atualizar; cancelar mantém bloqueio',
    () async {
      final play = FakePlay();
      final service = PlayUpdateService(client: play, supported: true);
      await service.check();
      expect(service.updateRequired, isTrue);
      await service.update();
      expect(play.updates, 1);
      expect(service.updateRequired, isTrue);
      service.dispose();
    },
  );
  test(
    'oferta confirmada sobrevive a reinício offline; nova instalação libera',
    () async {
      final play = FakePlay();
      var service = PlayUpdateService(client: play, supported: true);
      await service.check();
      service.dispose();
      play.fail = true;
      service = PlayUpdateService(client: play, supported: true);
      await service.check();
      expect(service.updateRequired, isTrue);
      play.installed = 101;
      await service.check();
      expect(service.updateRequired, isFalse);
      service.dispose();
    },
  );
  test('rollout indisponível e oferta retirada permitem continuar', () async {
    final play = FakePlay()..availability = 1;
    final service = PlayUpdateService(client: play, supported: true);
    await service.check();
    expect(service.updateRequired, isFalse);
    play.availability = 2;
    await service.check();
    expect(service.updateRequired, isTrue);
    play.availability = 1;
    await service.check();
    expect(service.updateRequired, isFalse);
    service.dispose();
  });
  test('APK externo e falha de conexão sem oferta não bloqueiam', () async {
    final play = FakePlay()..playStore = false;
    var service = PlayUpdateService(client: play, supported: true);
    await service.check();
    expect(service.updateRequired, isFalse);
    service.dispose();
    play.playStore = true;
    play.fail = true;
    service = PlayUpdateService(client: play, supported: true);
    await service.check();
    expect(service.updateRequired, isFalse);
    service.dispose();
  });
  test(
    'sem fluxo imediato abre a loja; retomar atualização não cria loop',
    () async {
      final play = FakePlay()..allowed = false;
      final service = PlayUpdateService(client: play, supported: true);
      await service.check();
      await service.update();
      expect(play.storeOpens, 1);
      expect(service.updateRequired, isTrue);
      play.availability = 3;
      await service.check();
      await Future<void>.delayed(Duration.zero);
      expect(play.updates, 1);
      service.dispose();
    },
  );
  for (final size in [const Size(320, 480), const Size(844, 390)]) {
    testWidgets('modal obrigatório não fecha e respeita recuos em $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 30, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final play = FakePlay();
      final service = PlayUpdateService(client: play, supported: true);
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              MandatoryUpdateGate(service: service, child: child!),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Continuar'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsOneWidget);
      await tester.tapAt(const Offset(5, 100));
      await tester.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsOneWidget);
      await tester.ensureVisible(find.text('Atualizar agora'));
      await tester.tap(find.text('Atualizar agora'));
      await tester.pumpAndSettle();
      expect(service.updateRequired, isTrue);
      expect(taps, 0);
      expect(tester.takeException(), isNull);
      play.availability = 1;
      await service.check();
      await tester.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsNothing);
      await tester.tap(find.text('Continuar'));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }
}

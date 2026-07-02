import 'package:carrodasdelicias/services/delivery_geofence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconhece coordenada de Bangu dentro da area de entrega', () async {
    final service = DeliveryGeofenceService.instance;
    await service.inicializarAreas();

    final result = service.verificarCoordenada(-22.8930159, -43.4707557);

    expect(result.atende, isTrue);
    expect(result.areaName, contains('Bangu'));
  });
}

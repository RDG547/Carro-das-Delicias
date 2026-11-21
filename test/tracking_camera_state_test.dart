import 'package:carrodasdelicias/utils/tracking_camera_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  final first = Point(coordinates: Position(-43.2, -22.9));
  final next = Point(coordinates: Position(-43.201, -22.901));
  test('painel e atualização da Kombi não recriam o viewport inicial', () {
    final state = TrackingCameraState();
    final viewport = state.initialViewport(first);
    state.locationChanged(next);
    expect(identical(viewport, state.initialViewport(next)), isTrue);
  });
  test(
    'acompanhamento automático muda o centro sem redefinir zoom ou rotação',
    () {
      final state = TrackingCameraState();
      final camera = state.locationChanged(next)!;
      expect(camera.center, next);
      expect(camera.zoom, isNull);
      expect(camera.bearing, isNull);
      expect(camera.pitch, isNull);
    },
  );
  test(
    'gesto manual suspende o acompanhamento até recentralizar explicitamente',
    () {
      final state = TrackingCameraState();
      state.initialViewport(first);
      state.userGesture();
      expect(state.locationChanged(next), isNull);
      expect(state.initialViewport(next).center, first);
      final camera = state.recenter(next);
      expect(camera.zoom, TrackingCameraState.defaultZoom);
      expect(state.locationChanged(first)!.center, first);
      expect(state.locationChanged(first)!.zoom, isNull);
    },
  );
}

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Separa o acompanhamento da Kombi da exploração manual do mapa.
class TrackingCameraState {
  static const defaultZoom = 17.0;
  bool _following = true;
  CameraViewportState? _initialViewport;

  CameraViewportState initialViewport(Point location) => _initialViewport ??=
      CameraViewportState(center: location, zoom: defaultZoom);

  void userGesture() => _following = false;

  CameraOptions? locationChanged(Point location) =>
      _following ? CameraOptions(center: location) : null;

  CameraOptions recenter(Point location) {
    _following = true;
    return CameraOptions(
      center: location,
      zoom: defaultZoom,
      pitch: 0,
      bearing: 0,
    );
  }

  void reset() {
    _initialViewport = null;
    _following = true;
  }
}

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../services/delivery_geofence_service.dart';
import '../utils/tracking_camera_state.dart';
import '../services/location_tracking_service.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';

class KombiTrackingScreen extends StatefulWidget {
  const KombiTrackingScreen({super.key});

  @override
  State<KombiTrackingScreen> createState() => _KombiTrackingScreenState();
}

class _KombiTrackingScreenState extends State<KombiTrackingScreen>
    with WidgetsBindingObserver {
  static const double _bottomNavbarHeight = 88.0;
  static const double _bottomNavbarGap = 20.0;
  static const double _myLocationZoomCenterOffset = 26.0;

  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  final LocationTrackingService _trackingService = LocationTrackingService();
  StreamSubscription? _locationSubscription;
  Timer? _locationReconnectTimer;

  Point? _kombiLocation;
  bool _isOnline = false;
  DateTime? _lastUpdate;
  bool _isAdmin = false;
  double _currentZoom = TrackingCameraState.defaultZoom;
  final _cameraState = TrackingCameraState();
  String? _currentAddress;
  bool _isLoadingAddress = false;
  String? _lastGeocodeKey;
  int _addressRequestId = 0;

  // Multi-Kombi support
  List<Map<String, dynamic>> _allKombis = [];
  String? _selectedAdminId;
  final Map<String, String> _vendorNames = {};

  // Controlador para o top sheet arrastável (invertido)
  bool _isSheetExpanded = false;
  double get _sheetCollapsedHeight => 60.0;
  double get _sheetExpandedHeight {
    final onlineCount = _allKombis.where(_isKombiOnline).length;
    return onlineCount > 1 ? 340.0 : 280.0;
  }

  bool _isKombiOnline(Map<String, dynamic> kombi) {
    return LocationTrackingService.isKombiRecentlyOnline(kombi);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    kombiOnlineStatus.addListener(_onKombiStatusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdminStatus();
    });
    _loadInitialLocation();
    _subscribeToLocationUpdates();
  }

  void _onKombiStatusChanged() {
    debugPrint(
      '🔔 KombiTracking - Status global mudou para: ${kombiOnlineStatus.value}',
    );
    if (!mounted) return;

    if (!kombiOnlineStatus.value) {
      setState(() {
        _isOnline = false;
        _kombiLocation = null;
        _mapboxMap = null;
        _pointAnnotationManager = null;
        _cameraState.reset();
        _selectedAdminId = null;
      });
      unawaited(_clearMarker());
    } else if (_selectedAdminId == null || _kombiLocation == null) {
      unawaited(_loadInitialLocation());
    }
  }

  Future<void> _checkAdminStatus() async {
    if (_isAdmin) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      debugPrint(
        '🔍 KombiTracking - Verificando admin status - user: ${user?.id}',
      );

      if (user == null) {
        debugPrint('⚠️ KombiTracking - Usuário não autenticado');
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('📊 KombiTracking - Resposta da query: $response');

      if (mounted && response != null) {
        final isAdmin = response['role'] == 'admin';
        debugPrint('✅ KombiTracking - is_admin definido como: $isAdmin');
        if (_isAdmin != isAdmin) {
          setState(() => _isAdmin = isAdmin);
        }
      } else {
        debugPrint('⚠️ KombiTracking - Response null ou widget desmontado');
      }
    } catch (e) {
      debugPrint('❌ KombiTracking - Erro ao verificar status admin: $e');
    }
  }

  Future<void> _loadInitialLocation() async {
    final kombis = await _trackingService.getAllOnlineKombis();
    if (kombis.isNotEmpty && mounted) {
      await _loadVendorNames(kombis);
      setState(() => _allKombis = kombis);
      final selected =
          kombis.where((k) => k['admin_id'] == _selectedAdminId).firstOrNull ??
          kombis.first;
      final id = selected['admin_id'] as String;
      _selectKombi(id, recenter: _selectedAdminId != id || _mapboxMap == null);
    } else if (mounted) {
      setState(() {
        _allKombis = [];
        _isOnline = false;
        _kombiLocation = null;
        _mapboxMap = null;
        _pointAnnotationManager = null;
        _cameraState.reset();
        _selectedAdminId = null;
      });
      await _clearMarker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    kombiOnlineStatus.removeListener(_onKombiStatusChanged);
    _locationSubscription?.cancel();
    _locationReconnectTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_loadInitialLocation());
    _subscribeToLocationUpdates();
  }

  void _subscribeToLocationUpdates() {
    unawaited(_locationSubscription?.cancel());
    _locationReconnectTimer?.cancel();
    _locationSubscription = _trackingService.watchAllKombis().listen(
      (allData) {
        if (!mounted) return;

        final onlineKombis = allData.where(_isKombiOnline).toList();

        // Carregar nomes de vendedores novos
        final currentIds = _vendorNames.keys.toSet();
        final hasNewIds = allData.any(
          (k) => !currentIds.contains(k['admin_id'] as String),
        );
        if (hasNewIds) {
          _loadVendorNames(allData);
        }

        setState(() => _allKombis = allData);

        if (onlineKombis.isEmpty) {
          setState(() {
            _isOnline = false;
            _kombiLocation = null;
            _mapboxMap = null;
            _pointAnnotationManager = null;
            _cameraState.reset();
            _selectedAdminId = null;
          });
          _clearMarker();
          return;
        }

        // Se a kombi selecionada ficou offline, selecionar a primeira online
        final selectedStillOnline = onlineKombis.any(
          (k) => k['admin_id'] == _selectedAdminId,
        );
        if (!selectedStillOnline) {
          _selectKombi(onlineKombis.first['admin_id'] as String);
          return;
        }

        // Atualizar localização da kombi selecionada
        final selected = onlineKombis.firstWhere(
          (k) => k['admin_id'] == _selectedAdminId,
        );
        final latitude = selected['latitude'] as double?;
        final longitude = selected['longitude'] as double?;

        if (latitude != null && longitude != null) {
          setState(() {
            _kombiLocation = Point(coordinates: Position(longitude, latitude));
            _isOnline = true;
            _lastUpdate = DateTime.now();
          });
          _updateMarker();
          _animateToLocation();
          _reverseGeocode(latitude, longitude);
        }
      },
      onError: (error) {
        if (mounted) {
          debugPrint('Erro ao receber localização: $error');
          _scheduleLocationReconnect();
        }
      },
      onDone: _scheduleLocationReconnect,
    );
  }

  void _scheduleLocationReconnect() {
    if (!mounted) return;
    _locationReconnectTimer?.cancel();
    _locationReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(_loadInitialLocation());
      _subscribeToLocationUpdates();
    });
  }

  Future<void> _loadVendorNames(List<Map<String, dynamic>> kombis) async {
    final adminIds = kombis.map((k) => k['admin_id'] as String).toList();
    final newNames = await _trackingService.getVendorNames(adminIds);
    if (mounted) {
      setState(() => _vendorNames.addAll(newNames));
    }
  }

  void _selectKombi(String adminId, {bool recenter = true}) {
    final kombi = _allKombis.firstWhere(
      (k) => k['admin_id'] == adminId,
      orElse: () => <String, dynamic>{},
    );
    if (kombi.isEmpty) return;

    final latitude = kombi['latitude'] as double?;
    final longitude = kombi['longitude'] as double?;
    final isOnline = _isKombiOnline(kombi);

    final selectionChanged = _selectedAdminId != adminId;
    setState(() {
      _selectedAdminId = adminId;
      _isOnline = isOnline;
      if (latitude != null && longitude != null) {
        _kombiLocation = Point(coordinates: Position(longitude, latitude));
        _lastUpdate = DateTime.now();
      } else {
        _kombiLocation = null;
        _mapboxMap = null;
        _pointAnnotationManager = null;
        _cameraState.reset();
      }
      if (selectionChanged) {
        _currentAddress = null;
        _lastGeocodeKey = null;
        _addressRequestId++;
        _isLoadingAddress = false;
      }
    });

    if (latitude != null && longitude != null) {
      _updateMarker();
      _animateToLocation(recenter: recenter);
      _reverseGeocode(latitude, longitude);
    }
  }

  Future<void> _updateMarker() async {
    if (_kombiLocation == null || _pointAnnotationManager == null) return;

    debugPrint(
      '📍 Atualizando marcador na posição: ${_kombiLocation!.coordinates.lng}, ${_kombiLocation!.coordinates.lat}',
    );

    // Remove marcador anterior
    await _clearMarker();

    // Cria novo marcador com ícone de carrinho/kombi
    final pointAnnotationOptions = PointAnnotationOptions(
      geometry: _kombiLocation!,
      iconImage: 'car', // Ícone padrão do Mapbox para veículo
      iconSize: 1.5,
      iconColor: 0xFFFF6B35, // Cor laranja vibrante
      iconRotate: 0.0,
      iconAnchor: IconAnchor.CENTER,
      textField: _vendorNames[_selectedAdminId] ?? 'Kombi',
      textSize: 12.0,
      textColor: 0xFF000000,
      textOffset: [0.0, 2.0],
      textHaloColor: 0xFFFFFFFF,
      textHaloWidth: 1.5,
    );

    await _pointAnnotationManager?.create(pointAnnotationOptions);
    debugPrint('✅ Marcador criado com sucesso');
  }

  Future<void> _reverseGeocode(double latitude, double longitude) async {
    if (!mounted) return;
    final key =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    if (_lastGeocodeKey == key) return;
    _lastGeocodeKey = key;
    final requestId = ++_addressRequestId;
    setState(() => _isLoadingAddress = true);
    try {
      final address = await DeliveryGeofenceService.instance
          .reverseGeocodeCoordinates(latitude: latitude, longitude: longitude);
      if (!mounted || requestId != _addressRequestId) return;
      final parts = [
        address?.endereco,
        address?.numero,
        address?.bairro,
        address?.cidade,
      ].whereType<String>().where((part) => part.trim().isNotEmpty);
      setState(() {
        _currentAddress = parts.isEmpty
            ? 'Endereço não disponível'
            : parts.join(', ');
        _isLoadingAddress = false;
      });
    } catch (_) {
      if (!mounted || requestId != _addressRequestId) return;
      setState(() {
        _currentAddress = 'Endereço não disponível';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _clearMarker() async {
    if (_pointAnnotationManager != null) {
      await _pointAnnotationManager!.deleteAll();
    }
  }

  Future<void> _animateToLocation({bool recenter = false}) async {
    final map = _mapboxMap;
    final location = _kombiLocation;
    if (map == null || location == null) return;
    final camera = recenter
        ? _cameraState.recenter(location)
        : _cameraState.locationChanged(location);
    if (camera == null) return;
    await map.flyTo(
      camera,
      MapAnimationOptions(duration: recenter ? 900 : 500),
    );
  }

  Future<void> _zoomIn() => _changeZoom(1);
  Future<void> _zoomOut() => _changeZoom(-1);

  Future<void> _changeZoom(double delta) async {
    final map = _mapboxMap;
    if (map == null) return;
    _cameraState.userGesture();
    final current = await map.getCameraState();
    if (!mounted || !identical(_mapboxMap, map)) return;
    _currentZoom = (current.zoom + delta).clamp(1.0, 22.0);
    await map.easeTo(
      CameraOptions(zoom: _currentZoom),
      MapAnimationOptions(duration: 300),
    );
  }

  double _mapControlsBottomInset(BuildContext context) {
    final view = View.of(context);
    final safeBottom = view.viewPadding.bottom / view.devicePixelRatio;
    return _bottomNavbarHeight + _bottomNavbarGap + safeBottom;
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return 'Nunca';

    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inSeconds < 60) {
      return 'Agora mesmo';
    } else if (diff.inMinutes < 60) {
      return 'Há ${diff.inMinutes} min';
    } else {
      return 'Há ${diff.inHours}h';
    }
  }

  void _onMapCreated(MapboxMap map) async {
    if (!mounted || _kombiLocation == null) return;
    _mapboxMap = map;
    await map.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: true,
        pitchEnabled: true,
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        quickZoomEnabled: true,
        simultaneousRotateAndPinchToZoomEnabled: true,
      ),
    );
    if (!mounted || !identical(_mapboxMap, map)) return;
    final manager = await map.annotations.createPointAnnotationManager();
    if (!mounted || !identical(_mapboxMap, map)) return;
    _pointAnnotationManager = manager;
    _currentZoom = (await map.getCameraState()).zoom;
    if (!mounted || !identical(_mapboxMap, map)) return;
    await _updateMarker();
    // O viewport inicial já posicionou a câmera. Não sobrescreve um gesto
    // que possa ter ocorrido enquanto o mapa e o marcador carregavam.
  }

  @override
  Widget build(BuildContext context) {
    final mapControlsBottom = _mapControlsBottomInset(context);
    final sheetTop = MediaQuery.paddingOf(context).top + 48;
    final sheetHeight =
        (MediaQuery.sizeOf(context).height - sheetTop - mapControlsBottom - 12)
            .clamp(_sheetCollapsedHeight, _sheetExpandedHeight);

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: Colors.black,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            debugPrint('🔙 Botão voltar pressionado - Voltando para Home');
            final provider = MainNavigationProvider.of(context);
            if (provider?.navigateToPage != null) {
              provider!.navigateToPage!(0);
            }
          },
        ),
        title: const Text(
          'Rastreamento das Kombis',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [AppMenu(isGuestMode: false, isAdmin: _isAdmin)],
      ),
      body: Stack(
        children: [
          // Mapa Mapbox com gestos nativos habilitados
          _kombiLocation != null
              ? MapWidget(
                  key: const ValueKey('mapbox-map'),
                  styleUri: MapboxStyles.MAPBOX_STREETS,
                  onMapCreated: _onMapCreated,
                  viewport: _cameraState.initialViewport(_kombiLocation!),
                  onCameraChangeListener: (event) {
                    _currentZoom = event.cameraState.zoom;
                  },
                  onScrollListener: (_) => _cameraState.userGesture(),
                  onZoomListener: (_) => _cameraState.userGesture(),
                )
              : Container(
                  color: Colors.grey[100],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma Kombi Online',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nenhuma Kombi está compartilhando\nsua localização no momento.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          // Controles de zoom (lado esquerdo) - responsivo à navbar
          if (_kombiLocation != null)
            Positioned(
              left: 16,
              bottom: mapControlsBottom,
              child: Column(
                children: [
                  // Botão Zoom In (+)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _zoomIn,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.add,
                            color: Colors.grey[800],
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Botão Zoom Out (-)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _zoomOut,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.remove,
                            color: Colors.grey[800],
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Botão "Minha localização" - responsivo à navbar
          if (_kombiLocation != null)
            Positioned(
              right: 16,
              bottom: mapControlsBottom + _myLocationZoomCenterOffset,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.white,
                onPressed: () => _animateToLocation(recenter: true),
                child: Icon(Icons.my_location, color: Colors.grey[800]),
              ),
            ),

          // Card de informações superior expansível
          Positioned(
            top: sheetTop,
            left: 16, // Margem lateral esquerda
            right: 16, // Margem lateral direita
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity! < -200) {
                  // Arrastar para cima rápido = retrair
                  setState(() => _isSheetExpanded = false);
                } else if (details.primaryVelocity! > 200) {
                  // Arrastar para baixo rápido = expandir
                  setState(() => _isSheetExpanded = true);
                }
              },
              onTap: () {
                setState(() => _isSheetExpanded = !_isSheetExpanded);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isSheetExpanded ? sheetHeight : _sheetCollapsedHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    24,
                  ), // Arredonda todos os cantos
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Barra de arrasto com área de toque maior
                      Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isSheetExpanded
                                    ? 'Arraste para cima'
                                    : 'Arraste para baixo',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Conteúdo expansível
                      if (_isSheetExpanded) ...[
                        // Seletor de Kombis (quando há mais de uma online)
                        if (_allKombis.where(_isKombiOnline).length > 1) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selecione uma Kombi:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _allKombis
                                        .where(_isKombiOnline)
                                        .map((kombi) {
                                          final adminId =
                                              kombi['admin_id'] as String;
                                          final isSelected =
                                              adminId == _selectedAdminId;
                                          final vendorName =
                                              _vendorNames[adminId] ??
                                              'Vendedor';
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: ChoiceChip(
                                              label: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Colors.green,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(vendorName),
                                                ],
                                              ),
                                              selected: isSelected,
                                              selectedColor: Colors.orange[100],
                                              backgroundColor: Colors.grey[100],
                                              labelStyle: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? Colors.orange[900]
                                                    : Colors.grey[800],
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                side: BorderSide(
                                                  color: isSelected
                                                      ? Colors.orange
                                                      : Colors.grey[300]!,
                                                ),
                                              ),
                                              onSelected: (_) =>
                                                  _selectKombi(adminId),
                                            ),
                                          );
                                        })
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Status badge centralizado
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _isOnline
                                  ? Colors.green[50]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isOnline
                                    ? Colors.green[300]!
                                    : Colors.grey[300]!,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isOnline
                                        ? Colors.green
                                        : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isOnline
                                      ? '${_vendorNames[_selectedAdminId] ?? 'KOMBI'} - ONLINE'
                                      : 'KOMBI OFFLINE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _isOnline
                                        ? Colors.green[800]
                                        : Colors.grey[800],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Informações principais (se online)
                        if (_isOnline && _kombiLocation != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Endereço completo
                                if (_currentAddress != null ||
                                    _isLoadingAddress) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.blue[200]!,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 20,
                                              color: Colors.blue[700],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Localização Atual',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue[900],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (_isLoadingAddress)
                                          Row(
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.blue[700],
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Obtendo endereço...',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          )
                                        else if (_currentAddress != null)
                                          Text(
                                            _currentAddress!,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[800],
                                              height: 1.4,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Última atualização
                                if (_lastUpdate != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 20,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Última atualização: ${_formatLastUpdate()}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../services/location_tracking_service.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';

class KombiTrackingScreen extends StatefulWidget {
  const KombiTrackingScreen({super.key});

  @override
  State<KombiTrackingScreen> createState() => _KombiTrackingScreenState();
}

class _KombiTrackingScreenState extends State<KombiTrackingScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  final LocationTrackingService _trackingService = LocationTrackingService();
  StreamSubscription? _locationSubscription;

  Point? _kombiLocation;
  bool _isOnline = false;
  DateTime? _lastUpdate;
  bool _isAdmin = false;
  double _currentZoom = 16.0;
  String? _currentAddress;
  bool _isLoadingAddress = false;

  // Multi-Kombi support
  List<Map<String, dynamic>> _allKombis = [];
  String? _selectedAdminId;
  final Map<String, String> _vendorNames = {};

  // Controlador para o top sheet arrastável (invertido)
  bool _isSheetExpanded = false;
  double get _sheetCollapsedHeight => 60.0;
  double get _sheetExpandedHeight {
    final onlineCount = _allKombis.where((k) => k['is_online'] == true).length;
    return onlineCount > 1 ? 340.0 : 280.0;
  }

  @override
  void initState() {
    super.initState();

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
    if (mounted) {
      setState(() {
        _isOnline = kombiOnlineStatus.value;
      });
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
      _selectKombi(kombis.first['admin_id'] as String);
    }
  }

  @override
  void dispose() {
    kombiOnlineStatus.removeListener(_onKombiStatusChanged);
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToLocationUpdates() {
    _locationSubscription = _trackingService.watchAllKombis().listen(
      (allData) {
        if (!mounted) return;

        final onlineKombis = allData
            .where((d) => d['is_online'] == true)
            .toList();

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
        }
      },
    );
  }

  Future<void> _loadVendorNames(List<Map<String, dynamic>> kombis) async {
    final adminIds = kombis.map((k) => k['admin_id'] as String).toList();
    final newNames = await _trackingService.getVendorNames(adminIds);
    if (mounted) {
      setState(() => _vendorNames.addAll(newNames));
    }
  }

  void _selectKombi(String adminId) {
    final kombi = _allKombis.firstWhere(
      (k) => k['admin_id'] == adminId,
      orElse: () => <String, dynamic>{},
    );
    if (kombi.isEmpty) return;

    final latitude = kombi['latitude'] as double?;
    final longitude = kombi['longitude'] as double?;
    final isOnline = kombi['is_online'] as bool? ?? false;

    setState(() {
      _selectedAdminId = adminId;
      _isOnline = isOnline;
      if (latitude != null && longitude != null) {
        _kombiLocation = Point(coordinates: Position(longitude, latitude));
        _lastUpdate = DateTime.now();
      } else {
        _kombiLocation = null;
      }
      _currentAddress = null;
    });

    if (latitude != null && longitude != null) {
      _updateMarker();
      _animateToLocation();
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

    debugPrint('🌍 Iniciando geocodificação reversa...');
    debugPrint('📍 Lat: $latitude, Lng: $longitude');

    setState(() => _isLoadingAddress = true);

    try {
      // Usando Mapbox Geocoding API com token centralizado
      final url = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$longitude,$latitude.json?access_token=${SupabaseConfig.mapboxAccessToken}&types=address,place,postcode,locality,neighborhood&language=pt',
      );

      debugPrint('🔗 URL da API: $url');

      final response = await http.get(url);

      debugPrint('📡 Status da resposta: ${response.statusCode}');
      debugPrint(
        '📄 Corpo da resposta: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty && mounted) {
          final feature = features[0];
          final placeName = feature['place_name'] as String?;

          // Extrair componentes do endereço
          String? rua, numero, bairro, cidade, estado, cep;

          final context = feature['context'] as List?;
          if (context != null) {
            for (var item in context) {
              final id = item['id'] as String;
              final text = item['text'] as String;

              if (id.startsWith('neighborhood')) {
                bairro = text;
              } else if (id.startsWith('place')) {
                cidade = text;
              } else if (id.startsWith('region')) {
                estado = text;
              } else if (id.startsWith('postcode')) {
                cep = text;
              }
            }
          }

          // Rua e número vêm do place_name
          if (placeName != null) {
            final parts = placeName.split(',');
            if (parts.isNotEmpty) {
              final firstPart = parts[0].trim();
              // Tentar extrair número usando split
              String? extractedNumero;
              String? extractedRua;

              // Procurar por dígitos no texto
              for (int i = 0; i < firstPart.length; i++) {
                if (firstPart.codeUnitAt(i) >= 48 &&
                    firstPart.codeUnitAt(i) <= 57) {
                  // Encontrou um dígito
                  int start = i;
                  while (i < firstPart.length &&
                      firstPart.codeUnitAt(i) >= 48 &&
                      firstPart.codeUnitAt(i) <= 57) {
                    i++;
                  }
                  extractedNumero = firstPart.substring(start, i);
                  extractedRua = firstPart
                      .replaceAll(extractedNumero, '')
                      .trim();
                  break;
                }
              }

              if (extractedNumero != null && extractedRua != null) {
                numero = extractedNumero;
                rua = extractedRua;
              } else {
                rua = firstPart;
              }
            }
          }

          // Montar endereço formatado
          final addressParts = <String>[];
          if (rua != null && rua.isNotEmpty) {
            if (numero != null) {
              addressParts.add('$rua, $numero');
            } else {
              addressParts.add(rua);
            }
          }
          if (bairro != null) addressParts.add(bairro);
          if (cidade != null) addressParts.add(cidade);
          if (estado != null) addressParts.add(estado);
          if (cep != null) addressParts.add('CEP: $cep');

          setState(() {
            _currentAddress = addressParts.isNotEmpty
                ? addressParts.join(' • ')
                : placeName ?? 'Endereço não disponível';
            _isLoadingAddress = false;
          });

          debugPrint('📍 Endereço obtido: $_currentAddress');
        } else {
          // Sem resultados - não é necessariamente um erro
          if (mounted) {
            setState(() {
              _currentAddress = 'Localização não especificada';
              _isLoadingAddress = false;
            });
          }
          // Log apenas para debug, sem emoji de aviso
          debugPrint(
            'ℹ️ Geocodificação reversa sem resultados para estas coordenadas',
          );
        }
      } else {
        // Resposta não foi 200
        if (mounted) {
          setState(() {
            _currentAddress = 'Não foi possível obter o endereço';
            _isLoadingAddress = false;
          });
        }
        debugPrint('❌ Erro na API de geocodificação: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao obter endereço: $e');
      if (mounted) {
        setState(() {
          _currentAddress = 'Não foi possível obter o endereço';
          _isLoadingAddress = false;
        });
      }
    }
  }

  Future<void> _clearMarker() async {
    if (_pointAnnotationManager != null) {
      await _pointAnnotationManager!.deleteAll();
    }
  }

  Future<void> _animateToLocation() async {
    if (_mapboxMap == null || _kombiLocation == null) return;

    debugPrint(
      '📹 Animando câmera para: ${_kombiLocation!.coordinates.lng}, ${_kombiLocation!.coordinates.lat}',
    );

    await _mapboxMap!.flyTo(
      CameraOptions(center: _kombiLocation, zoom: 17.0, pitch: 0, bearing: 0),
      MapAnimationOptions(duration: 1500, startDelay: 0),
    );

    debugPrint('✅ Câmera animada com sucesso');
  }

  Future<void> _zoomIn() async {
    if (_mapboxMap == null) return;
    _currentZoom = (_currentZoom + 1).clamp(1.0, 22.0);
    await _mapboxMap!.easeTo(
      CameraOptions(zoom: _currentZoom),
      MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _zoomOut() async {
    if (_mapboxMap == null) return;
    _currentZoom = (_currentZoom - 1).clamp(1.0, 22.0);
    await _mapboxMap!.easeTo(
      CameraOptions(zoom: _currentZoom),
      MapAnimationOptions(duration: 300),
    );
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

  void _onMapCreated(MapboxMap mapboxMap) async {
    debugPrint('🗺️ Mapa criado, inicializando...');
    _mapboxMap = mapboxMap;

    // Habilita gestos de navegação
    await _mapboxMap!.gestures.updateSettings(
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

    _pointAnnotationManager = await _mapboxMap!.annotations
        .createPointAnnotationManager();

    debugPrint('✅ PointAnnotationManager criado e gestos habilitados');

    // Define estilo do mapa (Streets)
    await _mapboxMap!.style.setStyleURI(MapboxStyles.MAPBOX_STREETS);

    // Obtém zoom inicial
    _currentZoom = (await _mapboxMap!.getCameraState()).zoom;

    if (_kombiLocation != null) {
      debugPrint('📍 Localização inicial disponível, criando marcador...');
      await _updateMarker();
      await _animateToLocation();
    } else {
      debugPrint('⚠️ Nenhuma localização disponível ainda');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onMapCreated: _onMapCreated,
                  cameraOptions: CameraOptions(
                    center: _kombiLocation,
                    zoom: 16.0,
                  ),
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
              bottom:
                  80 +
                  MediaQuery.of(context).padding.bottom, // Navbar + SafeArea
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
              bottom:
                  106 +
                  MediaQuery.of(
                    context,
                  ).padding.bottom, // Navbar + botões de zoom + SafeArea
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.white,
                onPressed: _animateToLocation,
                child: Icon(Icons.my_location, color: Colors.grey[800]),
              ),
            ),

          // Card de informações superior expansível
          Positioned(
            top: kToolbarHeight, // Logo abaixo da AppBar (sem margem adicional)
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
                height: _isSheetExpanded
                    ? _sheetExpandedHeight
                    : _sheetCollapsedHeight,
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
                  physics: const NeverScrollableScrollPhysics(),
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
                        if (_allKombis
                                .where((k) => k['is_online'] == true)
                                .length >
                            1) ...[
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
                                        .where((k) => k['is_online'] == true)
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

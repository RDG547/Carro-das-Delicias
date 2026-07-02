import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:turf/turf.dart';

import '../config/supabase_config.dart';

class DeliveryAreaResult {
  const DeliveryAreaResult({required this.atende, this.areaName});

  final bool atende;
  final String? areaName;
}

class DeliveryAddressValidation {
  const DeliveryAddressValidation({
    required this.atende,
    required this.addressQuery,
    this.areaName,
    this.message,
    this.latitude,
    this.longitude,
  });

  final bool atende;
  final String addressQuery;
  final String? areaName;
  final String? message;
  final double? latitude;
  final double? longitude;
}

class DeliveryReverseAddress {
  const DeliveryReverseAddress({
    this.endereco,
    this.bairro,
    this.cidade,
    this.cep,
  });

  final String? endereco;
  final String? bairro;
  final String? cidade;
  final String? cep;

  bool get hasAnyValue =>
      _hasText(endereco) ||
      _hasText(bairro) ||
      _hasText(cidade) ||
      _hasText(cep);

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;
}

class DeliveryGeofenceService {
  DeliveryGeofenceService._();

  static final DeliveryGeofenceService instance = DeliveryGeofenceService._();
  static const String _deliveryZonesAsset =
      'assets/coordenadas_entregas.geojson';

  FeatureCollection<GeometryObject>? _deliveryZones;
  Future<void>? _initializationFuture;

  Future<void> inicializarAreas() {
    _initializationFuture ??= _loadDeliveryZones();
    return _initializationFuture!;
  }

  Future<void> _loadDeliveryZones() async {
    try {
      final response = await rootBundle.loadString(_deliveryZonesAsset);
      final data = jsonDecode(response) as Map<String, dynamic>;
      _deliveryZones = FeatureCollection<GeometryObject>.fromJson(data);
    } catch (error, stackTrace) {
      _deliveryZones = null;
      debugPrint('Erro ao carregar áreas de entrega: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool verificarSeAtende(double latitude, double longitude) {
    return verificarCoordenada(latitude, longitude).atende;
  }

  DeliveryAreaResult verificarCoordenada(double latitude, double longitude) {
    final deliveryZones = _deliveryZones;
    if (deliveryZones == null) {
      debugPrint('Erro: as áreas de entrega ainda não foram inicializadas.');
      return const DeliveryAreaResult(atende: false);
    }

    final customerPoint = Position(longitude, latitude);

    for (final feature in deliveryZones.features) {
      final geometry = feature.geometry;
      final GeoJSONObject supportedGeometry;
      if (geometry is Polygon) {
        supportedGeometry = geometry;
      } else if (geometry is MultiPolygon) {
        supportedGeometry = geometry;
      } else {
        continue;
      }

      final isInside = booleanPointInPolygon(customerPoint, supportedGeometry);
      if (isInside) {
        final areaName =
            feature.properties?['name']?.toString().trim().isNotEmpty == true
            ? feature.properties!['name'].toString().trim()
            : 'Área de entrega';
        debugPrint('Cliente está dentro da área de entrega: $areaName');
        return DeliveryAreaResult(atende: true, areaName: areaName);
      }
    }

    return const DeliveryAreaResult(atende: false);
  }

  Future<DeliveryAddressValidation> validarEndereco({
    required String endereco,
    required String bairro,
    required String cidade,
    required String cep,
  }) async {
    await inicializarAreas();

    final addressQuery = _buildAddressQuery(
      endereco: endereco,
      bairro: bairro,
      cidade: cidade,
      cep: cep,
    );

    if (_deliveryZones == null) {
      return DeliveryAddressValidation(
        atende: false,
        addressQuery: addressQuery,
        message:
            'Não foi possível carregar o mapa das áreas de entrega. Tente novamente.',
      );
    }

    final coordinates = await _geocodeAddress(
      addressQuery: addressQuery,
      endereco: endereco,
      bairro: bairro,
      cidade: cidade,
      cep: cep,
    );
    if (coordinates == null) {
      return DeliveryAddressValidation(
        atende: false,
        addressQuery: addressQuery,
        message:
            'Não conseguimos localizar este endereço. Confira rua, número, bairro, cidade e CEP.',
      );
    }

    final areaResult = verificarCoordenada(
      coordinates.latitude,
      coordinates.longitude,
    );

    return DeliveryAddressValidation(
      atende: areaResult.atende,
      addressQuery: addressQuery,
      areaName: areaResult.areaName,
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      message: areaResult.atende
          ? 'Endereço dentro da área de entrega.'
          : 'Ainda não entregamos neste endereço.',
    );
  }

  String _buildAddressQuery({
    required String endereco,
    required String bairro,
    required String cidade,
    required String cep,
  }) {
    final street = _normalizeStreetForGeocoding(endereco);
    final parts = [
      street.trim(),
      bairro.trim(),
      cidade.trim(),
      cep.replaceAll(RegExp(r'[^0-9]'), '').trim(),
      'Brasil',
    ].where((part) => part.isNotEmpty).toList();

    return parts.join(', ');
  }

  String _normalizeStreetForGeocoding(String endereco) {
    final normalized = endereco
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(
          RegExp(
            r'\s+(casa|apto|apartamento|bloco|lote|fundos|sala|loja|refer[eê]ncia)\b.*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    return normalized.isEmpty ? endereco.trim() : normalized;
  }

  Future<_Coordinates?> _geocodeAddress({
    required String addressQuery,
    required String endereco,
    required String bairro,
    required String cidade,
    required String cep,
  }) async {
    final token = SupabaseConfig.mapboxAccessToken.trim();
    if (token.isNotEmpty) {
      final mapboxCoordinates = await _geocodeWithMapbox(addressQuery, token);
      if (mapboxCoordinates != null) return mapboxCoordinates;

      debugPrint(
        'Mapbox não encontrou o endereço. Tentando fallback por Nominatim.',
      );
    }

    return _geocodeWithNominatim(
      addressQuery: addressQuery,
      endereco: endereco,
      bairro: bairro,
      cidade: cidade,
      cep: cep,
    );
  }

  Future<_Coordinates?> _geocodeWithMapbox(
    String addressQuery,
    String token,
  ) async {
    final encodedQuery = Uri.encodeComponent(addressQuery);
    final url =
        Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$encodedQuery.json',
        ).replace(
          queryParameters: {
            'access_token': token,
            'country': 'br',
            'language': 'pt',
            'limit': '1',
            'proximity': '-43.45,-22.88',
            'types': 'address,place,postcode,locality,neighborhood',
          },
        );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint(
          'Erro Mapbox geocoding ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final firstFeature = features.first as Map<String, dynamic>;
      final center = firstFeature['center'] as List<dynamic>?;
      if (center == null || center.length < 2) return null;

      final longitude = (center[0] as num).toDouble();
      final latitude = (center[1] as num).toDouble();
      return _Coordinates(latitude: latitude, longitude: longitude);
    } catch (error) {
      debugPrint('Erro ao geocodificar endereço para entrega: $error');
      return null;
    }
  }

  Future<_Coordinates?> _geocodeWithNominatim({
    required String addressQuery,
    required String endereco,
    required String bairro,
    required String cidade,
    required String cep,
  }) async {
    final street = _normalizeStreetForGeocoding(endereco);
    final originalStreet = endereco.trim();
    final city = cidade.trim();
    final postalCode = cep.replaceAll(RegExp(r'[^0-9]'), '').trim();

    final attempts = [
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'br',
        'street': street,
        'city': city,
        'postalcode': postalCode,
        'country': 'Brasil',
        'accept-language': 'pt-BR',
      }),
      if (originalStreet.isNotEmpty && originalStreet != street)
        Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'jsonv2',
          'limit': '1',
          'countrycodes': 'br',
          'street': originalStreet,
          'city': city,
          'postalcode': postalCode,
          'country': 'Brasil',
          'accept-language': 'pt-BR',
        }),
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'br',
        'q': addressQuery,
        'accept-language': 'pt-BR',
      }),
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'br',
        'q': [
          street,
          bairro.trim(),
          city,
          'Rio de Janeiro',
          'Brasil',
        ].where((part) => part.isNotEmpty).join(', '),
        'accept-language': 'pt-BR',
      }),
    ];

    for (final url in attempts) {
      final coordinates = await _fetchNominatimCoordinates(url);
      if (coordinates != null) return coordinates;
    }

    return null;
  }

  Future<_Coordinates?> _fetchNominatimCoordinates(Uri url) async {
    try {
      final response = await http
          .get(
            url,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'CarroDasDeliciasApp/1.0 (validacao-area-entrega)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          'Erro Nominatim geocoding ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! List || data.isEmpty) return null;

      final firstResult = data.first;
      if (firstResult is! Map<String, dynamic>) return null;

      final latitude = double.tryParse(firstResult['lat']?.toString() ?? '');
      final longitude = double.tryParse(firstResult['lon']?.toString() ?? '');
      if (latitude == null || longitude == null) return null;

      return _Coordinates(latitude: latitude, longitude: longitude);
    } catch (error) {
      debugPrint('Erro ao geocodificar com Nominatim: $error');
      return null;
    }
  }

  Future<DeliveryReverseAddress?> reverseGeocodeCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    final token = SupabaseConfig.mapboxAccessToken.trim();
    if (token.isNotEmpty) {
      final mapboxAddress = await _reverseGeocodeWithMapbox(
        latitude: latitude,
        longitude: longitude,
        token: token,
      );
      if (mapboxAddress?.hasAnyValue == true) return mapboxAddress;
    }

    return _reverseGeocodeWithNominatim(
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<DeliveryReverseAddress?> _reverseGeocodeWithMapbox({
    required double latitude,
    required double longitude,
    required String token,
  }) async {
    final url =
        Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$longitude,$latitude.json',
        ).replace(
          queryParameters: {
            'access_token': token,
            'country': 'br',
            'language': 'pt',
            'limit': '1',
            'types': 'address,place,postcode,locality,neighborhood',
          },
        );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint(
          'Erro Mapbox reverse geocoding ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final feature = features.first as Map<String, dynamic>;
      final text = feature['text']?.toString().trim();
      final number = feature['address']?.toString().trim();
      final endereco = [
        text,
        number,
      ].where((part) => part?.isNotEmpty == true).join(', ');

      String? bairro;
      String? cidade;
      String? cep;
      final context = feature['context'] as List<dynamic>?;
      if (context != null) {
        for (final rawItem in context) {
          if (rawItem is! Map<String, dynamic>) continue;

          final id = rawItem['id']?.toString() ?? '';
          final itemText = rawItem['text']?.toString().trim();
          if (itemText == null || itemText.isEmpty) continue;

          if (id.startsWith('neighborhood') || id.startsWith('locality')) {
            bairro ??= itemText;
          } else if (id.startsWith('place')) {
            cidade ??= itemText;
          } else if (id.startsWith('postcode')) {
            cep ??= itemText;
          }
        }
      }

      return DeliveryReverseAddress(
        endereco: endereco.isEmpty ? null : endereco,
        bairro: bairro,
        cidade: cidade,
        cep: cep,
      );
    } catch (error) {
      debugPrint('Erro ao fazer reverse geocoding Mapbox: $error');
      return null;
    }
  }

  Future<DeliveryReverseAddress?> _reverseGeocodeWithNominatim({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'accept-language': 'pt-BR',
      'zoom': '18',
      'addressdetails': '1',
    });

    try {
      final response = await http
          .get(
            url,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'CarroDasDeliciasApp/1.0 (validacao-area-entrega)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          'Erro Nominatim reverse geocoding ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'];
      if (address is! Map<String, dynamic>) return null;

      final road = _firstAddressValue(address, const [
        'road',
        'pedestrian',
        'residential',
        'footway',
      ]);
      final number = _firstAddressValue(address, const ['house_number']);
      final endereco = [
        road,
        number,
      ].where((part) => part?.isNotEmpty == true).join(', ');

      final bairro = _firstAddressValue(address, const [
        'suburb',
        'neighbourhood',
        'quarter',
        'city_district',
      ]);
      final cidade = _firstAddressValue(address, const [
        'city',
        'town',
        'municipality',
      ]);
      final cep = _firstAddressValue(address, const ['postcode']);

      return DeliveryReverseAddress(
        endereco: endereco.isEmpty ? null : endereco,
        bairro: bairro,
        cidade: cidade,
        cep: cep,
      );
    } catch (error) {
      debugPrint('Erro ao fazer reverse geocoding Nominatim: $error');
      return null;
    }
  }

  String? _firstAddressValue(Map<String, dynamic> address, List<String> keys) {
    for (final key in keys) {
      final value = address[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class _Coordinates {
  const _Coordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

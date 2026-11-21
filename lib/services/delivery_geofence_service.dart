import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:turf/turf.dart';

import '../config/supabase_config.dart';
import '../utils/geocoding_text.dart';

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
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.cep,
  });

  final String? endereco;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? cep;

  bool get hasAnyValue =>
      _hasText(endereco) ||
      _hasText(numero) ||
      _hasText(complemento) ||
      _hasText(bairro) ||
      _hasText(cidade) ||
      _hasText(cep);

  bool get hasStreetAddress => _hasText(endereco) || _hasText(numero);

  DeliveryReverseAddress mergeMissing(DeliveryReverseAddress? fallback) {
    if (fallback == null) return this;

    return DeliveryReverseAddress(
      endereco: _hasText(endereco) ? endereco : fallback.endereco,
      numero: _hasText(numero) ? numero : fallback.numero,
      complemento: _hasText(complemento) ? complemento : fallback.complemento,
      bairro: _hasText(bairro) ? bairro : fallback.bairro,
      cidade: _hasText(cidade) ? cidade : fallback.cidade,
      cep: _hasText(cep) ? cep : fallback.cep,
    );
  }

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
    DeliveryReverseAddress? mapboxAddress;
    final token = SupabaseConfig.mapboxAccessToken.trim();
    if (token.isNotEmpty) {
      mapboxAddress = await _reverseGeocodeWithMapbox(
        latitude: latitude,
        longitude: longitude,
        token: token,
      );
      final needsBetterNumber =
          mapboxAddress?.hasStreetAddress != true ||
          mapboxAddress?.numero?.trim().isEmpty == true;
      if (needsBetterNumber) {
        final mapboxV6Address = await _reverseGeocodeWithMapboxV6(
          latitude: latitude,
          longitude: longitude,
          token: token,
        );
        mapboxAddress =
            mapboxAddress?.mergeMissing(mapboxV6Address) ?? mapboxV6Address;
      }
    }

    final nominatimAddress = await _reverseGeocodeWithNominatim(
      latitude: latitude,
      longitude: longitude,
    );

    if (mapboxAddress?.hasStreetAddress == true) {
      return mapboxAddress!.mergeMissing(nominatimAddress);
    }

    if (nominatimAddress?.hasStreetAddress == true) {
      return nominatimAddress!.mergeMissing(mapboxAddress);
    }

    return mapboxAddress?.mergeMissing(nominatimAddress) ?? nominatimAddress;
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
            'limit': '5',
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

      final feature = _bestMapboxAddressFeature(features);
      final text = feature['text']?.toString().trim();
      final number = _extractNumberFromFeature(feature, text);

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
        endereco: text == null || text.isEmpty ? null : text,
        numero: number == null || number.isEmpty ? null : number,
        complemento: _mapboxComplement(feature),
        bairro: bairro,
        cidade: cidade,
        cep: cep,
      );
    } catch (error) {
      debugPrint('Erro ao fazer reverse geocoding Mapbox: $error');
      return null;
    }
  }

  Future<DeliveryReverseAddress?> _reverseGeocodeWithMapboxV6({
    required double latitude,
    required double longitude,
    required String token,
  }) async {
    final url = Uri.https('api.mapbox.com', '/search/geocode/v6/reverse', {
      'access_token': token,
      'longitude': longitude.toString(),
      'latitude': latitude.toString(),
      'country': 'br',
      'language': 'pt',
      'types': 'address,street,place,postcode,locality,neighborhood',
    });

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint(
          'Erro Mapbox v6 reverse geocoding ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final feature = _bestMapboxAddressFeature(features);
      final properties = feature['properties'];
      final props = properties is Map<String, dynamic>
          ? properties
          : <String, dynamic>{};
      final fullAddress =
          GeocodingText.label(props['full_address']) ??
          GeocodingText.label(props['place_formatted']) ??
          GeocodingText.label(props['name']);
      final name =
          GeocodingText.label(props['name']) ??
          GeocodingText.label(feature['text']);
      final number = _extractNumberFromFeature(feature, name);
      final street = _streetFromAddressText(fullAddress, number) ?? name;

      return DeliveryReverseAddress(
        endereco: street == null || street.isEmpty ? null : street,
        numero: number == null || number.isEmpty ? null : number,
        complemento: _mapboxComplement(feature),
        bairro: _nestedString(feature, const {
          'neighborhood',
          'locality',
          'district',
        }),
        cidade: _nestedString(feature, const {'place', 'city', 'locality'}),
        cep: _nestedString(feature, const {'postcode', 'postal_code'}),
      );
    } catch (error) {
      debugPrint('Erro ao fazer reverse geocoding Mapbox v6: $error');
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
        endereco: road,
        numero: number,
        complemento: _firstAddressValue(address, const [
          'building',
          'house',
          'amenity',
          'shop',
          'office',
        ]),
        bairro: bairro,
        cidade: cidade,
        cep: cep,
      );
    } catch (error) {
      debugPrint('Erro ao fazer reverse geocoding Nominatim: $error');
      return null;
    }
  }

  Map<String, dynamic> _bestMapboxAddressFeature(List<dynamic> features) {
    for (final rawFeature in features) {
      if (rawFeature is! Map<String, dynamic>) continue;

      final placeTypes = rawFeature['place_type'];
      final isAddress =
          placeTypes is List &&
          placeTypes.any((type) => type?.toString() == 'address');
      final hasNumber =
          rawFeature['address']?.toString().trim().isNotEmpty == true;
      final text = rawFeature['text']?.toString();
      final hasStreetAndNumber =
          text?.trim().isNotEmpty == true &&
          _extractNumberFromPlaceName(rawFeature, text) != null;

      if (isAddress || hasNumber || hasStreetAndNumber) return rawFeature;
    }

    for (final rawFeature in features) {
      if (rawFeature is Map<String, dynamic>) return rawFeature;
    }

    return <String, dynamic>{};
  }

  String? _mapboxComplement(Map<String, dynamic> feature) {
    final properties = feature['properties'];
    if (properties is Map<String, dynamic>) {
      for (final key in const ['unit', 'suite', 'building', 'name']) {
        final value = GeocodingText.label(properties[key]);
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _extractNumberFromFeature(
    Map<String, dynamic> feature,
    String? streetName,
  ) {
    for (final value in [
      feature['address'],
      feature['address_number'],
      _nestedString(feature, const {'address_number', 'house_number'}),
      (feature['properties'] is Map<String, dynamic>)
          ? (feature['properties'] as Map<String, dynamic>)['address']
          : null,
      (feature['properties'] is Map<String, dynamic>)
          ? (feature['properties'] as Map<String, dynamic>)['address_number']
          : null,
      (feature['properties'] is Map<String, dynamic>)
          ? (feature['properties'] as Map<String, dynamic>)['house_number']
          : null,
    ]) {
      final number = _normalizeAddressNumber(value?.toString());
      if (number != null) return number;
    }

    for (final value in [
      feature['place_name'],
      feature['matching_place_name'],
      feature['text'],
      feature['matching_text'],
    ]) {
      final number = _extractNumberFromAddressText(
        value?.toString(),
        streetName,
      );
      if (number != null) return number;
    }

    return null;
  }

  String? _streetFromAddressText(String? value, String? number) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;

    final parts = text
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final numberText = number?.trim();
    for (final part in parts.take(3)) {
      if (numberText != null && part == numberText) continue;
      final withoutNumber = numberText == null
          ? part
          : part
                .replaceFirst(
                  RegExp(
                    '^${RegExp.escape(numberText)}\\s+',
                    caseSensitive: false,
                  ),
                  '',
                )
                .replaceFirst(
                  RegExp(
                    '\\s*,?\\s*${RegExp.escape(numberText)}\$',
                    caseSensitive: false,
                  ),
                  '',
                )
                .trim();
      if (withoutNumber.isNotEmpty &&
          RegExp(
            r'\b(rua|avenida|av\.?|estrada|travessa|praça|rodovia|alameda)\b',
            caseSensitive: false,
          ).hasMatch(withoutNumber)) {
        return withoutNumber;
      }
    }

    return parts.first;
  }

  String? _nestedString(dynamic value, Set<String> keys) =>
      GeocodingText.find(value, keys);

  String? _extractNumberFromPlaceName(
    Map<String, dynamic> feature,
    String? streetName,
  ) {
    return _extractNumberFromAddressText(
      feature['place_name']?.toString(),
      streetName,
    );
  }

  String? _extractNumberFromAddressText(String? value, String? streetName) {
    final placeName = value?.trim();
    if (placeName == null || placeName.isEmpty) return null;

    final street = streetName?.trim();
    if (street != null && street.isNotEmpty) {
      final escapedStreet = RegExp.escape(street);
      for (final pattern in [
        '$escapedStreet\\s*,\\s*([^,]+)',
        '$escapedStreet\\s+(\\d{1,5}[a-zA-Z]?(?:[-/]\\d{1,5})?)\\b',
        '\\b(\\d{1,5}[a-zA-Z]?(?:[-/]\\d{1,5})?)\\s+$escapedStreet\\b',
      ]) {
        final match = RegExp(
          pattern,
          caseSensitive: false,
        ).firstMatch(placeName);
        final number = _normalizeAddressNumber(match?.group(1));
        if (number != null) return number;
      }
    }

    final parts = placeName.split(',').map((part) => part.trim()).take(3);
    for (final part in parts) {
      final number = _normalizeAddressNumber(part);
      if (number != null) return number;
    }

    final firstNumber = RegExp(
      r'\b\d{1,5}[a-zA-Z]?(?:[-/]\d{1,5})?\b',
    ).firstMatch(placeName);
    return _normalizeAddressNumber(firstNumber?.group(0));
  }

  String? _normalizeAddressNumber(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;

    final match = RegExp(
      r'^\s*(?:n[ºo.]?\s*)?(\d{1,5}[a-zA-Z]?(?:[-/]\d{1,5})?)\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final number = match.group(1);
    if (number == null || RegExp(r'^\d{5}-?\d{3}$').hasMatch(number)) {
      return null;
    }
    return number;
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

import 'package:carrodasdelicias/utils/geocoding_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final feature = {
    'properties': {
      'context': {
        'place': {
          'mapbox_id': 'provider-id',
          'name': 'Rio de Janeiro',
          'wikidata_id': 'Q8678',
        },
        'locality': {
          'mapbox_id': 'district-id',
          'name': 'Senador Camará',
          'translations': {
            'pt': {'name': 'Senador Camará'},
          },
        },
        'neighborhood': {
          'mapbox_id': 'neighborhood-id',
          'name': 'Vila Aliança',
        },
        'postcode': {'name': '21840-000'},
        'address': {
          'street_name': 'Rua Capitão Borges Couto',
          'address_number': '66',
        },
      },
    },
  };
  test('Mapbox v6 apresenta somente os nomes e prioriza bairro específico', () {
    expect(
      GeocodingText.find(feature, ['neighborhood', 'locality', 'district']),
      'Vila Aliança',
    );
    expect(
      GeocodingText.find(feature, ['place', 'city', 'locality']),
      'Rio de Janeiro',
    );
    expect(GeocodingText.find(feature, ['postcode']), '21840-000');
    expect(GeocodingText.find(feature, ['address_number']), '66');
  });
  test('contexto sem nome não exibe IDs nem traduções como endereço', () {
    expect(
      GeocodingText.find(
        {
          'place': {
            'mapbox_id': 'id',
            'translations': {
              'pt': {'name': 'Oculto'},
            },
          },
        },
        ['place'],
      ),
      isNull,
    );
    expect(GeocodingText.label(['Cidade']), isNull);
    expect(GeocodingText.label({'name': ' ', 'text': ' Bangu '}), 'Bangu');
    expect(GeocodingText.label(66), '66');
    expect(
      GeocodingText.label({
        'name_preferred': 'Nome preferido',
        'name': 'Outro',
      }),
      'Nome preferido',
    );
  });
}

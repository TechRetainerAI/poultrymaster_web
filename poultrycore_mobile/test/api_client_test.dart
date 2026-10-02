import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/api/api_client.dart';
import 'package:poultrycore_mobile/models/company.dart';

void main() {
  group('ApiClient.normalise', () {
    test('lowercases the first letter of PascalCase keys', () {
      final out = ApiClient.normalise({'FarmId': 'abc', 'FarmName': 'Great Favour'});
      expect(out, {'farmId': 'abc', 'farmName': 'Great Favour'});
    });

    test('leaves camelCase keys untouched', () {
      final out = ApiClient.normalise({'farmId': 'abc', 'totalCount': 3});
      expect(out, {'farmId': 'abc', 'totalCount': 3});
    });

    test('recurses through nested maps and lists', () {
      final out = ApiClient.normalise({
        'Response': {
          'AccessToken': {'Token': 'jwt-value'},
          'Companies': [
            {'FarmId': '1', 'Type': 'Water'},
          ],
        },
      });
      expect(out['response']['accessToken']['token'], 'jwt-value');
      expect(out['response']['companies'][0]['farmId'], '1');
      expect(out['response']['companies'][0]['type'], 'Water');
    });

    test('does not alter values, only keys', () {
      final out = ApiClient.normalise({'Type': 'Poultry'});
      expect(out['type'], 'Poultry', reason: 'values must keep their casing');
    });

    test('passes scalars and nulls through unchanged', () {
      expect(ApiClient.normalise(42), 42);
      expect(ApiClient.normalise(null), isNull);
      expect(ApiClient.normalise('Text'), 'Text');
    });
  });

  group('Company', () {
    test('parses a normalised /Companies/mine row', () {
      final c = Company.fromJson({
        'farmId': 'f-1',
        'name': 'Great Favour Water',
        'type': 'Water',
        'role': 'Admin',
      });
      expect(c.farmId, 'f-1');
      expect(c.type, CompanyType.water);
      expect(c.isAdmin, isTrue);
    });

    test('maps every known company type case-insensitively', () {
      expect(companyTypeFrom('poultry'), CompanyType.poultry);
      expect(companyTypeFrom('WATER'), CompanyType.water);
      expect(companyTypeFrom('Generic'), CompanyType.generic);
      expect(companyTypeFrom('Restaurant'), CompanyType.restaurant);
      expect(companyTypeFrom('Hotel'), CompanyType.hotel);
    });

    test('an unrecognised type degrades instead of throwing', () {
      // New company types have shipped before the mobile app knew about them;
      // the UI shows an explanatory card rather than crashing.
      expect(companyTypeFrom('Warehouse'), CompanyType.unknown);
      expect(companyTypeFrom(null), CompanyType.unknown);
    });

    test('falls back to farmName when name is absent', () {
      final c = Company.fromJson({'farmId': 'f-2', 'farmName': 'Fallback', 'type': 'Hotel'});
      expect(c.name, 'Fallback');
    });
  });
}

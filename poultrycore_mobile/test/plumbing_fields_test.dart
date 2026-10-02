import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/plumbing_fields.dart';

void main() {
  // The exact record the Changes Report was printing to the client.
  final row = <String, dynamic>{
    'id': '55b4d252-d6eb-4954-a517-86a7d68699a9',
    'userId': '0abe794a-c0d8-4fe2-826e-16eaae7bdbf1',
    'userName': 'ProfowusuFarms',
    'action': 'POST',
    'resource': 'PoultryProduct',
    'details': 'POST PoultryProduct - Created',
    'data': '{"method":"POST","path":"/api/Poultry/products/ensure-defaults",'
        '"request":{"farmId":"6b888997-c36a-4462-bdb8-c0fe291f1062"},'
        '"response":{"eggProductId":65,"birdsProductId":66}}',
    'ipAddress': '34.96.62.169',
    'userAgent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/151.0.0.0',
    'timestamp': '2026-09-01T00:13:22.825461',
    'status': 'Success',
    'farmId': '6b888997-c36a-4462-bdb8-c0fe291f1062',
    'createdById': 'abc',
  };

  test('plumbing is hidden from the client', () {
    for (final k in ['id', 'userId', 'data', 'ipAddress', 'userAgent',
                     'farmId', 'createdById']) {
      expect(isPlumbingField(k, row[k]), isTrue, reason: '$k should be hidden');
    }
  });

  test('the business fields survive', () {
    for (final k in ['userName', 'action', 'resource', 'details',
                     'timestamp', 'status']) {
      expect(isPlumbingField(k, row[k]), isFalse, reason: '$k should show');
    }
  });
}

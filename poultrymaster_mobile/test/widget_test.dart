import 'package:flutter_test/flutter_test.dart';

import 'package:poultrymaster/core/json.dart';

void main() {
  test('pick reads keys case-insensitively', () {
    final map = {'FarmId': 'abc', 'totalProduction': 42};
    expect(pickString(map, ['farmId']), 'abc');
    expect(pickNum(map, ['TotalProduction']), 42);
    expect(pickBool({'IsStaff': true}, ['isStaff']), true);
  });
}

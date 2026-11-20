// Report 36 Part 4: Generic Business Features (app/generic-business-features
// + lib/generic/recommended-modules.ts) at phone width, against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/generic/generic_business_features_screen.dart';
import 'package:poultrycore_mobile/pages/generic/generic_kit.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart' show pageScreens;

import 'support/harness.dart';

final generic = Company(farmId: 'g1', name: 'Kofi Shop', type: CompanyType.generic, role: 'Admin');
const base = '/api/generic-company/g1';

Map<String, dynamic> retail({Map<String, bool> plus = const {}}) => {'farmId': 'g1', ...recommendedGenericModules('RetailBusiness')!, ...plus};

FakeApi api(Map<String, dynamic> modules) => FakeApi()
  ..gets['$base/module-settings'] = modules
  ..gets['$base/business-template'] = {'genericBusinessTemplate': 'RetailBusiness', 'genericIndustryTemplate': 'Bakery'};

void main() {
  tearDown(invalidateGenericModules);

  test('recommended sets, groups and the dependency chain, as the web', () {
    expect(recommendedGenericModules('GeneralBusiness'), recommendedGenericModules('RetailBusiness'));
    expect(recommendedGenericModules('SubscriptionServiceBusiness')!['enableProducts'], false);
    expect(recommendedGenericModules(null), isNull);
    expect([for (final g in groupedGenericFeatures()) g.$1], ['Sales & Billing', 'Inventory & Products', 'Expenses & Finance', 'Employees & Payroll']);
    final on = {for (final f in genericFeatureCatalog) f.key: true};
    expect(genericFeatureDependents('enableProducts', on), ['enableInventory', 'enableStockAdjustments', 'enableInternalUse']);
    final off = toggleGenericFeature(on, 'enableSubscriptions');
    expect((off['enableSubscriptions'], off['enableInvoices'], off['enableCustomerBalances']), (false, false, false));
    expect(toggleGenericFeature(off, 'enableSubscriptions')['enableInvoices'], false, reason: 'switching on does not switch dependents back on');
    final c = genericRestoreChanges(on, recommendedGenericModules('RetailBusiness'));
    expect(c.toEnable, isEmpty);
    expect(c.toDisable, ['enableSubscriptions', 'enableInvoices', 'enableCustomerBalances']);
    expect(pageScreens['/generic-business-features'], isNotNull);
  });

  testWidgets('switch off Products: its dependents go too, and Save sends the set without farmId', (tester) async {
    final a = api(retail());
    await open(tester, GenericBusinessFeaturesScreen(session: await sessionFor(a), company: generic), size: phone);
    expect(find.text('Business Type: Bakery'), findsOneWidget);
    expect(find.text('Recommended Configuration: Applied'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('features-save'))).onPressed, isNull, reason: 'nothing changed yet');
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('features-restore'))).onPressed, isNull, reason: 'already recommended');

    await tester.scrollUntilVisible(find.byKey(const ValueKey('feature-enableProducts')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Recommended'), findsWidgets, reason: 'a shop is recommended Products and stock, not billing');
    await tester.tap(find.byKey(const ValueKey('feature-enableProducts')));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byKey(const ValueKey('feature-enableInternalUse'))).value, false);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('features-save')), -200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('features-save')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/module-settings', 'PUT');
    expect(b.containsKey('farmId'), false);
    expect((b['enableProducts'], b['enableInventory'], b['enableStockAdjustments'], b['enablePurchases']), (false, false, false, true));
    expect(find.text('Business features saved'), findsOneWidget);
  });

  testWidgets('Restore Recommended lists what changes, then saves the recommended set', (tester) async {
    final a = api(retail(plus: {'enableSubscriptions': true, 'enableProducts': false}));
    await open(tester, GenericBusinessFeaturesScreen(session: await sessionFor(a), company: generic), size: phone);
    await tester.tap(find.byKey(const ValueKey('features-restore')));
    await tester.pumpAndSettle();
    expect(find.text('Features to enable:'), findsOneWidget);
    expect(find.text('Features to disable:'), findsOneWidget);
    expect(find.text('Subscriptions'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('features-restore-go')));
    await tester.pumpAndSettle();
    final b = a.lastBody('$base/module-settings', 'PUT');
    expect((b['enableSubscriptions'], b['enableProducts']), (false, true));
    expect(find.textContaining('Recommended features restored'), findsOneWidget);
  });
}

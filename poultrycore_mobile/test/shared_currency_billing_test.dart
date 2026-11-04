// Report 30 Part 5, the shared screens of the 26 Oct – 2 Nov pull: the
// currency symbol restored when cleared (Poultry farm setup, Water setup), and
// the billing_nav flag that shows or hides Billing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_screen.dart';
import 'package:poultrycore_mobile/pages/shared/billing_nav.dart';
import 'package:poultrycore_mobile/pages/water/water_setup_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'support/harness.dart';

final water = Company(farmId: 'farm-1', name: 'Win Water', type: CompanyType.water);

Future<void> clearSymbolAndLeave(WidgetTester tester) async {
  final box = find.descendant(of: find.byKey(const ValueKey('currency-symbol')), matching: find.byType(TextField));
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.enterText(box, '   ');
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

String symbolText(WidgetTester tester) =>
    tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('currency-symbol')), matching: find.byType(TextField))).controller!.text;

void main() {
  tearDown(() => billingNavVisible.value = true);

  group('billing_nav (use-billing-nav.ts)', () {
    test('hidden only on an explicit off; fail-open otherwise', () async {
      final a = FakeApi()..gets['/api/PlatformOps/flags/billing_nav/evaluate'] = {'enabled': false, 'matchedScope': 'Company'};
      await loadBillingNavFlag(await sessionFor(a), companyId: 'farm-1');
      expect(billingNavVisible.value, isFalse);
      expect(a.requests.last.url.queryParameters['companyId'], 'farm-1');

      final nf = FakeApi()..gets['/api/PlatformOps/flags/billing_nav/evaluate'] = {'enabled': false, 'matchedScope': 'FlagNotFound'};
      await loadBillingNavFlag(await sessionFor(nf));
      expect(billingNavVisible.value, isTrue, reason: 'a missing flag never hides Billing');

      final down = FakeApi()..statuses['/api/PlatformOps/flags/billing_nav/evaluate'] = 500;
      await loadBillingNavFlag(await sessionFor(down));
      expect(billingNavVisible.value, isTrue, reason: 'fail-open');
    });

    test('the phone menus drop the Billing rows while hidden', () {
      final groups = webNavGroups['poultry']!;
      bool hasBilling(List<NavGroup> gs) => gs.any((g) => g.subGroups.any((s) => s.links.any((l) => isBillingHref(l.href))));
      expect(hasBilling(gateBillingLinks(groups)), isTrue);
      billingNavVisible.value = false;
      expect(hasBilling(gateBillingLinks(groups)), isFalse);
      expect(gateBillingLinks(groups).any((g) => g.title == 'System'), isTrue, reason: 'the rest of System stays');
    });
  });

  group('currency symbol: cleared means the currency\'s own, never a hard-coded GHC', () {
    testWidgets('Poultry farm setup restores it on leaving the box, with the hint', (tester) async {
      final api = FakeApi()..statuses['/api/Poultry/company'] = 404;
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company));
      expect(find.text('To hide it, turn off "Show symbol on amounts".'), findsOneWidget);
      await clearSymbolAndLeave(tester);
      expect(symbolText(tester), 'GH₵');
    });

    testWidgets('Water setup restores it, with the switch hint', (tester) async {
      final api = FakeApi()
        ..statuses['/api/Water/company'] = 404
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'currencySymbol': 'GHC', 'showCurrencySymbol': true};
      await open(tester, WaterSetupScreen(session: await sessionFor(api), company: water));
      expect(find.text('Prefix rendered before amounts. e.g. GHC, ₵, \$, ₦. To hide it, turn off the switch below.'), findsOneWidget);
      await clearSymbolAndLeave(tester);
      expect(symbolText(tester), 'GH₵');
    });
  });
}

// Report 34, A2 part 1: Farm Setup (/poultry-setup) rebuilt as the web's
// app/poultry-setup/page.tsx: Production Setup / Business Setup, their tabs
// (lib/nav/poultry-setup-tabs.ts), the task bar along the bottom, Company
// settings as the first tab, and the regrouped Setup menu. At phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/poultry_setup_tabs.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/setup_embed.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

import 'package:poultrycore_mobile/design/app_theme.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import 'support/harness.dart';

bool _all(String _) => true;
bool _none(String _) => false;
bool Function(String) _except(List<String> blocked) => (k) => !blocked.contains(k);


/// A task is offered: on the bar, or folded into More (the test font is wide).
bool _offered(WidgetTester tester, String id) =>
    find.byKey(ValueKey('task-')).evaluate().isNotEmpty || find.byKey(const ValueKey('task-more')).evaluate().isNotEmpty;

/// Taps a task, through More when it was folded there.
Future<void> _tapTask(WidgetTester tester, String id, String label) async {
  final direct = find.byKey(ValueKey('task-'));
  if (direct.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('task-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
  } else {
    await tester.tap(direct);
  }
  await tester.pumpAndSettle();
}

FakeApi _farm() => FakeApi()
  ..gets['/api/Poultry/company'] = {
    'brandName': 'Gyimah Farm', 'businessType': 'Layers', 'housingSystem': 'DeepLitter',
    'defaultCurrency': 'GHS', 'defaultCrateEggCount': 30,
  }
  ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'currencySymbol': 'GHC', 'showCurrencySymbol': true}
  ..gets['/api/Poultry/vehicles'] = [
    {'poultryVehicleId': 3, 'vehicleName': 'Truck 1', 'vehicleType': 'Truck', 'capacityCrates': 12, 'status': 'Active'},
  ];

void main() {
  // ------------------------------------------------- poultry-setup-tabs.test.ts
  group('resolveSetupLocation (the web\'s cases)', () {
    test("the bare route opens Production's first tab", () {
      expect(resolveSetupLocation(allowed: _all), const SetupAt(SetupSection.production, 'company-settings'));
    });
    test("section alone opens that section's first tab", () {
      expect(resolveSetupLocation(section: 'business', allowed: _all), const SetupAt(SetupSection.business, 'customers'));
    });
    test('an explicit deep link', () {
      expect(resolveSetupLocation(section: 'production', tab: 'egg-settings', allowed: _all),
          const SetupAt(SetupSection.production, 'egg-settings'));
    });
    test("the tab's own section wins over a mismatched section", () {
      expect(resolveSetupLocation(section: 'production', tab: 'customers', allowed: _all), const SetupAt(SetupSection.business, 'customers'));
    });
    test('an unknown tab falls back safely', () {
      expect(resolveSetupLocation(section: 'business', tab: 'nonsense', allowed: _all), const SetupAt(SetupSection.business, 'customers'));
    });
    test('never a tab the user may not see', () {
      expect(resolveSetupLocation(tab: 'financial-settings', allowed: _except(['financial-settings', 'company-settings'])),
          const SetupAt(SetupSection.production, 'houses'));
    });
    test('Business when no Production tab is allowed', () {
      expect(resolveSetupLocation(section: 'production', allowed: (k) => sectionOfTab(k) == SetupSection.business),
          const SetupAt(SetupSection.business, 'customers'));
    });
    test('no access when nothing is allowed', () {
      expect(resolveSetupLocation(tab: 'houses', allowed: _none), isA<SetupNone>());
    });
    test('the old step links', () {
      expect(resolveSetupLocation(step: 'company', allowed: _all), const SetupAt(SetupSection.production, 'company-settings'));
      expect(resolveSetupLocation(step: 'flocks', allowed: _all), const SetupAt(SetupSection.production, 'flock-groups'));
      expect(resolveSetupLocation(step: 'raw-materials', allowed: _all), const SetupAt(SetupSection.production, 'inventory'));
      expect(resolveSetupLocation(step: 'vehicles', allowed: _all), const SetupAt(SetupSection.business, 'vehicles'));
      expect(resolveSetupLocation(step: 'employees', allowed: _all), const SetupRedirect('/employees'));
    });
    test('tab over a legacy step', () {
      expect(resolveSetupLocation(tab: 'products', step: 'customers', allowed: _all), const SetupAt(SetupSection.production, 'products'));
    });
    test('the old profile tabs go to Company settings', () {
      for (final tab in ['farm-profile', 'company-profile']) {
        expect(resolveSetupLocation(section: 'business', tab: tab, allowed: _all), const SetupAt(SetupSection.production, 'company-settings'));
      }
    });
    test('Delivery opens on Drivers', () {
      expect(resolveSetupLocation(tab: 'delivery', allowed: _all), const SetupAt(SetupSection.business, 'drivers'));
    });
    test('the canonical link, and every tab has one section and a description', () {
      expect(setupHref(SetupSection.production, 'flock-groups'), '/poultry-setup?section=production&tab=flock-groups');
      final keys = [for (final s in setupSections.values) ...s.tabs.map((t) => t.key)];
      expect(keys.toSet().length, keys.length);
      for (final s in setupSections.values) {
        for (final t in s.tabs) {
          expect(t.description.length, greaterThan(10));
        }
      }
      expect(resolveSetupHref('/poultry-setup?section=business&tab=staff', allowed: _all), const SetupAt(SetupSection.business, 'staff'));
    });
    test('every tab but Company settings has a screen in the app', () {
      for (final s in setupSections.values) {
        for (final t in s.tabs) {
          if (t.key == 'company-settings') continue;
          final r = setupTabRoutes[t.key];
          expect(r, isNotNull, reason: t.key);
          expect(pageScreens[r!.$1] != null || r.$2 != null, isTrue, reason: t.key);
        }
      }
    });
  });

  // ------------------------------------------------------------- the menu
  group('the Setup menu (9 Nov regrouping)', () {
    test('Farm | Finance | Production | Company | Delivery | People, with the new rows and names', () {
      final setup = webNavGroups['poultry']!.firstWhere((g) => g.title == 'Setup');
      expect([for (final s in setup.subGroups) s.title], ['Farm', 'Finance', 'Production', 'Company', 'Delivery', 'People']);
      List<String> rows(String sub) => [for (final l in setup.subGroups.firstWhere((s) => s.title == sub).links) l.label];
      expect(rows('Farm'), ['Houses', 'Flock Groups', 'Flock Purchases (Batches)']);
      expect(rows('Finance'), ['Customers', 'Suppliers', 'Financial Settings']);
      expect(rows('Production'), ['Products', 'Feed Formulas', 'Egg Settings']);
      expect(rows('Company'), ['Production Setup', 'Business Setup', 'Companies']);
      final hrefs = [for (final s in setup.subGroups) ...s.links.map((l) => l.href)];
      expect(hrefs, isNot(contains('/poultry-company-setup')));
      for (final h in ['/poultry-setup?section=production', '/poultry-setup?section=business']) {
        expect(hrefs, contains(h));
        expect(pageScreens[h], isNotNull, reason: h);
      }
      final system = webNavGroups['poultry']!.firstWhere((g) => g.title == 'System');
      expect(system.subGroups.expand((s) => s.links).map((l) => l.label), contains('Support Videos'));
    });
  });

  // ------------------------------------------------------------- the page
  group('Farm Setup page', () {
    testWidgets('opens on Production Setup → Company settings, in four sections, Save on the task bar', (tester) async {
      final api = _farm();
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('Farm Setup'), findsOneWidget);
      expect(find.text('Production Setup'), findsOneWidget);
      expect(find.text('Business Setup'), findsOneWidget);
      expect(find.text('Company settings'), findsOneWidget);
      expect(find.byKey(const ValueKey('setup-tab-description')), findsOneWidget);
      expect(find.text('Your business name and contacts, farm type and capacity, currency and business time zone.'), findsOneWidget);
      for (final s in ['Business profile', 'Farm details', 'Currency & time zone']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }

      // Nothing changed yet: Save is there but off, Discard is not.
      final save = find.descendant(of: find.byKey(const ValueKey('setup-task-bar')), matching: find.byKey(const ValueKey('task-save')));
      expect(save, findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(_offered(tester, 'discard'), isFalse);
      expect(find.byKey(const ValueKey('setup-reload')), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Gyimah Farm'), 'Gyimah Poultry');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      expect(_offered(tester, 'discard'), isTrue);

      // Leaving the tab asks first; Cancel stays put.
      await tester.ensureVisible(find.text('Houses & pens'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Houses & pens'));
      await tester.pumpAndSettle();
      expect(find.text('You have unsaved changes on this tab. Leave without saving them?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Business profile'), findsOneWidget);

      await tester.tap(save);
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/company', 'PUT');
      expect((body['brandName'], body['defaultCurrency']), ('Gyimah Poultry', 'GHS'));
      expect(api.writes.any((w) => w.url.path == '/api/Water/farm-settings/currency'), isTrue);
      expect(find.text('Company settings saved'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'saved: nothing unsaved any more');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Discard puts the form back', (tester) async {
      await open(tester, FarmSetupScreen(session: await sessionFor(_farm()), company: company), size: phone);
      await tester.enterText(find.widgetWithText(TextFormField, 'Gyimah Farm'), 'Changed');
      await tester.pumpAndSettle();
      await _tapTask(tester, 'discard', 'Discard');
      expect(find.widgetWithText(TextFormField, 'Gyimah Farm'), findsOneWidget);
      expect(_offered(tester, 'discard'), isFalse);
    });

    testWidgets('the server refusing the Water-only currency route still saves the company', (tester) async {
      final api = _farm()
        ..statuses['/api/Water/farm-settings'] = 403
        ..writeStatuses['/api/Water/farm-settings/currency'] = 403;
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company), size: phone);
      await tester.enterText(find.widgetWithText(TextFormField, 'Gyimah Farm'), 'Gyimah Poultry');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-save')));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Poultry/company', 'PUT')['defaultCurrency'], 'GHS');
      expect(find.textContaining('Save failed'), findsNothing);
      expect(find.textContaining('Currency not applied app-wide'), findsOneWidget);
    });

    testWidgets('Business Setup: a list tab drops its title, its buttons go on the task bar', (tester) async {
      final api = _farm();
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company, href: '/poultry-setup?section=business'),
          size: phone);
      expect(find.text('Customers'), findsWidgets);
      expect(find.text('Manage customer details used in sales and payments.'), findsOneWidget);

      await tester.ensureVisible(find.text('Delivery Vehicles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delivery Vehicles'));
      await tester.pumpAndSettle();
      expect(find.text('Truck 1'), findsOneWidget);
      expect(find.text('Manage the vehicles your eggs are loaded onto for delivery.'), findsOneWidget);
      // The page's own header and Add button are not drawn in the tab…
      expect(find.byType(AppBar), findsOneWidget, reason: "only Farm Setup's own");
      // …the Add button is on the task bar, and opens the page's form.
      final add = find.descendant(of: find.byKey(const ValueKey('setup-task-bar')), matching: find.byKey(const ValueKey('task-add')));
      expect(add, findsOneWidget);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Vehicle name'), findsWidgets, reason: 'the Vehicles page form');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back to Production Setup through its radio.
      await tester.tap(find.byKey(const ValueKey('setup-section-production')));
      await tester.pumpAndSettle();
      expect(find.text('Business profile'), findsOneWidget);
    });

    testWidgets('Reload remounts the tab and fetches it again', (tester) async {
      final api = _farm();
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company, href: '/poultry-setup?tab=vehicles'), size: phone);
      final before = api.requests.where((r) => r.url.path == '/api/Poultry/vehicles').length;
      await tester.tap(find.byKey(const ValueKey('setup-reload')));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.url.path == '/api/Poultry/vehicles').length, greaterThan(before));
    });

    testWidgets('the task bar folds what does not fit into More', (tester) async {
      tester.view.physicalSize = const Size(320, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tapped = '';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskBarRow(dark: true, tasks: [
            SetupTask(id: 'a', label: 'Add something long', primary: true, onTap: () => tapped = 'a'),
            SetupTask(id: 'b', label: 'Add several things at once', onTap: () => tapped = 'b'),
            SetupTask(id: 'c', label: 'Export the whole list', onTap: () => tapped = 'c'),
            const SetupTask(id: 'd', label: 'Hidden', hidden: true),
          ]),
        ),
      ));
      expect(find.text('Add something long'), findsOneWidget, reason: 'the primary stays');
      expect(find.byKey(const ValueKey('task-more')), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('task-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export the whole list').last);
      await tester.pumpAndSettle();
      expect(tapped, 'c');
    });
  });

  // Switching the phone between light and dark on this page used to break it
  // (rounded boxes threw while painting; const boxes stayed light).
  for (final href in ['/poultry-setup?section=production', '/poultry-setup?section=business']) {
    testWidgets('switching light / dark on $href paints cleanly', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(() => Tone.dark = false);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      final s = await sessionFor(_farm());
      await tester.pumpWidget(FollowPhoneBrightness(
        builder: (context, dark) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: FarmSetupScreen(session: s, company: company, href: href),
        ),
      ));
      await tester.pumpAndSettle();
      for (final b in [Brightness.dark, Brightness.light, Brightness.dark]) {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'switching to $b');
        expect(Tone.dark, b == Brightness.dark);
      }
    });
  }
}

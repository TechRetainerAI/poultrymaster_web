// Poultry → Setup → Company: Company Setup, Financial Settings, Companies
// and the Farm Setup hub, driven against a fake API.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/lookup_loader.dart';
import 'package:poultrycore_mobile/pages/poultry/company_setup_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/financial_settings_screen.dart';
import 'package:poultrycore_mobile/pages/shared/companies_screen.dart';
import 'package:poultrycore_mobile/pages/shared/company_timezone_field.dart';

import 'support/harness.dart';

const _zones = [
  {'timeZoneId': 'Africa/Accra', 'utcOffset': '+00:00', 'isDst': false},
  {'timeZoneId': 'Africa/Lagos', 'utcOffset': '+01:00', 'isDst': false},
];

/// Picks [option] from the searchable sheet the field showing [shown] opens.
Future<void> search(WidgetTester tester, String shown, String query, String option) async {
  await tester.tap(find.text(shown));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(LookupLoader.clear);

  group('Company Setup', () {
    testWidgets('first time: every dropdown works, and setting up also moves the farm currency',
        (tester) async {
      final api = FakeApi()
        ..statuses['/api/Poultry/company'] = 404
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'showCurrencySymbol': true}
        ..gets['/api/CompanyTime/zones'] = _zones;
      await open(tester, PoultryCompanySetupScreen(session: await sessionFor(api), company: company));

      expect(find.text('Set up Poultry Company'), findsOneWidget);
      await pick(tester, 'Layers', 'Broilers');
      await pick(tester, 'Deep litter', 'Battery cage');
      await search(tester, 'GHC', 'naira', 'NGN — Nigerian Naira (₦)');
      expect(find.text('NGN — Nigerian Naira (₦)'), findsOneWidget);

      await tester.tap(find.text('Set up Poultry Company'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/company/setup');
      expect(body['businessType'], 'Broilers');
      expect(body['housingSystem'], 'BatteryCage');
      expect(body['defaultCurrency'], 'NGN');
      expect(body['defaultCrateEggCount'], 30);
      expect(body['farmId'], 'farm-1');
      final cur = api.lastBody('/api/Water/farm-settings/currency', 'PUT');
      expect(cur['currencyCode'], 'NGN');
      expect(cur['currencySymbol'], '₦');
    });

    testWidgets('set up: an older lowercase value still shows, and saving updates in place',
        (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/company'] = {
          'brandName': 'Gyimah Farm', 'businessType': 'broilers', 'housingSystem': 'freerange',
          'defaultCurrency': 'GHS', 'defaultCrateEggCount': 30,
        }
        ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS'}
        ..gets['/api/CompanyTime/zones'] = _zones;
      await open(tester, PoultryCompanySetupScreen(session: await sessionFor(api), company: company));
      expect(find.text('Broilers'), findsOneWidget);
      expect(find.text('Free range'), findsOneWidget);
      expect(find.text('✓ Set up'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/Poultry/company', 'PUT')['housingSystem'], 'FreeRange');
      expect(api.writes.where((w) => w.url.path.endsWith('/currency')), isEmpty,
          reason: 'same currency: the farm row is left alone');
    });
  });

  group('Business timezone', () {
    testWidgets('an unconfirmed guess can be confirmed; a new zone saves on its own', (tester) async {
      final api = FakeApi()
        ..gets['/api/CompanyTime/context'] = {
          'timeZoneId': 'Africa/Accra', 'timeZoneConfirmed': false, 'businessDate': '2026-10-02',
        }
        ..gets['/api/CompanyTime/zones'] = _zones;
      final s = await sessionFor(api);
      await open(tester, Scaffold(body: ListView(children: [CompanyTimeZoneField(session: s, company: company)])));
      expect(find.text('Confirm timezone'), findsOneWidget);
      expect(find.textContaining('guessed from your currency'), findsOneWidget);

      await search(tester, 'Africa/Accra (+00:00)', 'lagos', 'Africa/Lagos (+01:00)');
      await tester.tap(find.text('Save timezone'));
      await tester.pumpAndSettle();
      expect(api.lastBody('/api/CompanyTime/timezone', 'PUT')['timeZoneId'], 'Africa/Lagos');
    });
  });

  group('Financial Settings', () {
    testWidgets('Save waits for a real change; deferring shows both warnings', (tester) async {
      final api = FakeApi()
        ..gets['/api/Poultry/financial-settings/cost-recognition'] = {
          'feedCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
          'medicationCostRecognitionMethod': 'EXPENSE_WHEN_PURCHASED',
          'isConfigured': false,
        };
      await open(tester, FinancialSettingsScreen(session: await sessionFor(api), company: company));
      expect(find.textContaining('Nobody has set this up yet'), findsOneWidget);
      expect(find.text('Discard'), findsNothing);

      await tester.tap(find.text('Expense when consumed').first); // Feed
      await tester.pumpAndSettle();
      expect(find.textContaining('This applies to new purchases from now on'), findsOneWidget);
      expect(find.textContaining('A deferred purchase holds its cost'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Poultry/financial-settings/cost-recognition', 'PUT');
      expect(body['feedCostRecognitionMethod'], 'EXPENSE_WHEN_CONSUMED');
      expect(body['medicationCostRecognitionMethod'], 'EXPENSE_WHEN_PURCHASED');
      expect(body['effectiveFromDate'], null);
      expect(body['updatedBy'], 'user-1');
    });
  });

  group('Companies', () {
    testWidgets('the active company is called out; the others can be switched to', (tester) async {
      final api = FakeApi()
        ..gets['/api/Companies/mine'] = [
          {'farmId': 'farm-1', 'name': 'Test Farm', 'type': 'Poultry', 'role': 'Admin', 'createdAt': '2026-09-01T10:00:00Z'},
          {'farmId': 'farm-2', 'name': 'Cool Spring', 'type': 'Water', 'role': 'Admin'},
        ];
      await open(tester, CompaniesScreen(session: await sessionFor(api), company: company));
      expect(find.text('✓ Active'), findsOneWidget);
      expect(find.text('You are working in this company.'), findsOneWidget);
      expect(find.text('Switch to this company'), findsOneWidget);
    });

    testWidgets('new company: the business type decides the company type', (tester) async {
      final api = FakeApi();
      await open(tester, CompaniesScreen(session: await sessionFor(api), company: company));
      await tester.tap(find.text('New company'));
      await tester.pumpAndSettle();
      // A template business says it will be set up for you...
      await pick(tester, 'Water production', 'Gym / fitness centre');
      expect(find.textContaining("We'll set up the right menus"), findsOneWidget);
      // ...and goes on to the (web) setup wizard, which a widget test cannot
      // render, so the create itself is checked with a non-template type.
      await pick(tester, 'Gym / fitness centre', 'Hotel');
      expect(find.textContaining("We'll set up the right menus"), findsNothing);
      await enter(tester, 'Company name', 'Lake View Hotel');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      final body = api.lastBody('/api/Companies');
      expect(body['Name'], 'Lake View Hotel');
      expect(body['Type'], 'Hotel');
    });
  });

  group('Farm Setup hub', () {
    testWidgets('opens on Company; an area lists, adds and deletes through the page itself',
        (tester) async {
      final api = FakeApi()
        ..statuses['/api/Poultry/company'] = 404
        ..gets['/api/Poultry/vehicles'] = [
          {'poultryVehicleId': 3, 'vehicleName': 'Truck 1', 'vehicleType': 'Truck', 'capacityCrates': 12, 'status': 'Active'},
        ];
      await open(tester, FarmSetupScreen(session: await sessionFor(api), company: company));
      expect(find.text('Set up Poultry Company'), findsOneWidget, reason: 'Company is the first tab');
      expect(find.text('Show symbol on amounts'), findsOneWidget);

      await tester.tap(find.text('Vehicles'));
      await tester.pumpAndSettle();
      expect(find.text('Truck 1'), findsOneWidget);
      expect(find.text('12 crates'), findsOneWidget);

      await tester.tap(find.text('Add vehicle'));
      await tester.pumpAndSettle();
      expect(find.text('Vehicle name'), findsOneWidget, reason: 'the Vehicles page form');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete vehicle?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Poultry/vehicles/3'), isTrue);
    });
  });
}


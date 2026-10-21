// Restaurant → Menu & Setup (2026-10-20): Staff, Menu Items and Restaurant
// Setup as the web pages, against a fake API at phone width.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_menu_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_setup_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_staff_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  test('Menu & Setup rows open native screens', () {
    for (final h in ['/restaurant-menu', '/restaurant-staff', '/restaurant-setup']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(menuMargin(10, 3), 70);
    expect(menuMargin(10, 0), isNull);
  });

  testWidgets('Staff: counts, role cards filter, Employee badge, owes, permissions, delete', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/staff'] = [
        {'restaurantStaffId': 1, 'firstName': 'Kojo', 'lastName': 'Asante', 'phone': '020', 'role': 'Waiter', 'salaryType': 'Monthly', 'basePay': 900, 'isActive': true},
        {'restaurantStaffId': 2, 'firstName': 'Abla', 'lastName': 'Doe', 'phone': '024', 'email': 'a@x.com', 'role': 'Chef', 'salaryType': 'Weekly', 'basePay': 0, 'isActive': false},
      ]
      ..gets['/api/Restaurant/staff-loans/staff-report'] = [
        {'restaurantStaffId': 1, 'outstanding': 150},
      ]
      ..gets['/api/StaffUserLink'] = [
        {'staffId': 2, 'userId': 'u-2'},
      ];
    await open(tester, RestaurantStaffScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('2 team members across 2 roles'), findsOneWidget);
    expect(find.text('owes 150.00'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.byTooltip('Make employee (give a login)'), findsOneWidget, reason: 'only the unlinked one');

    // A role card filters the list; tapping it again clears it.
    // The role card comes first; the same label is in Roles & Permissions below.
    await tester.tap(find.text('Chef / Cook').first);
    await tester.pumpAndSettle();
    expect(find.text('1 staff (Chef)'), findsOneWidget);
    expect(find.text('Kojo Asante'), findsNothing);
    await tester.tap(find.text('Chef / Cook').first);
    await tester.pumpAndSettle();
    expect(find.text('2 staff '), findsOneWidget);

    // A role in Roles & Permissions opens its Permissions dialog.
    // Waiter / Server is also the role card above and Kojo's badge below.
    await tester.tap(find.text('Waiter / Server').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Waiter / Server — Permissions'), findsOneWidget);
    expect(find.text('Allowed'), findsNWidgets(3));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    final d = api.writes.last;
    expect((d.method, d.url.path, d.url.queryParameters['farmId']), ('DELETE', '/api/Restaurant/staff/1', 'farm-1'));
  });

  testWidgets('Menu: stats, 86, a new item with a typed name and category, combos', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/menu/categories'] = [
        {'menuCategoryId': 3, 'name': 'Mains', 'isActive': true},
      ]
      ..gets['/api/Restaurant/menu/items'] = [
        {'menuItemId': 7, 'name': 'Jollof', 'menuCategoryId': 3, 'categoryName': 'Mains', 'price': 50, 'costPrice': 20, 'isAvailable': true, 'isVegan': true, 'spicyLevel': 2},
        {'menuItemId': 8, 'name': 'Kenkey', 'price': 30, 'costPrice': 0, 'isAvailable': false},
      ]
      ..gets['/api/Restaurant/menu/combos'] = [
        {'comboId': 4, 'name': 'Family Deal', 'price': 120, 'isActive': true},
      ]
      ..gets['/api/Restaurant/menu/combos/4/items'] = [
        {'comboItemId': 9, 'quantity': 2, 'menuItemName': 'Jollof'},
      ]
      ..gets['/api/Hotel/setup/menu-category-types'] = []
      ..gets['/api/Restaurant/menu/item-names'] = [
        {'restaurantMenuItemNameId': 1, 'description': 'Waakye', 'category': 'Mains'},
        {'restaurantMenuItemNameId': 2, 'description': 'Other', 'category': 'Other'},
      ]
      ..gets['/api/Restaurant/inventory/ingredients'] = []
      ..writeAnswers['/api/Restaurant/menu/categories'] = {'menuCategoryId': 5};
    await open(tester, RestaurantMenuScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('2 items across 1 categories'), findsOneWidget);
    expect(find.text("86'd — Unavailable"), findsOneWidget);
    expect(find.text('🌱 Vegan'), findsOneWidget);
    expect(find.text(' 60%', findRichText: true), findsNothing);
    expect(find.textContaining('60%', findRichText: true), findsOneWidget, reason: 'margin on 50 / 20');

    await tester.tap(find.byTooltip("Mark 86'd"));
    await tester.pumpAndSettle();
    final p = api.writes.last;
    expect((p.method, p.url.path, p.url.queryParameters['isAvailable']), ('PATCH', '/api/Restaurant/menu/items/7/availability', 'false'));

    // New item: "Other" name, a new category typed inline, a dietary option.
    await tester.tap(find.text('Add Menu Item'));
    await tester.pumpAndSettle();
    expect(find.text('Save the item first, then edit it to define the recipe/ingredients.'), findsOneWidget);
    await tester.tap(find.text('Select or type a name'));
    await tester.pumpAndSettle();
    expect(find.text('Waakye (Mains)'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget, reason: "the lookup's own Other is folded into one row");
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Type item name'), 'Banku');
    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ New category…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Type a new category'), 'Sides');
    await tapText(tester, '☪️ Halal');
    await tapText(tester, 'Add Item');
    final cat = api.lastBody('/api/Restaurant/menu/categories');
    expect((cat['name'], cat['isActive']), ('Sides', true));
    final item = api.lastBody('/api/Restaurant/menu/items');
    expect((item['name'], item['menuCategoryId'], item['isHalal'], item['isAvailable']), ('Banku', 5, true, true));
    final name = api.lastBody('/api/Restaurant/menu/item-names');
    expect((name['description'], name['category']), ('Banku', 'Sides'));

    // Combos: expand, then add an item.
    await tapText(tester, 'Combos');
    await tapText(tester, 'Family Deal');
    expect(find.text('2x'), findsOneWidget);
    await tapText(tester, 'Add item to combo');
    await tapText(tester, 'Add to Combo');
    final ci = api.lastBody('/api/Restaurant/menu/combos/4/items');
    expect((ci['menuItemId'], ci['quantity'], ci['sortOrder']), (7, 1, 0));
  });

  testWidgets('Setup: profile with services and a typed cuisine, a schedule, a modifier', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/setup/profile'] = {
        'restaurantName': 'Rose Bistro', 'serviceTypes': 'DineIn', 'defaultCurrency': 'GHS', 'taxRate': 0, 'serviceChargeRate': 0, 'seatingCapacity': 40,
      }
      ..gets['/api/Restaurant/menu/schedules'] = []
      ..gets['/api/Restaurant/menu/modifier-groups'] = [
        {'modifierGroupId': 6, 'name': 'Choose Size', 'isRequired': true, 'minSelections': 1, 'maxSelections': 1, 'isActive': true},
      ]
      ..gets['/api/Restaurant/menu/modifiers'] = [
        {'modifierId': 1, 'modifierGroupId': 6, 'name': 'Large', 'priceAdjustment': 5, 'isDefault': true, 'isAvailable': true},
      ]
      ..gets['/api/Restaurant/custom-options'] = []
      ..gets['/api/Water/farm-settings'] = {'currencyCode': 'GHS', 'showCurrencySymbol': true};
    await open(tester, RestaurantSetupScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Rose Bistro'), findsOneWidget);

    await tapText(tester, 'Takeaway');
    await tester.tap(find.text('Select cuisine type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other (type your own)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Type your own'), 'Ghanaian');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    final prof = api.lastBody('/api/Restaurant/setup/profile');
    expect((prof['serviceTypes'], prof['cuisineType'], prof['seatingCapacity'], prof['farmId']), ('DineIn,Takeaway', 'Ghanaian', 40, 'farm-1'));
    final opt = api.lastBody('/api/Restaurant/custom-options');
    expect((opt['listKey'], opt['value']), ('CuisineType', 'Ghanaian'));
    expect(api.writes.where((w) => w.url.path == '/api/Water/farm-settings/currency'), isEmpty, reason: 'the currency did not change');

    await tapText(tester, 'Menu Schedules');
    await tapText(tester, 'Add Schedule');
    await tester.tap(find.text('Select a schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Sun');
    await tapText(tester, 'Create Schedule');
    final sch = api.lastBody('/api/Restaurant/menu/schedules');
    expect((sch['name'], sch['startTime'], sch['endTime'], sch['daysOfWeek']), ('Lunch', '06:00', '11:00', 'Mon,Tue,Wed,Thu,Fri,Sat'));

    await tapText(tester, 'Modifiers');
    expect(find.text('Select 1 option'), findsOneWidget);
    expect(find.text('+5.00'), findsOneWidget);
    await tapText(tester, 'Add option');
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Large, Extra Cheese, Spicy'), 'Small');
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '-2');
    await tapText(tester, 'Add Option');
    final mod = api.lastBody('/api/Restaurant/menu/modifiers');
    expect((mod['modifierGroupId'], mod['name'], mod['priceAdjustment'], mod['isAvailable']), (6, 'Small', -2, true));
    expect(jsonEncode(mod).contains('isDefault'), isTrue);
  });
}

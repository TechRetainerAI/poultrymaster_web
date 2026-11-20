// Restaurant images and the Kitchen Display Exit button (2026-10-22): menu
// pictures saved by the web as data URIs must show on POS and QR / Customer
// Order, the cards must fit on a wide phone with larger text, and Exit must be
// readable on the dark header.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_kds_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_order_online_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_pos_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
const phone = Size(430, 1400);

final memoryImages = find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);

void largerText(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = 1.15;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('POS shows a data-URI menu image and the tile fits', (tester) async {
    largerText(tester);
    final api = FakeApi()
      ..gets['/api/Restaurant/menu/items'] = [
        {'menuItemId': 11, 'name': 'Jollof', 'price': 10, 'categoryName': 'Mains', 'isAvailable': true, 'isActive': true, 'prepTime': 15, 'imageUrl': png},
        {'menuItemId': 12, 'name': 'Sobolo', 'price': 3, 'isAvailable': true, 'isActive': true},
      ];
    await open(tester, RestaurantPosScreen(session: await sessionFor(api), company: rest), size: phone);
    expect(memoryImages, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR / Customer Order shows the image and the card fits with the quantity stepper', (tester) async {
    largerText(tester);
    final api = FakeApi()
      ..gets['/api/Restaurant/public/farm-1/settings'] = {'isEnabled': true, 'acceptingOrders': true, 'allowTakeaway': true, 'allowDelivery': true}
      ..gets['/api/Restaurant/public/farm-1/categories'] = [
        {'menuCategoryId': 1, 'name': 'Mains'},
      ]
      ..gets['/api/Restaurant/public/farm-1/menu'] = [
        {'menuItemId': 11, 'name': 'Jollof', 'price': 8, 'categoryId': 1, 'prepTime': 15, 'spicyLevel': 2, 'imageUrl': png},
        {'menuItemId': 12, 'name': 'Spring Rolls', 'description': 'Spring Rolls is Appetizers', 'price': 3, 'categoryId': 1, 'prepTime': 30},
      ]
      ..gets['/api/Restaurant/public/farm-1/profile'] = {'restaurantName': 'Rose Bistro', 'logoUrl': png};
    await open(tester, RestaurantOrderOnlineScreen(session: await sessionFor(api), company: rest), size: phone);
    expect(memoryImages, findsNWidgets(2), reason: 'the logo and the Jollof card');
    for (final name in ['Jollof', 'Spring Rolls']) {
      await tester.tap(find.byTooltip('Add $name to your order').last);
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Remove one Jollof'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kitchen Display Exit is see-through, not a white box', (tester) async {
    await open(tester, RestaurantKdsScreen(session: await sessionFor(FakeApi()), company: rest), size: phone);
    final exit = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Exit'));
    expect(exit.style!.backgroundColor!.resolve({}), Colors.transparent);
  });
}

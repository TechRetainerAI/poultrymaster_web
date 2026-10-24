// Restaurant → Delivery & Online (2026-10-21): Online Settings, Drivers &
// Dispatch and the QR / Customer Order page, against a fake API at phone
// width.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/config/env.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/report_export.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_delivery_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_online_settings_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_order_online_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_qr.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(360, 3200);

Finder filled(String t) => find.widgetWithText(FilledButton, t);

/// The box under [label] (the rField / rLabel column), last one on screen.
Future<void> enterUnder(WidgetTester tester, String label, String text) async {
  final l = find.byWidgetPredicate((w) => w is Text && RegExp('^${RegExp.escape(label)}' r'( \*)?$').hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''));
  final box = find.descendant(of: find.ancestor(of: l.last, matching: find.byType(Column)).first, matching: find.byType(EditableText));
  await tester.enterText(box.first, text);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  test('routes, the QR link, QR modules, the PDF and the small helpers', () async {
    for (final h in ['/restaurant-online-orders', '/restaurant-order-online', '/restaurant-delivery']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    expect(buildQrOrderUrl('a b', 'order.example.com/'), 'https://order.example.com/restaurant-order-online?qr=a%20b');
    expect(buildQrOrderUrl('T1'), '${Env.webBase}/restaurant-order-online?qr=T1');
    expect(qrModules('https://x.test/restaurant-order-online?qr=T1', 200), isNotEmpty);
    final pdf = await qrCardsPdf([
      {'qrCodeId': 1, 'qrToken': 'T1', 'codeType': 'Restaurant'},
      {'qrCodeId': 2, 'qrToken': 'T2', 'tableNumber': '4'},
    ], restaurantName: 'Rose Bistro');
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(promoValueLabel({'discountType': 'Percentage', 'discountValue': 10}), '10%');
    expect(promoValueLabel({'discountType': 'FixedAmount', 'discountValue': 5}), '5.00');
    expect(promoValueLabel({'discountType': 'FreeDelivery', 'discountValue': 0}), 'Free Delivery');
    final pending = pendingDeliveryOrders([
      {'orderId': 1, 'orderType': 'Delivery', 'status': 'Placed'},
      {'orderId': 2, 'orderType': 'Delivery', 'status': 'Completed'},
      {'orderId': 3, 'orderType': 'DineIn', 'status': 'Placed'},
      {'orderId': 4, 'orderType': 'Delivery', 'status': 'Ready'},
    ], [
      {'orderId': 4},
    ]);
    expect(pending.map((o) => o['orderId']), [1]);
    expect(openState('09:00', '17:00', DateTime(2026, 1, 1, 12))?.open, isTrue);
    expect(openState('22:00', '02:00', DateTime(2026, 1, 1, 1))?.open, isTrue, reason: 'past midnight wraps');
    expect(openState('22:00', '02:00', DateTime(2026, 1, 1, 12))?.open, isFalse);
    expect(openState('', '17:00'), isNull);
    expect(makeMoney(null)(20), '20.00');
    expect(makeMoney('xx')(3.5), '3.50');
  });

  testWidgets('Online Settings: pause, save settings, create the venue QR, copy, print, promos', (tester) async {
    final shared = <String>[];
    ReportExport.sharer = (name, bytes, mime, subject) async => shared.add(name);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    final api = FakeApi()
      ..gets['/api/Restaurant/online/settings'] = {
        'isEnabled': true, 'allowDineInQr': true, 'allowTakeaway': true, 'allowDelivery': false, 'minOrderAmount': 5,
        'slotDurationMins': 30, 'deliveryFeeType': 'Fixed', 'deliveryFeeAmount': 2, 'acceptingOrders': true, 'publicBaseUrl': 'order.rose.test',
      }
      ..gets['/api/Restaurant/online/qr-codes'] = [
        {'qrCodeId': 7, 'qrToken': 'TOK7', 'tableNumber': '4', 'codeType': 'Table', 'isActive': true, 'scanCount': 1},
      ]
      ..gets['/api/Restaurant/online/promo-codes'] = [
        {'promoCodeId': 3, 'code': 'SAVE10', 'description': 'Ten off', 'discountType': 'Percentage', 'discountValue': 10,
          'currentUses': 2, 'maxUses': 0, 'isActive': true, 'channelRestriction': 'QR'},
      ]
      ..gets['/api/Restaurant/setup/profile'] = {'restaurantName': 'Rose Bistro'};
    await open(tester, RestaurantOnlineSettingsScreen(session: await sessionFor(api), company: rest), size: tall);

    // Pause orders.
    await tester.tap(filled('Accepting Orders'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/online/settings/toggle', 'PATCH'), {'accepting': false, 'reason': 'Paused by staff'});
    expect(filled('Orders Paused'), findsOneWidget);

    // Settings: tick Delivery, change the minimum, pick a fee type, save.
    await tester.tap(find.text('Allow Delivery'));
    await tester.pump();
    await enterUnder(tester, 'Min Order Amount', '12.5');
    await enterUnder(tester, 'Free Delivery Above', '50');
    await pick(tester, 'Fixed', 'Distance Based');
    await enterUnder(tester, 'Welcome Message', 'Hello!');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
    final s = api.lastBody('/api/Restaurant/online/settings');
    expect((s['allowDelivery'], s['minOrderAmount'], s['freeDeliveryAbove'], s['deliveryFeeType'], s['welcomeMessage'], s['farmId'], s['acceptingOrders']),
        (true, 12.5, 50, 'DistanceBased', 'Hello!', 'farm-1', false));
    expect(s['estimatedPrepMinsDine'], 15, reason: 'the default when the server had none');

    // QR Codes tab.
    await tester.tap(find.text('QR Codes (1)'));
    await tester.pumpAndSettle();
    expect(find.text('TABLE'), findsOneWidget);
    expect(find.text('1 scan'), findsOneWidget);
    await tapText(tester, 'Create it');
    expect(api.lastBody('/api/Restaurant/online/qr-codes'), {'codeType': 'Restaurant', 'tableId': null, 'tableNumber': null});
    await tapText(tester, 'Copy link');
    expect(copied, 'https://order.rose.test/restaurant-order-online?qr=TOK7');
    await tester.runAsync(() async {
      await tester.tap(find.text('Print').first);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();
    expect(shared, ['qr-cards.pdf']);
    await tester.tap(find.byTooltip('Delete QR'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Restaurant/online/qr-codes/7'), isTrue);

    // Promo Codes tab: the row, then a new fixed-amount QR-only promo.
    await tester.tap(find.text('Promo Codes (1)'));
    await tester.pumpAndSettle();
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('Ten off | Uses: 2/∞ | QR only'), findsOneWidget);
    await tapText(tester, 'Add Promo');
    expect(find.text('New Promo Code'), findsOneWidget);
    await enterUnder(tester, 'Code', 'summer5');
    await pick(tester, 'Percentage', 'Fixed Amount');
    await enterUnder(tester, 'Value', '5');
    await enterUnder(tester, 'Max Uses (0=∞)', '20');
    await pick(tester, 'All Channels', 'QR Only');
    await tester.tap(filled('Create'));
    await tester.pumpAndSettle();
    final p = api.lastBody('/api/Restaurant/online/promo-codes');
    expect((p['code'], p['discountType'], p['discountValue'], p['maxUses'], p['channelRestriction'], p['isActive'], p['farmId']),
        ('SUMMER5', 'FixedAmount', 5, 20, 'QR', true, 'farm-1'));

    // Edit keeps the row's fields; delete.
    await tester.tap(find.byTooltip('Edit promo'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Promo Code'), findsOneWidget);
    await tester.tap(filled('Update'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/online/promo-codes/3', 'PUT')['code'], 'SAVE10');
    await tester.tap(find.byTooltip('Delete promo'));
    await tester.pumpAndSettle();
    expect(api.writes.any((w) => w.method == 'DELETE' && w.url.path == '/api/Restaurant/online/promo-codes/3'), isTrue);
  });

  testWidgets('Drivers & Dispatch: stats, assign a waiting order, status steps, filter, drivers, zones, platforms', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/delivery/drivers'] = [
        {'driverId': 1, 'firstName': 'Kofi', 'lastName': 'Mensah', 'phone': '055', 'vehicleType': 'Motorcycle', 'status': 'Available',
          'totalDeliveries': 3, 'activeDeliveries': 0},
        {'driverId': 2, 'firstName': 'Ama', 'lastName': 'Boateng', 'phone': '024', 'vehicleType': 'Car', 'status': 'OffDuty', 'totalDeliveries': 0},
      ]
      ..gets['/api/Restaurant/delivery/zones'] = [
        {'deliveryZoneId': 4, 'name': 'Zone A', 'minDistanceKm': 0, 'maxDistanceKm': 3, 'deliveryFee': 5, 'estimatedMins': 20, 'isActive': true},
      ]
      ..gets['/api/Restaurant/delivery/assignments'] = [
        {'deliveryAssignmentId': 9, 'orderId': 50, 'orderNumber': 'ORD-50', 'status': 'Assigned', 'driverName': 'Kofi Mensah', 'driverPhone': '055'},
      ]
      ..gets['/api/Restaurant/delivery/stats'] = {'availableDrivers': 1, 'onDeliveryDrivers': 0, 'activeCount': 1, 'deliveredCount': 4, 'avgDeliveryMins': 22.4}
      ..gets['/api/Restaurant/delivery/platforms'] = []
      ..gets['/api/Restaurant/orders'] = [
        {'orderId': 60, 'orderNumber': 'ORD-60', 'orderType': 'Delivery', 'status': 'Placed', 'customerName': 'Efua', 'totalAmount': 40,
          'createdAt': '2026-10-21T10:00:00Z', 'notes': 'Delivery: 12 Palm St'},
        {'orderId': 50, 'orderNumber': 'ORD-50', 'orderType': 'Delivery', 'status': 'Ready', 'totalAmount': 20, 'createdAt': '2026-10-21T09:00:00Z'},
      ];
    await open(tester, RestaurantDeliveryScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('22m'), findsOneWidget);
    expect(find.text('Awaiting Driver Assignment (1)'), findsOneWidget);
    expect(find.text('ORD-60'), findsOneWidget);

    // Assign the waiting order: the order is preselected, pick the driver.
    await tester.tap(filled('Assign Driver').first);
    await tester.pumpAndSettle();
    expect(find.text('Ama Boateng (Car)'), findsNothing, reason: 'only Available drivers');
    await pick(tester, 'Choose a driver...', 'Kofi Mensah (Motorcycle)');
    await tester.tap(find.widgetWithText(FilledButton, 'Assign Driver').last);
    await tester.pumpAndSettle();
    final a = api.lastBody('/api/Restaurant/delivery/assignments');
    expect((a['orderId'], a['orderNumber'], a['driverId'], a['deliveryAddress'], a['deliveryFee']), (60, 'ORD-60', 1, 'Delivery: 12 Palm St', 0));

    // Assigned → Picked Up.
    await tester.tap(filled('Picked Up'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/delivery/assignments/9/status', 'PATCH'), {'status': 'PickedUp'});

    // The Delivered filter asks the server for that status.
    // ("Active" is also a stat card label, so open the select by its last match.)
    await tester.tap(find.text('Active').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivered').last);
    await tester.pumpAndSettle();
    expect(api.requests.any((r) => r.url.path == '/api/Restaurant/delivery/assignments' && r.url.queryParameters['status'] == 'Delivered'), isTrue);

    // Drivers: Clock In, and a new driver needs a name and phone.
    await tester.tap(find.text('Drivers (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock In'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/delivery/drivers/2/status', 'PATCH'), {'status': 'Available'});
    await tapText(tester, 'Add Driver');
    await tester.tap(filled('Add Driver').last);
    await tester.pumpAndSettle();
    expect(find.text('Name and phone required'), findsOneWidget);
    await enterUnder(tester, 'First Name', 'Yaw');
    await enterUnder(tester, 'Phone', '020');
    // ("Motorcycle" is also Kofi's badge behind the dialog.)
    await tester.tap(find.text('Motorcycle').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bicycle').last);
    await tester.pumpAndSettle();
    await enterUnder(tester, 'Plate', 'GR-1');
    await tester.tap(filled('Add Driver').last);
    await tester.pumpAndSettle();
    final d = api.lastBody('/api/Restaurant/delivery/drivers');
    expect((d['firstName'], d['phone'], d['vehicleType'], d['vehiclePlate'], d['farmId']), ('Yaw', '020', 'Bicycle', 'GR-1', 'farm-1'));

    // Zones: edit keeps the zone, numbers parse.
    await tester.tap(find.text('Zones (1)'));
    await tester.pumpAndSettle();
    expect(find.text('0-3 km | Fee: 5.00 | Est: 20min'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit zone'));
    await tester.pumpAndSettle();
    await enterUnder(tester, 'Delivery Fee', '7.5');
    await tester.tap(filled('Update'));
    await tester.pumpAndSettle();
    final z = api.lastBody('/api/Restaurant/delivery/zones/4', 'PUT');
    expect((z['name'], z['deliveryFee'], z['maxDistanceKm'], z['estimatedMins']), ('Zone A', 7.5, 3, 20));

    // Third-Party: add an enabled platform.
    await tester.tap(find.text('Third-Party (0)'));
    await tester.pumpAndSettle();
    expect(find.text('No platforms configured. Add Uber Eats, Glovo, etc.'), findsOneWidget);
    await tapText(tester, 'Add Platform');
    await enterUnder(tester, 'Platform Name', 'Glovo');
    await enterUnder(tester, 'Commission %', '15');
    await tester.tap(find.text('Enabled'));
    await tester.pump();
    await tester.tap(filled('Add Platform').last);
    await tester.pumpAndSettle();
    final pl = api.lastBody('/api/Restaurant/delivery/platforms');
    expect((pl['name'], pl['commissionRate'], pl['isEnabled']), ('Glovo', 15, true));
  });

  FakeApi guestApi({bool enabled = true, bool accepting = true}) => FakeApi()
    ..gets['/api/Restaurant/public/farm-1/settings'] = {
      'isEnabled': enabled, 'acceptingOrders': accepting, 'allowTakeaway': true, 'allowDelivery': true,
      'minOrderAmount': 10, 'deliveryFeeAmount': 5, 'welcomeMessage': 'Karibu', 'pausedReason': 'Kitchen break',
    }
    ..gets['/api/Restaurant/public/farm-1/categories'] = [
      {'menuCategoryId': 1, 'name': 'Mains'},
      {'menuCategoryId': 2, 'name': 'Drinks'},
    ]
    ..gets['/api/Restaurant/public/farm-1/menu'] = [
      {'menuItemId': 11, 'name': 'Jollof', 'price': 8, 'categoryId': 1, 'prepTime': 15, 'spicyLevel': 2, 'isVegan': false, 'isVegetarian': true},
      {'menuItemId': 12, 'name': 'Sobolo', 'price': 3, 'categoryId': 2, 'prepTime': 0, 'spicyLevel': 0},
    ]
    ..gets['/api/Restaurant/public/farm-1/profile'] = {'restaurantName': 'Rose Bistro', 'city': 'Accra'}
    ..writeAnswers['/api/Restaurant/public/farm-1/place-order'] = {'orderNumber': 'ORD-77', 'trackingToken': 'TRK'}
    ..writeAnswers['/api/Restaurant/public/farm-1/validate-promo'] = {'valid': true, 'message': 'Saved 2.00', 'calculatedDiscount': 2}
    ..gets['/api/Restaurant/public/track/TRK'] = {
      'orderNumber': 'ORD-77', 'orderType': 'Delivery', 'status': 'Ready', 'totalAmount': 22, 'createdAt': '2026-10-21T10:00:00Z',
    }
    ..gets['/api/Restaurant/public/feedback/TRK'] = {'found': true, 'canRate': true, 'alreadyRated': false};

  testWidgets('QR / Customer Order: not set up, paused, then order, check out, track and rate', (tester) async {
    // Never switched on.
    var api = guestApi(enabled: false);
    await open(tester, RestaurantOrderOnlineScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text("Rose Bistro isn't taking phone orders yet"), findsOneWidget);

    // Paused.
    api = guestApi(accepting: false);
    await open(tester, RestaurantOrderOnlineScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('Orders are paused right now'), findsOneWidget);
    expect(find.text('Kitchen break'), findsOneWidget);

    // A bad code.
    api = guestApi()..statuses['/api/Restaurant/public/qr/BAD'] = 404;
    await open(tester, RestaurantOrderOnlineScreen(session: await sessionFor(api), qrToken: 'BAD'), size: tall);
    expect(find.text('Restaurant not found'), findsOneWidget);

    api = guestApi();
    await open(tester, RestaurantOrderOnlineScreen(session: await sessionFor(api), company: rest), size: const Size(360, 1400));
    expect(find.text('Rose Bistro'), findsWidgets);
    expect(find.text('Karibu'), findsOneWidget);
    expect(find.text('VEG'), findsOneWidget);

    // Categories and search filter the cards.
    await tester.tap(find.text('Drinks').first);
    await tester.pump();
    expect(find.text('Jollof'), findsNothing);
    await tester.tap(find.text('All').first);
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Search the menu...'), 'zzz');
    await tester.pump();
    expect(find.text('Nothing matches that'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();

    // Add to the order: below the 10.00 minimum, then above it.
    await tester.tap(find.byTooltip('Add Jollof to your order').first);
    await tester.pump();
    expect(find.text('View order'), findsOneWidget);
    await tester.tap(find.text('View order'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum order is 10.00. Add 2.00 more.'), findsOneWidget);
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(find.text('Continue · 16.00'), findsOneWidget);
    await tester.tap(find.text('Close').hitTestable().evaluate().isEmpty ? find.byTooltip('Close') : find.text('Close'));
    await tester.pumpAndSettle();

    // Delivery adds the fee; check out.
    await tester.tap(find.text('Delivery').first);
    await tester.pump();
    await tester.tap(find.text('View order'));
    await tester.pumpAndSettle();
    expect(find.text('Continue · 21.00'), findsOneWidget);
    await tester.tap(find.text('Continue · 21.00'));
    await tester.pumpAndSettle();
    expect(find.text('Your details'), findsWidgets);
    final place = find.widgetWithText(FilledButton, 'Place order · 21.00');
    expect(tester.widget<FilledButton>(place).onPressed, isNull, reason: 'name, phone and address are required');
    await tester.enterText(find.widgetWithText(TextField, 'Promo code'), 'save2');
    await tester.tap(find.byTooltip('Apply promo'));
    await tester.pumpAndSettle();
    expect(find.text('Saved 2.00'), findsOneWidget);
    expect(api.lastBody('/api/Restaurant/public/farm-1/validate-promo'), {'code': 'SAVE2', 'orderAmount': 16, 'channel': 'Online'});
    await tester.enterText(find.widgetWithText(TextField, 'So we know whose order this is'), 'Efua');
    await tester.enterText(find.widgetWithText(TextField, 'In case we need to check something'), '0244');
    await tester.enterText(find.widgetWithText(TextField, 'For your receipt'), 'bad@');
    await tester.pump();
    expect(find.textContaining('That email address does not look right'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'For your receipt'), '');
    await tester.enterText(find.widgetWithText(TextField, 'Where should we bring it?'), '12 Palm St');
    await tester.tap(find.text('Mobile Money'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Place order · 19.00'));
    await tester.pumpAndSettle();
    final o = api.lastBody('/api/Restaurant/public/farm-1/place-order');
    expect(
        (o['orderType'], o['customerName'], o['customerPhone'], o.containsKey('customerEmail'), o['deliveryAddress'], o['notes'], o['deliveryFee'],
            o['promoCode'], o['guestPaymentIntent'], o['guestPaymentAmount'], o['onlineSource']),
        ('Delivery', 'Efua', '0244', false, '12 Palm St', 'Delivery: 12 Palm St', 5, 'SAVE2', 'MobileMoney', 19, 'Web'));
    expect(o['items'], [
      {'menuItemId': 11, 'quantity': 2},
    ]);

    // The tracking card, then rating the visit.
    expect(find.text('ORD-77'), findsOneWidget);
    expect(find.text('Order something else'), findsOneWidget);
    expect(find.text('How was everything?'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
    await tester.pump();
    expect(find.text('Really good'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Tell them what you loved, or what could be better...'), 'Lovely');
    api.gets['/api/Restaurant/public/feedback/TRK'] = {'found': true, 'canRate': false, 'alreadyRated': true, 'rating': 4, 'comment': 'Lovely'};
    await tester.ensureVisible(find.text('Send my rating'));
    await tester.tap(find.text('Send my rating'));
    await tester.pumpAndSettle();
    expect(api.lastBody('/api/Restaurant/public/feedback/TRK'), {'rating': 4, 'comment': 'Lovely'});
    expect(find.text('Thank you - that means a lot.'), findsOneWidget);

    // Back to the menu: the order is remembered on this device.
    await tester.tap(find.text('Order something else'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (1)'), findsOneWidget);
    await tester.tap(find.text('My orders (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Your recent orders'), findsOneWidget);
    expect(find.text('Ready for you'), findsOneWidget);
    await tester.tap(find.text('Forget my details on this device'));
    await tester.pumpAndSettle();
    expect(find.text('My orders (1)'), findsNothing);
  });

  testWidgets('a table QR code is dine-in with no type choice; details are filled in from last time', (tester) async {
    final api = guestApi()..gets['/api/Restaurant/public/qr/TBL'] = {'farmId': 'farm-1', 'tableId': 5, 'tableNumber': '5', 'codeType': 'Table'};
    final s = await sessionFor(api);
    await GuestStore.saveProfile({'name': 'Kwame', 'phone': '020'});
    await open(tester, RestaurantOrderOnlineScreen(session: s, qrToken: 'TBL'), size: const Size(360, 1400));
    expect(find.text('TABLE 5'), findsOneWidget);
    expect(find.text('Takeaway'), findsNothing);
    await tester.tap(find.byTooltip('Add Jollof to your order').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Add another Jollof'));
    await tester.pump();
    await tester.tap(find.text('View order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue · 16.00'));
    await tester.pumpAndSettle();
    expect(find.text('Filled in from last time.', findRichText: true), findsNothing);
    expect(find.textContaining('Filled in from last time', findRichText: true), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Place order · 16.00'));
    await tester.pumpAndSettle();
    final o = api.lastBody('/api/Restaurant/public/farm-1/place-order');
    expect((o['qrToken'], o['orderType'], o['tableId'], o['tableNumber'], o['customerName'], o['onlineSource'], o['deliveryFee']),
        ('TBL', 'DineIn', 5, '5', 'Kwame', 'QR', 0));
  });
}

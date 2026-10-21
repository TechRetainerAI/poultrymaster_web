// Restaurant → Growth (2026-10-20): Customers & CRM, Loyalty & Rewards and
// Events & Catering as the web pages, against a fake API at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_crm_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_events_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_gift_cards_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_loyalty_screen.dart';
import 'package:poultrycore_mobile/pages/restaurant/restaurant_notifications_screen.dart';

import 'support/harness.dart';

final rest = Company(farmId: 'farm-1', name: 'Rose Bistro', type: CompanyType.restaurant, role: 'Admin');
const tall = Size(390, 4000);

/// The first text box on the screen on top (a pushed form), not the page below it.
Finder topField() => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(TextFormField)).first;

Future<void> tapText(WidgetTester tester, String text, {bool first = false}) async {
  final f = first ? find.text(text).first : find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('all five Growth rows open native screens', () {
    for (final h in ['/restaurant-crm', '/restaurant-loyalty', '/restaurant-events', '/restaurant-gift-cards', '/restaurant-notifications']) {
      expect(pageScreens.containsKey(h), isTrue, reason: h);
    }
    final now = DateTime.utc(2026, 10, 20, 12);
    expect(notificationTimeAgo('2026-10-20T11:59:30Z', Duration.zero, now: now), 'Just now');
    expect(notificationTimeAgo('2026-10-20T11:15:00Z', Duration.zero, now: now), '45m ago');
    expect(notificationTimeAgo('2026-10-20T07:00:00Z', Duration.zero, now: now), '5h ago');
    expect(notificationTimeAgo('2026-10-18T12:00:00Z', Duration.zero, now: now), '2d ago');
  });

  testWidgets('CRM: stats, segment filter, a customer added, feedback responded, a campaign from a template', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/crm/customers'] = [
        {'customerId': 1, 'name': 'Ama Mensah', 'phone': '020', 'segment': 'VIP', 'totalVisits': 12, 'totalSpent': 900, 'allergies': 'Nuts'},
        {'customerId': 2, 'name': 'Kofi Boateng', 'segment': 'New', 'totalVisits': 1, 'totalSpent': 40},
      ]
      ..gets['/api/Restaurant/crm/customers/stats'] = {'totalCustomers': 2, 'newCount': 1, 'regularCount': 0, 'vipCount': 1, 'totalLifetimeValue': 940}
      ..gets['/api/Restaurant/crm/feedback'] = [
        {'feedbackId': 5, 'rating': 4, 'customerName': 'Ama', 'source': 'QR', 'status': 'New', 'comment': 'Lovely jollof', 'createdAt': '2026-10-19T12:00:00Z'},
      ]
      ..gets['/api/Restaurant/crm/feedback/stats'] = {'avgRating': 4, 'avgFood': 4.5, 'avgService': 3.5, 'avgAmbience': 4, 'totalFeedback': 1, 'newCount': 1};
    await open(tester, RestaurantCrmScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('940'), findsOneWidget, reason: 'lifetime value, no decimals');
    expect(find.text('Dietary'), findsWidgets);
    expect(find.text('— ⚠️ Nuts'), findsOneWidget);

    await tester.tap(find.text('All Segments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👑 VIP').last);
    await tester.pumpAndSettle();
    expect(find.text('Kofi Boateng'), findsNothing);

    await tapText(tester, 'Add Customer', first: true);
    await tester.enterText(topField(), 'Yaw Asare');
    // The app-bar title says Add Customer too; tap the button.
    await tester.tap(find.widgetWithText(FilledButton, 'Add Customer'));
    await tester.pumpAndSettle();
    final c = api.lastBody('/api/Restaurant/crm/customers');
    expect((c['name'], c['segment'], c['farmId'], c.containsKey('phone')), ('Yaw Asare', 'New', 'farm-1', false));

    await tapText(tester, 'Feedback');
    expect(find.text('4.5'), findsOneWidget);
    await tapText(tester, 'Respond');
    await tester.enterText(find.widgetWithText(TextFormField, 'Thank you for your feedback...'), 'Thanks Ama!');
    await tapText(tester, 'Send Response');
    final w = api.writes.last;
    expect((w.url.path, api.lastBody('/api/Restaurant/crm/feedback/5/respond')['response']), ('/api/Restaurant/crm/feedback/5/respond', 'Thanks Ama!'));

    await tapText(tester, 'Campaigns');
    await tapText(tester, 'Create Campaign');
    await tester.enterText(topField(), 'Birthday push');
    await tester.tap(find.text('Pick a template (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Birthday Greeting').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Create');
    final ca = api.lastBody('/api/Restaurant/crm/campaigns');
    expect((ca['name'], ca['campaignType'], (ca['message'] as String).startsWith('Dear {first_name},\n\nHappy Birthday!')), ('Birthday push', 'Promotion', true));
    expect(ca.containsKey('channel'), isFalse, reason: 'left at its default, as the web leaves it undefined');
  });

  testWidgets('Loyalty: tier cards, settings saved, a member earns and redeems, history', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/loyalty/settings'] = {
        'isEnabled': true, 'pointsPerCurrencyUnit': 2, 'pointsRedemptionRate': 0.05, 'minimumRedeemPoints': 50, 'pointsExpiryDays': 180,
        'tiersEnabled': true, 'bronzeThreshold': 0, 'silverThreshold': 400, 'goldThreshold': 900, 'platinumThreshold': 2000,
        'bronzeMultiplier': 1, 'silverMultiplier': 1.5, 'goldMultiplier': 2, 'platinumMultiplier': 3, 'referralBonus': 25,
      }
      ..gets['/api/Restaurant/loyalty/accounts'] = [
        {'loyaltyAccountId': 3, 'customerName': 'Esi', 'customerPhone': '024', 'currentTier': 'Gold', 'totalPoints': 1200, 'lifetimePoints': 1500},
      ]
      ..gets['/api/Restaurant/loyalty/stats'] = {'bronzeCount': 0, 'silverCount': 0, 'goldCount': 1, 'platinumCount': 0}
      ..gets['/api/Restaurant/loyalty/accounts/3/transactions'] = [
        {'pointTransactionId': 1, 'transactionType': 'Earn', 'points': 100, 'description': 'Dinner', 'createdAt': '2026-10-19T18:00:00Z'},
      ];
    await open(tester, RestaurantLoyaltyScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('400+ points'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);

    await tapText(tester, 'Save Settings');
    final s = api.lastBody('/api/Restaurant/loyalty/settings');
    expect((s['isEnabled'], s['pointsPerCurrencyUnit'], s['pointsRedemptionRate'], s['silverThreshold'], s['silverMultiplier']), (true, 2, 0.05, 400, 1.5));

    await tapText(tester, 'Members');
    expect(find.text('1,200 pts'), findsOneWidget);
    await tapText(tester, 'Earn');
    await tester.enterText(find.widgetWithText(TextFormField, 'Number of points'), '30');
    await tapText(tester, 'Add Points');
    final e = api.lastBody('/api/Restaurant/loyalty/accounts/3/earn');
    expect((e['points'], e['description'], e.containsKey('orderId')), (30, 'Manual earn', false));

    await tapText(tester, 'Redeem');
    expect(find.text('Redeem points for Esi (Available: 1,200)'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Number of points'), '100');
    await tapText(tester, 'Redeem');
    expect(api.lastBody('/api/Restaurant/loyalty/accounts/3/redeem')['points'], 100);

    await tapText(tester, 'History');
    expect(find.text('+100'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
  });

  testWidgets('Events: stats, status pills, the next step, a new event', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/events'] = [
        {'eventId': 8, 'eventNumber': 'EV-8', 'name': 'Smith Wedding', 'eventType': 'Wedding', 'status': 'Inquiry', 'eventDate': '2099-01-10',
          'guestCount': 120, 'venue': 'InHouse', 'pricePerHead': 50, 'totalAmount': 6000, 'depositAmount': 1000, 'depositPaid': false},
        {'eventId': 9, 'name': 'Office party', 'eventType': 'HolidayParty', 'status': 'Cancelled', 'eventDate': '2026-01-10', 'guestCount': 30, 'totalAmount': 900},
      ];
    await open(tester, RestaurantEventsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('6,000.00'), findsOneWidget, reason: 'cancelled events are left out of revenue');
    expect(find.text('75'), findsOneWidget, reason: 'average guests');
    expect(find.text('Deposit: 1000.00 (Unpaid)'), findsOneWidget);

    await tapText(tester, 'Confirmed');
    final p = api.writes.last;
    expect((p.method, p.url.path, api.lastBody('/api/Restaurant/events/8/status', 'PATCH')['status']), ('PATCH', '/api/Restaurant/events/8/status', 'Confirmed'));

    await tester.tap(find.text('Cancelled (1)', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Smith Wedding'), findsNothing);
    expect(find.text('Office party'), findsOneWidget);

    await tapText(tester, 'New Event', first: true);
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Smith Wedding Reception'), 'Board dinner');
    await tapText(tester, 'Create Event');
    final b = api.lastBody('/api/Restaurant/events');
    expect((b['name'], b['eventType'], b['guestCount'], b['startTime'], b['venue'], b.containsKey('pricePerHead')),
        ('Board dinner', 'Corporate', 50, '18:00', 'InHouse', false));
  });

  testWidgets('Gift Cards: stats, a card issued and emailed, check balance, redeem, reload, history', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/gift-cards'] = [
        {'giftCardId': 4, 'cardNumber': 'GC-AB12CD34', 'cardType': 'Digital', 'status': 'Active', 'initialBalance': 100, 'currentBalance': 60,
          'purchaserName': 'Kojo', 'recipientName': 'Esi'},
        {'giftCardId': 5, 'cardNumber': 'GC-ZZ99', 'cardType': 'Physical', 'status': 'Redeemed', 'initialBalance': 20, 'currentBalance': 0},
      ]
      ..gets['/api/Restaurant/gift-cards/stats'] = {'totalCards': 2, 'activeCards': 1, 'totalIssued': 120, 'totalRedeemed': 60}
      ..gets['/api/Restaurant/gift-cards/balance/GC-AB12CD34'] = {'cardNumber': 'GC-AB12CD34', 'status': 'Active', 'currentBalance': 60, 'initialBalance': 100}
      ..gets['/api/Restaurant/gift-cards/4/transactions'] = [
        {'giftCardTxId': 1, 'transactionType': 'Redeem', 'amount': -40, 'balanceAfter': 60, 'orderId': 77, 'createdAt': '2026-10-19T12:00:00Z'},
      ]
      ..writeAnswers['/api/Restaurant/gift-cards'] = {'giftCardId': 6, 'cardNumber': 'GC-NEW00001'}
      ..writeAnswers['/api/Restaurant/gift-cards/redeem'] = {'success': true, 'message': 'Redeemed', 'newBalance': 50}
      ..writeAnswers['/api/Email/send-html'] = {'success': true};
    await open(tester, RestaurantGiftCardsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text(r'$120.00'), findsOneWidget);
    expect(find.text(r'$100.00 → $60.00'), findsOneWidget);
    expect(find.byTooltip('Reload'), findsOneWidget, reason: 'only the active card');

    await tester.tap(find.text('Issue Card').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '50.00'), '75');
    await tester.enterText(find.descendant(of: find.byType(Scaffold).last, matching: find.byType(TextFormField)).at(4), 'esi@x.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Issue Card'));
    await tester.pumpAndSettle();
    final b = api.lastBody('/api/Restaurant/gift-cards');
    expect((b['amount'], b['cardType'], b['paymentMethod'], b['recipientEmail']), (75, 'Digital', 'Cash', 'esi@x.com'));
    final mail = api.lastBody('/api/Email/send-html');
    expect((mail['to'], mail['subject'], (mail['body'] as String).contains('GC-NEW00001')),
        ('esi@x.com', "You've Received a Gift Card — GC-NEW00001", true));

    await tester.tap(find.text('Check Balance').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'GC-XXXXXXXX'), 'GC-AB12CD34');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Check Balance'));
    await tester.pumpAndSettle();
    expect(find.text(r'Initial: $100.00'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Redeem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '10');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Redeem'));
    await tester.pumpAndSettle();
    final r = api.lastBody('/api/Restaurant/gift-cards/redeem');
    expect((r['cardNumber'], r['amount'], r.containsKey('orderId')), ('GC-AB12CD34', 10, false));

    await tester.tap(find.byTooltip('Reload'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '25.00'), '20');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
    await tester.pumpAndSettle();
    final rl = api.lastBody('/api/Restaurant/gift-cards/reload');
    expect((rl['amount'], rl['paymentMethod'], rl['cashAccountId']), (20, 'Cash', null));

    await tester.tap(find.byTooltip('History').first);
    await tester.pumpAndSettle();
    expect(find.text(r'$-40.00'), findsOneWidget, reason: 'the web puts + before a credit and leaves the minus after the dollar sign');
    expect(find.text('Order #77'), findsOneWidget);
    expect(find.text(r'Bal: $60.00'), findsOneWidget);
  });

  testWidgets('Notifications: unread count, tap marks read, mark all, settings loaded and saved', (tester) async {
    final api = FakeApi()
      ..gets['/api/Restaurant/notifications'] = [
        {'notificationId': 1, 'title': 'Low stock: Rice', 'message': 'Below reorder point', 'type': 'Stock', 'severity': 'warning', 'isRead': false,
          'createdAt': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String()},
        {'notificationId': 2, 'title': 'Order #12', 'message': 'New order', 'type': 'Order', 'severity': 'info', 'isRead': true,
          'createdAt': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String()},
      ]
      ..gets['/api/Restaurant/notifications/settings'] = {'newOrderAlerts': false, 'smsEnabled': true};
    await open(tester, RestaurantNotificationsScreen(session: await sessionFor(api), company: rest), size: tall);
    expect(find.text('5m ago'), findsOneWidget);
    expect(find.text('2h ago'), findsOneWidget);

    await tester.tap(find.text('Show Unread Only'));
    await tester.pumpAndSettle();
    expect(find.text('Order #12'), findsNothing);
    await tester.tap(find.text('Low stock: Rice'));
    await tester.pumpAndSettle();
    expect(api.writes.last.url.path, '/api/Restaurant/notifications/1/read');
    expect(find.text("You're all caught up! No unread notifications."), findsOneWidget);
    final markAll = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Mark All Read'));
    expect(markAll.onPressed, isNull, reason: 'nothing left unread');

    await tapText(tester, 'Settings');
    await tapText(tester, 'Save Preferences');
    final s = api.lastBody('/api/Restaurant/notifications/settings');
    expect((s['newOrderAlerts'], s['lowStockAlerts'], s['smsEnabled'], s['pushEnabled']), (false, true, true, false));
  });
}

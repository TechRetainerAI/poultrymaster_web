// Shared by the widget tests: a fake backend, a session over it, and the
// small actions every screen test needs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poultrycore_mobile/api/api_client.dart';
import 'package:poultrycore_mobile/design/app_theme.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/state/session.dart';
import 'package:poultrycore_mobile/state/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake backend: GET answers come from [gets] by path, writes are recorded.
class FakeApi {
  final Map<String, Object?> gets = {};

  /// A status other than 200 for a GET path, e.g. 404 for "not set up yet".
  final Map<String, int> statuses = {};
  final List<http.Request> writes = [];

  /// A status other than 200 for a write path, e.g. 409 for a refused post.
  final Map<String, int> writeStatuses = {};

  /// A JSON answer other than the default for a write path.
  final Map<String, Object?> writeAnswers = {};

  /// Every request, GETs included, in order.
  final List<http.Request> requests = [];

  /// Called on each write, so a test can change what later GETs return.
  void Function(http.Request req)? onWrite;

  http.Client get client => MockClient((req) async {
        requests.add(req);
        if (req.method == 'GET') {
          final status = statuses[req.url.path];
          if (status != null) return http.Response('{"message":"status $status"}', status);
          final body = gets[req.url.path];
          return http.Response(jsonEncode(body ?? []), 200,
              headers: {'content-type': 'application/json'});
        }
        writes.add(req);
        onWrite?.call(req);
        final ws = writeStatuses[req.url.path];
        if (ws != null) return http.Response('{"message":"status $ws"}', ws);
        return http.Response(jsonEncode(writeAnswers[req.url.path] ?? {'id': 'new-user-1', 'success': true}), 200,
            headers: {'content-type': 'application/json'});
      });

  Map<String, dynamic> lastBody(String path, [String method = 'POST']) {
    final r = writes.lastWhere((w) => w.url.path == path && w.method == method);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}

final company = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry);

/// The same company, owned by an admin.
final adminCompany = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Admin');

/// A small phone, where a too-wide row overflows.
const phone = Size(360, 780);

Future<Session> sessionFor(FakeApi api) async {
  SharedPreferences.setMockInitialValues({'user_id': 'user-1', 'auth_token': 't'});
  final tokens = TokenStore(await SharedPreferences.getInstance());
  return Session.forTesting(
    tokens,
    ApiClient(baseUrl: 'https://login.test', tokens: tokens, inner: api.client),
    ApiClient(baseUrl: 'https://farm.test', tokens: tokens, inner: api.client),
  );
}

/// Pushes [screen] over a host page, as the app does, so Save can pop.
Future<void> open(WidgetTester tester, Widget screen, {Size size = const Size(1200, 4000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    navigatorKey: nav,
    home: const Scaffold(body: Text('host')),
  ));
  nav.currentState!.push(MaterialPageRoute(builder: (_) => screen));
  await tester.pumpAndSettle();
}

/// Opens the dropdown currently showing [shown] and picks [option].
Future<void> pick(WidgetTester tester, String shown, String option) async {
  await tester.tap(find.text(shown).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(field.first, text);
  await tester.pump();
}


// Report 34, A2/A3: Add / Edit Flock's bird history (413 / 414), as the web's
// existing-flock-fields.tsx, flock-history-panel.tsx, house-picker.tsx and
// BatchAvailability (components/setup-views/flocks.tsx). At phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/record_screen.dart';
import 'package:poultrycore_mobile/pages/registry.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_form_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_history.dart';
import 'package:poultrycore_mobile/pages/poultry/flock_type.dart';

import 'support/harness.dart';

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, 300));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await see(tester, f);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> typeIn(WidgetTester tester, Key key, String text) async {
  final f = find.descendant(of: find.byKey(key), matching: find.byType(TextField));
  await see(tester, f);
  await tester.enterText(f.first, text);
  await tester.pumpAndSettle();
}

FakeApi _farm() {
  clearPoultryBusinessTypes();
  return FakeApi()
    ..statuses['/api/Poultry/company'] = 404
    ..gets['/api/MainFlockBatch'] = [
      {'batchId': 7, 'batchName': 'Batch Seven', 'numberOfBirds': 1000, 'startDate': '2026-10-01T00:00:00', 'breed': 'Isa Brown'},
    ]
    ..gets['/api/House'] = [
      {'houseId': 3, 'houseName': 'Pen 3', 'capacity': 2000, 'location': 'North'},
    ]
    ..gets['/api/Flock'] = []
    ..gets['/api/Poultry/bird-reconciliation/batches'] = [
      {'batchId': 7, 'unallocatedPool': 600, 'originallyAllocated': 300, 'batchSold': 100, 'batchMortality': 0, 'batchCulled': 0,
        'batchTransferred': 0, 'batchOtherRemovals': 0, 'status': 'Unexplained'},
    ];
}

final _ctx = <String, Object?>{
  'flockId': 11,
  'mode': 'Existing',
  'opening': {
    'openingPositionId': 4, 'effectiveDate': '2026-10-05', 'originallyPlaced': 500, 'openingLiveBirds': 450,
    'historicalMortality': 30, 'historicalSold': 0, 'historicalCulled': 0, 'historicalTransferred': 0,
    'historyKnown': true, 'startDateEstimated': false, 'source': 'Initial Farm Setup',
  },
  'position': {
    'originallyplaced': 500, 'openinglivebirds': 450, 'currentlivebirds': 440, 'recordedmortality': 10,
    'productionrecordcount': 2, 'birdssold': 0, 'birdsculled': 0, 'birdstransferred': 0,
  },
  'quantityAdjustments': 0,
  'movements': [
    {'kind': 'opening', 'id': 1, 'effectiveDate': '2026-10-05', 'postedAt': '2026-10-05T10:00:00Z', 'reason': 'Opening history', 'quantity': -50},
  ],
  'canDelete': false,
  'deleteBlockers': [
    {'source': 'production', 'label': 'production records', 'rows': 2},
  ],
};

void main() {
  deleteMain();
  test('existing-flock rules, opening warnings and the delete check', () {
    final d = ExistingFlockDraft('2026-11-10');
    expect(existingFlockHistory(500, d).problem, 'Enter how many birds are remaining today.');
    d.currentLiveBirds = '600';
    expect(existingFlockHistory(500, d).problem, startsWith('Birds remaining are more than were placed'));
    d
      ..currentLiveBirds = '450'
      ..mortality = '30';
    final h = existingFlockHistory(500, d);
    expect(h.problem, isNull);
    expect((h.history['originallyPlaced'], h.history['currentLiveBirds'], h.history['historicalMortality']), (500, 450, 30));
    d.historyKnown = false;
    expect(existingFlockHistory(500, d).history['historicalMortality'], 0, reason: 'unknown history sends no reasons');

    final draft = openingDraftFrom(_ctx)!;
    expect((draft.placed, draft.live, draft.mort, draft.sold), ('500', '450', '30', ''));
    expect(openingDraftWarnings(_ctx, draft), isEmpty);
    draft.live = '520';
    expect(openingDraftWarnings(_ctx, draft).first, startsWith('520 alive is more than the 500 originally placed'));
    expect(openingDraftWarnings(_ctx, draft).last, startsWith('This flock already has 2 production record(s).'));
    expect(draft.toEdit()['OpeningLiveBirds'], 520);

    final blocked = flockDeleteCheck(_ctx)!;
    expect(blocked.canDelete, isFalse);
    expect(blocked.message, contains('• 2 production records'));
    final ok = flockDeleteCheck({..._ctx, 'canDelete': true})!;
    expect(ok.message, 'Delete this flock? Its 500 placed birds go back to the batch, and its opening entries are reversed. This cannot be undone.');
    expect(flockDeleteCheck(null), isNull, reason: 'before 414 the usual text is shown');
  });

  testWidgets('Add Flock, existing flock: availability, the history, POST /api/Flock/existing', (tester) async {
    final api = _farm();
    await open(tester, FlockFormScreen(session: await sessionFor(api), company: company), size: phone);
    expect(find.text('New flock — birds being placed now'), findsOneWidget);

    await tapIt(tester, find.text('Please select a batch'));
    await tester.tap(find.text('Batch Seven').last);
    await tester.pumpAndSettle();
    expect(find.text('600 birds free to place'), findsOneWidget, reason: 'the server figure, not the batch size');
    expect(find.text('Batch of 1,000'), findsOneWidget);
    expect(find.textContaining('sold before placing', findRichText: true), findsOneWidget);

    await tapIt(tester, find.byKey(const ValueKey('flock-mode-existing')));
    expect(find.text('Birds Originally Placed'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Old pen');
    await tester.pumpAndSettle();
    final qty = find.descendant(
        of: find.ancestor(of: find.text('Birds Originally Placed'), matching: find.byType(Column)).first, matching: find.byType(TextField));
    await tester.enterText(qty.first, '500');
    await tester.pumpAndSettle();
    expect(find.text('100 birds left to place after this'), findsOneWidget);

    await typeIn(tester, const ValueKey('existing-live'), '450');
    await typeIn(tester, const ValueKey('existing-mortality'), '30');
    expect(find.textContaining('20 unexplained are recorded as “other”'), findsOneWidget);
    await see(tester, find.byKey(const ValueKey('house-picker')));
    expect(find.text('No house — assign one later'), findsOneWidget);

    await tapIt(tester, find.text('Create Flock'));
    final body = api.lastBody('/api/Flock/existing');
    final flock = body['flock'] as Map;
    expect((flock['name'], flock['quantity'], flock['batchId'], '${flock['startDate']}'.endsWith('T00:00:00')), ('Old pen', 500, 7, true));
    expect(body['history'], {
      'originallyPlaced': 500, 'currentLiveBirds': 450, 'historyKnown': true,
      'historicalMortality': 30, 'historicalSold': 0, 'historicalCulled': 0, 'historicalTransferred': 0,
    });
    expect((body['source'], body['asOfDate'] is String), ('Flocks page', true));
    expect(find.text('Flock created: 500 placed, 450 remaining.'), findsOneWidget);
  });

  testWidgets('Edit Flock: the bird history panel edits the opening history', (tester) async {
    final api = _farm()..gets['/api/Flock/11/edit-context'] = _ctx;
    final row = <String, dynamic>{
      'flockId': 11, 'name': 'Old pen', 'batchId': 7, 'quantity': 450, 'startDate': '2026-09-01T00:00:00',
      'breed': 'Isa Brown', 'active': true, 'hasArrived': true, 'flockType': 'Layer',
    };
    await open(tester, FlockFormScreen(session: await sessionFor(api), company: company, existing: row), size: phone);
    expect(find.text('New flock — birds being placed now'), findsNothing, reason: 'the choice is only on Add');
    expect(find.textContaining('This flock can have up to', findRichText: true), findsOneWidget);
    expect(find.text('Set from the registered bird count in Bird history below.'), findsOneWidget);

    await see(tester, find.byKey(const ValueKey('flock-history-panel')));
    expect(find.text('Bird history — originally placed, current and the difference'), findsOneWidget);
    expect(find.text('440'), findsOneWidget, reason: 'live birds now, from the posted records');
    await see(tester, find.text('Opening history'));
    expect(find.textContaining('20 not explained yet. Registered from Initial Farm Setup.'), findsOneWidget);

    await typeIn(tester, const ValueKey('history-live'), '460');
    await see(tester, find.byKey(const ValueKey('flock-quantity-locked')));
    final locked = find.descendant(of: find.byKey(const ValueKey('flock-quantity-locked')), matching: find.byType(TextField));
    expect(tester.widget<TextField>(locked).controller!.text, '460');

    await tapIt(tester, find.text('Update Flock'));
    final body = api.lastBody('/api/Flock/11', 'PUT');
    expect(body['quantity'], 460);
    expect((body['OpeningHistory'] as Map)['OpeningLiveBirds'], 460);
    expect(find.textContaining('Flock updated — please check — This flock already has 2 production record(s).'), findsOneWidget);
  });
}

void deleteMain() {
  testWidgets('Delete on a flock: blocked by posted activity, says why', (tester) async {
    final api = _farm()..gets['/api/Flock/11/edit-context'] = _ctx;
    final row = <String, dynamic>{'flockId': 11, 'name': 'Old pen', 'batchId': 7, 'quantity': 450, 'active': true, 'hasArrived': true};
    await open(tester, RecordScreen(spec: PageRegistry.of('flocks')!, row: row, company: company, session: await sessionFor(api)), size: phone);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This flock has posted activity and cannot be deleted'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(api.writes.where((w) => w.method == 'DELETE'), isEmpty);
  });

  testWidgets('Delete on a flock: the server says what it did', (tester) async {
    final api = _farm()
      ..gets['/api/Flock/11/edit-context'] = {..._ctx, 'canDelete': true, 'deleteBlockers': []}
      ..writeAnswers['/api/Flock/11'] = {'deleted': true, 'birdsReleased': 450};
    final row = <String, dynamic>{'flockId': 11, 'name': 'Old pen', 'batchId': 7, 'quantity': 450, 'active': true, 'hasArrived': true};
    final s = await sessionFor(api);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
        onPressed: () async => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RecordScreen(
            spec: PageRegistry.of('flocks')!, row: row, company: company, session: s))),
        child: const Text('go')))))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this flock? Its 500 placed birds go back to the batch, and its opening entries are reversed. This cannot be undone.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Flock deleted — Flock deleted. Its 450 birds are back in the batch, available to place again.'), findsOneWidget);
  });
}

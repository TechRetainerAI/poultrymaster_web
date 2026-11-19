// Report 34, A2: Initial Farm Setup's batch-level reconciliation (413) and
// the Completed setups panel (416 / 417). The rules are the web's
// lib/farm-setup/wizard.test.ts cases; the panels run at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/farm_setup_wizard.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/batch_reconciliation_step.dart';
import 'package:poultrycore_mobile/pages/poultry/setup/setup_runs_panel.dart';

import 'support/harness.dart';

const _business = '2026-10-02';

SetupContext _ctx({List<ExistingBatch> batches = const [], Map<int, Map> positions = const {}}) =>
    SetupContext(existingBatches: batches, batchPositions: positions, businessDate: _business);

BatchRow _batch(String birds) => BatchRow(key: nextKey('batch'), batchCode: 'B1', batchName: 'Batch 1', numberOfBirds: birds, startDate: '2026-01-01', isHistorical: true);
HouseRow _house() => HouseRow(key: nextKey('house'), houseName: 'Pen 1');
FlockRow _flock(String batchKey, String houseKey, String placed, String live) => FlockRow(
      key: nextKey('flock'),
      batchKey: batchKey,
      houseKey: houseKey,
      name: 'F ${nextKey('n')}',
      originallyPlaced: placed,
      currentLiveBirds: live,
      startDate: '2026-01-01',
    );

const _existing = ExistingBatch(
    batchId: 300, batchCode: 'B2025', batchName: 'Batch2025', breed: 'ISA Brown', numberOfBirds: 10000, startDate: '2025-01-01', isHistorical: true);

Map _position({int sold = 0, int mortality = 0}) => {
      'batchId': 300, 'originalBirds': 10000, 'originallyAllocated': 0,
      'previouslySold': sold, 'previousMortality': mortality, 'previouslyCulled': 0, 'previouslyTransferred': 0,
      'previousOther': 0, 'previousAdditions': 0, 'previouslyAccountedFor': 2500,
      'unallocatedPool': 7500, 'confirmedStillAlive': 0, 'lastReconciliationNo': 'BR-00001',
    };

({SetupDraft d, BatchRow b, SetupContext ctx}) _build([Map? pos]) {
  final b = batchRowFromExisting(_existing);
  final h = _house();
  final d = SetupDraft(batches: [b], houses: [h], flocks: [_flock(b.key, h.key, '3000', '3000')]);
  return (d: d, b: b, ctx: _ctx(batches: [_existing], positions: {300: pos ?? _position(sold: 2500)}));
}

String _msgs(SetupDraft d, SetupContext c) => validateSetup(d, c).errors.map((e) => e.message).join(' | ');

void main() {
  group('413: birds never placed in a flock', () {
    test('a historical batch is "accounted for", and may be explained instead', () {
      final b = _batch('16000');
      final h = _house();
      final d = SetupDraft(batches: [b], houses: [h], flocks: [_flock(b.key, h.key, '6500', '5950')]);
      expect(_msgs(d, _ctx()), contains('9,500 are not'));
      expect(_msgs(d, _ctx()), contains('explain them on the reconciliation step'));
    });

    test('ACCEPTS a historical batch whose never-placed birds are explained', () {
      final b = _batch('16000');
      final h = _house();
      final d = SetupDraft(batches: [b], houses: [h], flocks: [_flock(b.key, h.key, '6500', '5950')], batchReconciliations: {
        b.key: BatchReconciliationDraft(sales: [
          BatchSaleDraft(key: 's1', quantity: '2000', pricePerBird: '40', date: '2026-07-10'),
          BatchSaleDraft(key: 's2', quantity: '5000', pricePerBird: '45', date: '2026-08-15'),
        ], mortality: '1000', stillAlive: '1500'),
      });
      expect(validateSetup(d, _ctx()).errors, isEmpty);
      final v = batchReconciliationViews(d, _ctx()).single;
      // Measured on ORIGINALLY placed birds: 16,000 - 6,500, not 16,000 - 5,950.
      expect((v.neverPlaced, v.explained, v.unexplained, v.saleValue), (9500, 9500, 0, 305000));
      final req = toRequest(d, _ctx(), 'u', 'f');
      final recs = req['BatchReconciliations'] as List;
      expect(recs, hasLength(1));
      expect(recs[0]['StillUnallocatedLive'], 1500);
      expect([for (final l in recs[0]['Lines'] as List) l['Kind']], ['Sale', 'Sale', 'Mortality']);
      expect((recs[0]['Lines'] as List)[0]['AmountReceived'], 80000);
    });

    test('refuses explaining more birds than never went into a pen', () {
      final b = _batch('1000');
      final h = _house();
      final d = SetupDraft(batches: [b], houses: [h], flocks: [_flock(b.key, h.key, '900', '900')], batchReconciliations: {
        b.key: BatchReconciliationDraft(mortality: '150'),
      });
      expect(validateSetup(d, _ctx()).errors.first.message, contains('only 100 never went into a pen'));
    });

    test('"other" birds need a note', () {
      final b = _batch('1000');
      final h = _house();
      final d = SetupDraft(batches: [b], houses: [h], flocks: [_flock(b.key, h.key, '900', '900')], batchReconciliations: {
        b.key: BatchReconciliationDraft(other: '100'),
      });
      expect(_msgs(d, _ctx()), contains('B1: say what the "other" birds were.'));
    });

    test('the draft keeps its reconciliations through save and reopen', () {
      final b = _batch('1000');
      final d = SetupDraft(batches: [b], batchReconciliations: {
        b.key: BatchReconciliationDraft(sales: [BatchSaleDraft(key: 's', quantity: '5', valueUnknown: true)], stillAlive: '3'),
      });
      final back = SetupDraft.fromJson(d.toJson())!;
      final r = back.batchReconciliations[b.key]!;
      expect((r.stillAlive, r.sales.single.quantity, r.sales.single.valueUnknown), ('3', '5', true));
      expect(SetupDraft.fromJson({'batches': [], 'flocks': []})!.batchReconciliations, isEmpty, reason: 'a draft from before 413');
    });
  });

  group('batch history recorded before setup', () {
    test('E: 10,000 − 2,500 already recorded − 3,000 placed leaves 4,500, not 7,000', () {
      final (:d, b: _, :ctx) = _build();
      final a = batchAllocationViews(d, ctx).single;
      expect((a.previouslyAccountedFor, a.available, a.remaining), (2500, 7500, 4500));
      final v = batchReconciliationViews(d, ctx).single;
      expect((v.previouslyAccountedFor, v.placed, v.neverPlaced, v.unexplained), (2500, 3000, 4500, 4500));
      expect(v.previous?['previouslySold'], 2500);
      expect(_msgs(d, ctx), contains('4,500 are not'));
      expect(_msgs(d, ctx), isNot(contains('7,000')));
    });

    test('F: 4,500 still alive reconciles with no new movement', () {
      final (:d, :b, :ctx) = _build();
      d.batchReconciliations = {b.key: BatchReconciliationDraft(stillAlive: '4500')};
      expect(validateSetup(d, ctx).errors, isEmpty);
      expect(batchReconciliationViews(d, ctx).single.unexplained, 0);
      final recs = toRequest(d, ctx, 'u', 'f')['BatchReconciliations'] as List;
      expect((recs.length, recs[0]['StillUnallocatedLive']), (1, 4500));
      expect(recs[0]['Lines'], isEmpty);
    });

    test('G: an additional sale of 2,000 posts exactly one line, never the 2,500 again', () {
      final (:d, :b, :ctx) = _build();
      d.batchReconciliations = {
        b.key: BatchReconciliationDraft(sales: [BatchSaleDraft(key: 's1', quantity: '2000', pricePerBird: '50', date: _business)], stillAlive: '2500'),
      };
      expect(validateSetup(d, ctx).errors, isEmpty);
      final lines = (toRequest(d, ctx, 'u', 'f')['BatchReconciliations'] as List)[0]['Lines'] as List;
      expect((lines.length, lines[0]['Kind'], lines[0]['Quantity']), (1, 'Sale', 2000));
    });

    test('H: previously recorded MORTALITY stays mortality and is not asked about again', () {
      final (:d, :b, :ctx) = _build(_position(mortality: 2500));
      final v = batchReconciliationViews(d, ctx).single;
      expect((v.previous?['previousMortality'], v.previous?['previouslySold'], v.neverPlaced), (2500, 0, 4500));
      d.batchReconciliations = {b.key: BatchReconciliationDraft(stillAlive: '4500')};
      expect(validateSetup(d, ctx).errors, isEmpty);
    });

    test('I: explaining 7,000 is refused before it ever reaches the database', () {
      final (:d, :b, :ctx) = _build();
      d.batchReconciliations = {
        b.key: BatchReconciliationDraft(sales: [BatchSaleDraft(key: 's1', quantity: '2500', pricePerBird: '60', date: _business)], stillAlive: '4500'),
      };
      expect(_msgs(d, ctx), contains('only 4,500 never went into a pen'));
      expect(_msgs(d, ctx), contains('2,500 more were already recorded'));
    });

    test('cannot place more than the pool once earlier dispositions are counted', () {
      final (:d, b: _, :ctx) = _build();
      d.flocks[0]
        ..originallyPlaced = '8000'
        ..currentLiveBirds = '8000';
      expect(batchAllocationViews(d, ctx).single.status, 'over');
      expect(_msgs(d, ctx), contains('only 7,500 can still be placed'));
    });

    test('an older server (no positions) behaves exactly as before', () {
      final (:d, b: _, ctx: _) = _build();
      expect(batchReconciliationViews(d, _ctx(batches: [_existing])).single.neverPlaced, 7000);
    });

    test('the context reads batchPositions from the server', () {
      final c = SetupContext.fromServer({'batchPositions': [_position(sold: 2500)]}, _business);
      expect(accountedBeforePlacing(c, 300), 2500);
    });
  });

  testWidgets('the step: already recorded, a sale, the unexplained figure', (tester) async {
    final (:d, :b, :ctx) = _build();
    late StateSetter setOuter;
    await open(
      tester,
      StatefulBuilder(builder: (context, set) {
        setOuter = set;
        return Scaffold(
          body: ListView(padding: const EdgeInsets.all(14), children: [
            BatchReconciliationStep(views: batchReconciliationViews(d, ctx), draft: d, onEdit: (f) => setOuter(f), businessDate: _business),
          ]),
        );
      }),
      size: phone,
    );
    final k = b.key;
    expect(find.text('Birds never placed in a flock'), findsOneWidget);
    expect(find.text('What happened to the remaining 4,500 birds that are not in a pen?'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(ValueKey('batch-recon-unexplained-$k'))).data, '4,500');
    expect(find.text('Already recorded (last: BR-00001) — not posted again'), findsOneWidget);
    expect(find.text('Further sales not yet recorded'), findsOneWidget);
    expect(find.text('−2,500'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ValueKey('batch-recon-add-sale-$k')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('batch-recon-add-sale-$k')));
    await tester.pumpAndSettle();
    final qty = find.descendant(of: find.byKey(ValueKey('sale-qty-$k-0')), matching: find.byType(TextField));
    await tester.ensureVisible(qty);
    await tester.pumpAndSettle();
    await tester.enterText(qty, '2000');
    final price = find.descendant(of: find.byKey(ValueKey('sale-price-$k-0')), matching: find.byType(TextField));
    await tester.enterText(price, '50');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(ValueKey('sale-value-$k-0'))).data, '100,000.00');
    final alive = find.descendant(of: find.byKey(ValueKey('recon-alive-$k')), matching: find.byType(TextField));
    await tester.ensureVisible(alive);
    await tester.enterText(alive, '2500');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(ValueKey('batch-recon-unexplained-$k'))).data, '0');
    expect(find.text('Fully accounted for.'), findsOneWidget);
    expect(d.batchReconciliations[k]!.sales.single.date, _business);
  });

  testWidgets('Completed setups: items, blockers, undo with a reason', (tester) async {
    final api = FakeApi()
      ..gets['/api/PoultryFarmSetup/runs'] = [
        {
          'setuprunid': 5, 'businessdate': '2026-10-02T00:00:00', 'completedat': '2026-10-02T09:00:00Z', 'status': 'Completed',
          'blockers': <String>[],
          'items': [
            {'type': 'Batch', 'id': 1, 'name': 'B1', 'gone': false, 'blockers': <String>[]},
            {'type': 'Flock', 'id': 8, 'name': 'Pen 1 flock', 'gone': false, 'blockers': <String>[]},
            {'type': 'Flock', 'id': 9, 'name': 'Old flock', 'gone': true, 'blockers': <String>[]},
          ],
        },
        {
          'setuprunid': 4, 'businessdate': '2026-09-01', 'completedat': '2026-09-01T09:00:00Z', 'status': 'Completed',
          'blockers': ['3 production records'],
          'items': [
            {'type': 'House', 'id': 2, 'name': 'Pen 2', 'gone': false, 'blockers': <String>[]},
          ],
        },
      ]
      ..gets['/api/PoultryFarmSetup/legacy'] = [
        {'type': 'Batch', 'id': 70, 'name': 'Old batch', 'batchid': 70, 'suggested': false, 'blockers': <String>[]},
        {'type': 'Reconciliation', 'id': 71, 'name': 'BR-00009', 'batchid': 70, 'suggested': true, 'blockers': <String>[]},
        {'type': 'Flock', 'id': 72, 'name': 'Legacy flock', 'batchid': 70, 'suggested': true, 'blockers': ['2 production records']},
      ];
    await open(tester, Scaffold(body: ListView(children: [SetupRunsPanel(session: await sessionFor(api), company: company)])), size: phone);
    expect(find.text('Completed setups'), findsOneWidget);
    expect(find.text('Setup #5 · 2026-10-02'), findsOneWidget);
    expect(find.text('Deleted'), findsOneWidget, reason: 'an item already gone');
    expect(find.byTooltip("Cannot delete: Delete this setup's flocks first."), findsOneWidget, reason: 'a batch with live flocks');
    expect(find.text('Cannot be undone while things are recorded against it: 3 production records.'), findsOneWidget);
    final blockedUndo = tester.widget<OutlinedButton>(find.byKey(const ValueKey('undo-run-4')));
    expect(blockedUndo.onPressed, isNull);

    // Earlier setups: the reconciliation starts ticked; the batch (maybe older) does not; a blocked flock cannot be ticked.
    await tester.ensureVisible(find.byKey(const ValueKey('undo-legacy')));
    expect(find.text('Undo ticked (1)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('legacy-tick-Batch:70')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legacy-tick-Batch:70')));
    await tester.pumpAndSettle();
    expect(find.text('Undo ticked (2)'), findsOneWidget, reason: 'the batch takes its reconciliations with it');
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('legacy-tick-Flock:72'))).onChanged, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('undo-run-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('undo-run-5')));
    await tester.pumpAndSettle();
    expect(find.text('Undo setup #5?'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, 'Wrong batch sizes');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Undo setup')).last);
    await tester.pumpAndSettle();
    final body = api.lastBody('/api/PoultryFarmSetup/runs/5/reverse');
    expect(body['Reason'], 'Wrong batch sizes');
  });
}

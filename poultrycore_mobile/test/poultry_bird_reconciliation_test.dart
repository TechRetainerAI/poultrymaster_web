// Report 35, A3: bird reconciliation (413) and bulk flock batches, checked
// against the web. The rule tests are the web's own cases, ported one for
// one from lib/flocks/bird-reconciliation.test.ts and
// lib/flock-batches/bulk.test.ts. The screens run at phone width against a
// fake API: Batch Bird Reconciliation (the new report), Reconcile Birds and
// Add Multiple Batches.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/models/company.dart';
import 'package:poultrycore_mobile/pages/module_registry.dart';
import 'package:poultrycore_mobile/pages/poultry/batch_reconcile_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/bird_reconciliation.dart';
import 'package:poultrycore_mobile/pages/poultry/bulk_flock_batch_screen.dart';
import 'package:poultrycore_mobile/pages/poultry/reports/batch_bird_reconciliation_screen.dart';

import 'support/harness.dart';

ReconciliationLine _sale(num q, {num? price, num? received, bool unknown = false, bool receivable = false, int? customer, int? flock}) =>
    ReconciliationLine(
      kind: ReconciliationKind.sale,
      quantity: q,
      pricePerBird: price,
      amountReceived: received,
      valueUnknown: unknown,
      createReceivable: receivable,
      customerId: customer,
      flockId: flock,
    );
ReconciliationLine _line(ReconciliationKind k, num q, {bool increase = false, String? note}) =>
    ReconciliationLine(kind: k, quantity: q, increase: increase, note: note);

List<BulkBatchRow> _gen({int count = 3, int startNumber = 6, String amountPaid = ''}) => generateBatchRows(
      count: count,
      namePrefix: 'Batch',
      codePrefix: 'B',
      startNumber: startNumber,
      breed: 'Isa Brown',
      startDate: '2026-11-05',
      numberOfBirds: '1000',
      costPerChick: '10',
      amountPaid: amountPaid,
    );

Finder get _list => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> see(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
}

final _rows = [
  {
    'batchId': 1, 'batchCode': 'B001', 'batchName': 'Layers 1', 'isHistorical': true, 'originalBirds': 16000, 'originallyAllocated': 6500,
    'batchSold': 7000, 'batchMortality': 2000, 'batchCulled': 0, 'batchTransferred': 500, 'batchOtherRemovals': 0, 'batchAdditions': 0,
    'unallocatedLive': 0, 'unallocatedPool': 0, 'flockLiveBirds': 6000, 'totalLiveBirds': 6000, 'unexplained': 0, 'status': 'FullyAccountedFor',
  },
  {
    'batchId': 2, 'batchCode': 'B002', 'batchName': 'Broilers', 'isHistorical': false, 'originalBirds': 1000, 'originallyAllocated': 600,
    'batchSold': 0, 'batchMortality': 50, 'batchCulled': 10, 'batchTransferred': 0, 'batchOtherRemovals': 5, 'batchAdditions': 5,
    'unallocatedLive': 200, 'unallocatedPool': 340, 'flockLiveBirds': 580, 'totalLiveBirds': 780, 'unexplained': 140, 'status': 'NeedsReconciliation',
  },
];

FakeApi _api() => FakeApi()
  ..gets['/api/Poultry/bird-reconciliation/batches'] = _rows
  ..gets['/api/Poultry/bird-reconciliation/batches/2'] = {
    'summary': {'unallocatedpool': 340},
    'flocks': [
      {'flockId': 5, 'flockName': 'Pen 1', 'originallyPlaced': 600, 'historicalMortality': 0, 'recordedMortality': 20, 'birdsSold': 0,
        'birdsCulled': 0, 'birdsTransferred': 0, 'currentLiveBirds': 580, 'productionRecordCount': 0},
    ],
    'movements': [
      {'birdAdjustmentId': 1, 'date': '2026-10-02T00:00:00', 'scope': 'BatchUnallocated', 'reason': 'Mortality', 'quantity': -50,
        'birdsBefore': 400, 'birdsAfter': 350, 'sourceType': 'Reconciliation'},
      {'birdAdjustmentId': 2, 'date': '2026-10-03T00:00:00', 'scope': 'Flock', 'flockName': 'Pen 1', 'movementType': 'Placed', 'quantity': 600,
        'birdsBefore': 0, 'birdsAfter': 600, 'reversedById': 9},
    ],
    'historicalSales': [
      {'historicalSaleId': 3, 'saleDate': '2026-09-30', 'flockName': null, 'birds': 100, 'pricePerBird': 40, 'totalValue': 4000,
        'amountReceived': 3000, 'amountOwed': 1000, 'customerName': 'Ama', 'debtNumber': 'OD-1', 'status': 'Posted'},
    ],
    'reconciliations': [],
  };

final _admin = Company(farmId: 'farm-1', name: 'Test Farm', type: CompanyType.poultry, role: 'Admin');

void main() {
  // ------------------------------------------------- bird-reconciliation.test.ts
  group('saleValue (the web\'s cases)', () {
    test('values 2,000 birds at 45 as 90,000, fully paid', () {
      final v = saleValue(_sale(2000, price: 45, received: 90000));
      expect((v.total, v.received, v.owed, v.treatment, v.problem), (90000, 90000, 0, 'HistoricalPaid', null));
    });
    test('keeps the unpaid part as a receivable only when asked', () {
      final tracked = saleValue(_sale(2000, price: 45, received: 60000, receivable: true, customer: 7));
      expect((tracked.owed, tracked.treatment, tracked.problem), (30000, 'HistoricalReceivable', null));
      expect(saleValue(_sale(2000, price: 45, received: 60000)).treatment, 'HistoricalUnpaidNotTracked');
    });
    test('needs a customer for a receivable', () {
      expect(saleValue(_sale(10, price: 5, received: 0, receivable: true)).problem, contains('customer'));
    });
    test('is exact with decimal prices', () {
      expect(saleValue(_sale(3, price: 0.1, received: 0.3)).total, 0.3);
      expect(saleValue(_sale(2000, price: 45.1)).total, 90200);
    });
    test('never invents a price', () {
      expect(saleValue(_sale(10)).problem, contains('price'));
      final u = saleValue(_sale(10, unknown: true));
      expect((u.total, u.treatment, u.problem), (null, 'QuantityOnly', null));
    });
    test('rejects more received than the sale was worth', () {
      expect(saleValue(_sale(10, price: 5, received: 60)).problem, contains('between'));
    });
  });

  group('lineRemoves (the web\'s cases)', () {
    test('a sale valued from a flock moves no bird from the batch pool', () {
      expect(lineRemoves(_sale(100, flock: 4)), 0);
    });
    test('a stock correction can add birds back', () {
      expect(lineRemoves(_line(ReconciliationKind.stockCorrection, 20, increase: true)), -20);
      expect(lineRemoves(_line(ReconciliationKind.stockCorrection, 20)), 20);
    });
  });

  group('previewBatchReconciliation (the web\'s cases)', () {
    test('16,000 bought, 6,500 placed, three sales at different prices', () {
      final p = previewBatchReconciliation(9500, [
        _sale(2000, price: 40, received: 80000),
        _sale(3000, price: 45, received: 135000),
        _sale(2000, price: 50, received: 100000),
        _line(ReconciliationKind.mortality, 2000),
        _line(ReconciliationKind.transferOut, 500),
      ], 0);
      expect((p.saleBirds, p.saleValue, p.unexplained, p.status), (7000, 315000, 0, 'Reconciled'));
    });
    test('live unplaced birds are a legitimate outcome, not a gap', () {
      final p = previewBatchReconciliation(9500, [_sale(7000, unknown: true), _line(ReconciliationKind.mortality, 1000)], 1500);
      expect((p.poolAfter, p.unexplained, p.status), (1500, 0, 'Reconciled'));
    });
    test('what is not explained stays unexplained', () {
      final p = previewBatchReconciliation(9500, [_line(ReconciliationKind.mortality, 1000)], 0);
      expect((p.unexplained, p.status), (8500, 'Unexplained'));
    });
    test('refuses taking out more than the pool', () {
      expect(previewBatchReconciliation(100, [_line(ReconciliationKind.mortality, 200)], 0).status, 'Invalid');
    });
    test('Other needs a note', () {
      expect(previewBatchReconciliation(10, [_line(ReconciliationKind.other, 5)], 5).problems.first, contains('note'));
    });
  });

  group('previewFlockHistory (the web\'s cases)', () {
    test('1,500 placed, 1,350 remaining, 150 explained', () {
      final p = previewFlockHistory(originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: true, mortality: 100, sold: 30, culled: 20, transferred: 0);
      expect((p.difference, p.stated, p.other, p.problem), (150, 150, 0, null));
    });
    test('the unexplained part is other, never mortality', () {
      expect(previewFlockHistory(originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: true, mortality: 100, sold: '', culled: '', transferred: '').other, 50);
    });
    test('unknown history puts everything in other', () {
      final p = previewFlockHistory(originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: false, mortality: 100, sold: 0, culled: 0, transferred: 0);
      expect((p.stated, p.other), (0, 150));
    });
    test('more birds now than placed needs a documented increase', () {
      expect(previewFlockHistory(originallyPlaced: 100, currentLiveBirds: 120, historyKnown: true).problem, contains('more than were placed'));
    });
    test('over-explained is refused', () {
      expect(previewFlockHistory(originallyPlaced: 100, currentLiveBirds: 90, historyKnown: true, mortality: 20).problem, contains('add up'));
    });
  });

  // ---------------------------------------------------------------- bulk.test.ts
  group('bulk flock batches (the web\'s cases)', () {
    test('generates names and padded codes from the start number', () {
      final rows = _gen();
      expect([for (final r in rows) (r.batchName, r.batchCode)], [('Batch 6', 'B006'), ('Batch 7', 'B007'), ('Batch 8', 'B008')]);
      expect((rows[0].breed, rows[0].startDate, rows[0].numberOfBirds), ('Isa Brown', '2026-11-05', '1000'));
    });
    test("continues the farm's code series", () {
      expect(nextBatchStartNumber('B', ['B001', 'b005', 'BT1', 'Bnew', null]), 6);
      expect(nextBatchStartNumber('X', ['B001']), 1);
      expect(makeBatchCode('B', 12), 'B012');
    });
    test('accepts a clean batch', () {
      expect(validateBulkBatches(_gen(), ['B001']), isEmpty);
    });
    test('rejects duplicate codes in the list and against the farm', () {
      final rows = _gen(startNumber: 1);
      rows[2].batchCode = ' b001 ';
      final errs = validateBulkBatches(rows, ['B002']);
      expect([for (final e in errs) if (e.field == 'batchCode') e.index], [1, 2]);
      expect(errs.firstWhere((e) => e.index == 1).message, 'A batch with code "B002" already exists.');
      expect(errs.firstWhere((e) => e.index == 2).message, '"b001" appears more than once in this list.');
    });
    test('requires name, birds > 0 and a start date', () {
      final errs = validateBulkBatches([BulkBatchRow(batchCode: 'Z1')]);
      expect([for (final e in errs) e.field]..sort(), ['batchName', 'numberOfBirds', 'startDate']);
    });
    test('refuses paying more than the cost, and negatives', () {
      final rows = _gen(count: 2);
      rows[0].amountPaid = '10001';
      rows[1].costPerChick = '-1';
      expect(validateBulkBatches(rows), [
        (index: 0, field: 'amountPaid', message: 'Amount paid cannot be more than the total cost.'),
        (index: 1, field: 'costPerChick', message: 'Cost per chick cannot be negative.'),
      ]);
    });
    test('totals birds, cost and balance', () {
      expect(summarizeBulkBatches(_gen(count: 2, amountPaid: '4000')), (count: 2, birds: 2000, totalCost: 20000.0, amountPaid: 8000.0, balance: 12000.0));
    });
    test('copies the shared settings onto every row', () {
      final items = bulkBatchPayload(_gen(count: 1), supplierType: 'foreign', supplierId: 4, cashAccountId: null, status: 'pending', notes: ' run 1 ');
      final i = items.single;
      expect((i['BatchCode'], i['NumberOfBirds'], i['TotalCost'], i['SupplierType'], i['SupplierId'], i['PoultryCashAccountId'], i['Status'], i['Notes']),
          ('B006', 1000, 10000, 'foreign', 4, null, 'pending', 'run 1'));
    });
  });

  // ------------------------------------------------------------------- screens
  group('Batch Bird Reconciliation report', () {
    test('the route, the catalogue link and the totals', () {
      expect(pageScreens.containsKey('/poultry/reports/batch-bird-reconciliation'), isTrue);
      final t = reconciliationTotals(_rows);
      expect((t.original, t.flockLive, t.unalloc, t.live, t.unexplained), (17000, 6580, 200, 6780, 140));
      expect(otherDispositions(_rows[1]), 10, reason: 'culled 10 + other 5 − added 5');
    });

    testWidgets('cards, the table, Reconcile only where needed, the drilldown', (tester) async {
      final api = _api();
      await open(tester, BatchBirdReconciliationScreen(session: await sessionFor(api), company: company), size: phone);
      expect(find.text('Every bird each batch bought: in a flock, waiting to be placed, or gone — and why.'), findsOneWidget);
      expect(find.text('17,000'), findsOneWidget);
      expect(find.text('6,780'), findsWidgets);
      expect(find.text('Layers 1 · existing batch'), findsOneWidget);
      expect(find.text('Fully accounted for'), findsOneWidget);
      expect(find.text('Needs reconciliation'), findsOneWidget);
      expect(find.byKey(const ValueKey('recon-report-reconcile-1')), findsNothing, reason: 'nothing to reconcile on B001');
      expect(find.byKey(const ValueKey('recon-report-reconcile-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('recon-data-checks')), findsNothing, reason: 'admins only');

      await tester.tap(find.byKey(const ValueKey('recon-row-2')));
      await tester.pumpAndSettle();
      expect(find.text('B002 — where the birds went'), findsOneWidget);
      expect(find.textContaining('no production record', findRichText: true), findsOneWidget);
      expect(find.text('Not placed in a flock'), findsWidgets);
      expect(find.text('-50'), findsOneWidget);
      expect(find.text('Placed (reversed)'), findsOneWidget);
      await see(tester, find.text('Ama · OD-1'));
      expect(find.text('1,000.00'), findsWidgets, reason: 'the amount still owed');
    });

    testWidgets('?batchId opens that batch (the Initial Farm Setup "View source" link)', (tester) async {
      await open(tester, BatchBirdReconciliationScreen(session: await sessionFor(_api()), company: company, batchId: 2), size: phone);
      expect(find.text('B002 — where the birds went'), findsOneWidget);
    });

    testWidgets('Reconcile opens Reconcile Birds with the report as the source', (tester) async {
      final api = _api();
      await open(tester, BatchBirdReconciliationScreen(session: await sessionFor(api), company: company), size: phone);
      await tester.ensureVisible(find.byKey(const ValueKey('recon-report-reconcile-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recon-report-reconcile-2')));
      await tester.pumpAndSettle();
      final screen = tester.widget<BatchReconcileScreen>(find.byType(BatchReconcileScreen));
      expect((screen.batchId, screen.batchLabel, screen.source), (2, 'B002 Broilers', 'Batch Bird Reconciliation report'));
    });

    testWidgets('admins: Data checks, the dry run and the repair', (tester) async {
      final api = _api()
        ..gets['/api/Poultry/bird-reconciliation/repair/diagnose'] = [
          {'checkCode': 'MISSING_BATCH_LINK', 'severity': 'Warning', 'flockName': 'Pen 1', 'currentValue': 'none', 'expectedValue': 'B002',
            'proposedCorrection': 'Link to B002', 'doubleApplicationRisk': 'None', 'confidence': 'High', 'evidence': 'Placed from B002', 'autoRepairable': true},
        ]
        ..writeAnswers['/api/Poultry/bird-reconciliation/repair/apply'] = [
          {'checkCode': 'MISSING_BATCH_LINK', 'ledgerRowId': 4, 'applied': false},
        ];
      await open(tester, BatchBirdReconciliationScreen(session: await sessionFor(api), company: _admin), size: phone);
      await see(tester, find.byKey(const ValueKey('recon-run-check')));
      await tester.tap(find.byKey(const ValueKey('recon-run-check')));
      await tester.pumpAndSettle();
      expect(find.text('missing batch link'), findsOneWidget);
      await see(tester, find.byKey(const ValueKey('recon-dry-run')));
      await tester.tap(find.byKey(const ValueKey('recon-dry-run')));
      await tester.pumpAndSettle();
      expect(find.text('Dry run: 1 movement(s) would be linked — Nothing was changed.'), findsOneWidget);
      expect((jsonDecode(api.writes.last.body) as Map)['dryRun'], isTrue);
    });
  });

  group('Reconcile Birds and Add Multiple Batches', () {
    testWidgets('Reconcile Birds posts what the web posts', (tester) async {
      final api = _api();
      await open(tester, BatchReconcileScreen(session: await sessionFor(api), company: company, batchId: 2, batchLabel: 'B002 Broilers', source: 'Batch'), size: phone);
      await see(tester, find.byKey(const ValueKey('reconcile-add-loss')));
      await tester.tap(find.byKey(const ValueKey('reconcile-add-loss')));
      await tester.pumpAndSettle();
      await see(tester, find.byKey(const ValueKey('reconcile-line-0')));
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('reconcile-line-0')), matching: find.byType(TextField)).first, '140');
      await tester.pumpAndSettle();
      await see(tester, find.byKey(const ValueKey('reconcile-still-alive')));
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('reconcile-still-alive')), matching: find.byType(TextField)).first, '200');
      await tester.pumpAndSettle();
      await see(tester, find.byKey(const ValueKey('reconcile-save')));
      await tester.tap(find.byKey(const ValueKey('reconcile-save')));
      await tester.pumpAndSettle();
      final b = api.lastBody('/api/Poultry/bird-reconciliation/batches/2/reconcile');
      expect((b['farmId'], b['batchId'], b['stillUnallocatedLive'], b['source'], '${b['requestKey']}'.isNotEmpty), ('farm-1', 2, 200, 'Batch', true));
      final lines = b['lines'] as List;
      expect((lines.single['quantity'], lines.single['kind']), (140, 'Mortality'));
    });

    testWidgets('Add Multiple Batches: generate, review, one POST with every row', (tester) async {
      final api = FakeApi()..writeAnswers['/api/MainFlockBatch/bulk'] = {'createdCount': 2, 'batches': [], 'errors': []};
      await open(
        tester,
        BulkFlockBatchScreen(session: await sessionFor(api), company: company, existingCodes: const ['B001']),
        size: phone,
      );
      expect(tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('bb-start')), matching: find.byType(TextField)).first).controller!.text, '2',
          reason: 'continues after B001');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('bb-count')), matching: find.byType(TextField)).first, '2');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('bb-birds')), matching: find.byType(TextField)).first, '500');
      await tester.pumpAndSettle();
      await see(tester, find.byKey(const ValueKey('bb-generate')));
      await tester.tap(find.byKey(const ValueKey('bb-generate')));
      await tester.pumpAndSettle();
      await see(tester, find.byKey(const ValueKey('bb-create')));
      await tester.tap(find.byKey(const ValueKey('bb-create')));
      await tester.pumpAndSettle();
      final b = api.lastBody('/api/MainFlockBatch/bulk');
      expect((b['FarmId'], b['Source']), ('farm-1', 'Flock Purchases page'));
      expect([for (final r in b['Batches'] as List) (r['BatchCode'], r['NumberOfBirds'])], [('B002', 500), ('B003', 500)]);
    });
  });
}

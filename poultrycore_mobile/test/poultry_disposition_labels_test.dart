// Broken eggs / dead birds on the daily production form (390 / 391): Keep all,
// Dispose some (with a "Disposed now" count) or Dispose all, labelled, and
// hidden when there is nothing to allocate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/production/production_widgets.dart';

void main() {
  test('the count is the authority; Keep / Disposed only for none / all', () {
    expect(disposedCount(DisposalMode.some, '9', 4), 4, reason: 'capped at the count');
    expect(disposalPayload(DisposalMode.some, '1', 'Keep', 4, 'n', 'd'), {'n': 1});
    expect(disposalPayload(DisposalMode.all, '', 'Keep', 4, 'n', 'd'), {'n': 4, 'd': 'Disposed'});
    expect(disposalPayload(DisposalMode.keep, '', 'Keep', 4, 'n', 'd'), {'n': 0, 'd': 'Keep'});
    expect(disposalPayload(DisposalMode.all, '', '', 4, 'n', 'd'), isEmpty, reason: 'nothing loaded or chosen: nothing sent');
    expect(disposalModeFrom(4, 1, null), (mode: DisposalMode.some, disposed: '1'));
    expect(disposalModeFrom(4, null, 'Disposed'), (mode: DisposalMode.all, disposed: ''), reason: 'an older API: the choice decides');
  });

  testWidgets('labelled, three choices, Disposed now, and hidden when there is nothing to allocate', (tester) async {
    var mode = DisposalMode.keep;
    var disposed = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            DisposalSplitField(
              label: 'Broken Egg Stock allocation',
              count: 4,
              mode: mode,
              disposed: disposed,
              noun: ('broken egg', 'broken eggs'),
              stockName: 'Broken Egg stock',
              onMode: (m) => setState(() => mode = m),
              onDisposed: (v) => setState(() => disposed = v),
            ),
            DisposalSplitField(
              label: 'Dead Bird Stock allocation',
              count: 0,
              mode: DisposalMode.keep,
              disposed: '',
              noun: ('dead bird', 'dead birds'),
              stockName: 'Dead Bird stock',
              onMode: (_) {},
              onDisposed: (_) {},
            ),
          ]),
        ),
      ),
    ));
    expect(find.text('Broken Egg Stock allocation'), findsOneWidget);
    expect(find.text('Dead Bird Stock allocation'), findsNothing, reason: 'no dead birds, no choice');
    expect(find.text('4 broken eggs will be added to Broken Egg stock.'), findsOneWidget);
    await tester.tap(find.text('Dispose some'));
    await tester.pumpAndSettle();
    expect(find.text('Disposed now'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();
    expect(find.text('1 broken egg disposed of; 3 broken eggs added to Broken Egg stock.'), findsOneWidget);
    await tester.tap(find.text('Dispose all'));
    await tester.pumpAndSettle();
    expect(find.text('4 broken eggs recorded and disposed of. Nothing is added to stock.'), findsOneWidget);
    expect(find.text('Disposed now'), findsNothing);
  });
}

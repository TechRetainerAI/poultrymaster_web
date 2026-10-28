// The 26 October pull: each Keep / Disposed choice on the daily production
// form now carries a label naming it, on its own line on a phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/production/production_widgets.dart';

void main() {
  testWidgets('the Keep / Disposed choice is labelled, and hidden when there is nothing to allocate', (tester) async {
    String value = 'Keep';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            DispositionField(
              label: 'Broken Egg Stock allocation',
              count: 4,
              value: value,
              onChanged: (v) => setState(() => value = v),
              keepText: 'Kept as stock',
              disposedText: 'Thrown away',
            ),
            DispositionField(
              label: 'Dead Bird Stock allocation',
              count: 0,
              value: 'Keep',
              onChanged: (_) {},
              keepText: '',
              disposedText: '',
            ),
          ]),
        ),
      ),
    ));
    expect(find.text('Broken Egg Stock allocation'), findsOneWidget);
    expect(find.text('Dead Bird Stock allocation'), findsNothing, reason: 'no dead birds, no choice');
    expect(find.text('Kept as stock'), findsOneWidget);
    await tester.tap(find.text('Disposed immediately'));
    await tester.pumpAndSettle();
    expect(find.text('Thrown away'), findsOneWidget);
  });
}

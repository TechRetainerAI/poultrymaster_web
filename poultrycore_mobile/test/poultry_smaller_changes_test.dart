// Report 30 Part 4, the smaller Poultry changes of the 26 Oct – 2 Nov pull:
// the Supply Purchases tags (Feed Ingredient / Finished Feed / Default) and
// Flock Purchases (Batches) under Setup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poultrycore_mobile/pages/poultry/purchase/raw_materials_screen.dart';
import 'package:poultrycore_mobile/pages/web_nav.dart';

void main() {
  test('Setup → Farm lists Flock Purchases (Batches); Purchase keeps it too', () {
    final groups = webNavGroups['poultry']!;
    final setup = groups.firstWhere((g) => g.subGroups.any((s) => s.title == 'Farm'));
    final farm = setup.subGroups.firstWhere((s) => s.title == 'Farm');
    expect([for (final l in farm.links) l.label], ['Houses', 'Flock Groups', 'Flock Purchases (Batches)']);
    final all = [for (final g in groups) for (final s in g.subGroups) for (final l in s.links) if (l.href == '/flock-batch') l];
    expect(all.length, 2);
  });

  testWidgets('category tags and the Default tag', (tester) async {
    expect(rawCategoryTag('Medication'), isNull, reason: 'other categories stay plain text');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: FieldCard(
            title: 'Layer Mash',
            titleTag: const DefaultItemTag(),
            badge: const SizedBox(),
            extra: [('Category', rawCategoryTag('FinishedFeed')!)],
            fields: const [('Units', 'kg', null)],
            actions: const [],
          ),
        ),
      ),
    ));
    expect(find.text('DEFAULT'), findsOneWidget);
    expect(find.text('Finished Feed'), findsOneWidget);
    expect(find.byTooltip('Set up for you by default. You can edit or delete it like any other item.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

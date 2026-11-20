// Poultry Home → "Quick Actions", the web's card in
// components/dashboard/charts.tsx (the /dashboard page, under the metric
// cards). The 9 Nov pull added Flock Purchases, Record Purchase, Houses and
// Support Videos to its four original buttons.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import 'reports/report_routes.dart' show openAppHref;
import 'flock_form_screen.dart';
import 'production/production_record_form.dart' show productionRecordScreenForHref;

import 'package:poultrycore_mobile/design/tone.dart';

/// (label, href, icon, fill, text colour).
const poultryQuickActions = <(String, String, IconData, Color, Color)>[
  ('Log Production', '/production-records/new', Icons.checklist, Tone.bg(0xFF166534), Colors.white),
  ('Record Sale', '/sales', Icons.attach_money, Tone.bg(0xFFF97316), Colors.white),
  ('Update Expenses', '/expenses', Icons.inventory_2_outlined, Tone.bg(0xFF0EA5E9), Colors.white),
  ('Add Flock', '/flocks/new', Icons.flutter_dash, Tone.bg(0xFFF1F5F9), Tone.fg(0xFF1E293B)),
  ('Flock Purchases', '/flock-batch', Icons.flutter_dash, Tone.bg(0xFFD97706), Colors.white),
  ('Record Purchase', '/poultry-supply-purchases?purchase=1', Icons.shopping_cart_outlined, Tone.bg(0xFF4F46E5), Colors.white),
  ('Houses', '/houses', Icons.apartment_outlined, Tone.bg(0xFF0D9488), Colors.white),
  ('Support Videos', '/poultry-videos', Icons.play_circle_outline, Tone.bg(0xFFDC2626), Colors.white),
];

class PoultryQuickActions extends StatelessWidget {
  const PoultryQuickActions({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  void _open(BuildContext context, String label, String href) {
    final record = productionRecordScreenForHref(href, session, company);
    if (record != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => record));
      return;
    }
    if (href == '/flocks/new') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlockFormScreen(session: session, company: company)));
      return;
    }
    openAppHref(context, session, company, href, label: label);
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('poultry-quick-actions'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tone.bg(0xFFFFFFFF),
          border: Border.all(color: const Tone.line(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Quick Actions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
          const SizedBox(height: 12),
          for (final (label, href, icon, bg, fg) in poultryQuickActions) ...[
            SizedBox(
              height: 56,
              child: FilledButton(
                key: ValueKey('quick-$href'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tone.button(bg),
                  foregroundColor: fg,
                  side: identical(bg, poultryQuickActions[3].$4) ? const BorderSide(color: Tone.line(0xFFE2E8F0)) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => _open(context, label, href),
                child: Row(children: [
                  // The web's Log Production button carries a "0" where the
                  // others have their icon, and its icon on the right.
                  if (href == '/production-records/new')
                    const Text('0', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))
                  else
                    Icon(icon, size: 20),
                  Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                  if (href == '/production-records/new') Icon(icon, size: 20) else const SizedBox(width: 20),
                ]),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ]),
      );
}

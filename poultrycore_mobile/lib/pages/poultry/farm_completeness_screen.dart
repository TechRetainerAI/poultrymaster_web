import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../shared/business_dates.dart';
import '../shared/farm_completeness_card.dart';

/// Poultry → Tools → Farm Completeness, as `app/poultry-farm-completeness/page.tsx`:
/// the Missing Activity Detector opened up, with a day picker so a past day
/// can be checked. The picker is capped at the COMPANY's today (from the
/// report itself, never the phone's clock); today is left for the server to
/// decide, so this page and the dashboard cannot disagree about it.
class FarmCompletenessScreen extends StatefulWidget {
  const FarmCompletenessScreen({super.key, required this.session, required this.company, this.initialDate});
  final Session session;
  final Company company;

  /// A past day to open on, as `?date=` does (Daily Closing's "Resolve").
  final String? initialDate;

  @override
  State<FarmCompletenessScreen> createState() => _FarmCompletenessScreenState();
}

class _FarmCompletenessScreenState extends State<FarmCompletenessScreen> {
  /// The company's today, learned from the first report.
  String? _today;

  /// Null = follow today.
  late String? _picked = toBusinessDate(widget.initialDate);

  String? get _shown {
    final t = _today;
    final p = _picked;
    if (t == null) return p;
    return p != null && p.compareTo(t) < 0 ? p : t;
  }

  bool get _isToday => _today != null && _shown == _today;

  void _choose(String? value) {
    final d = toBusinessDate(value);
    setState(() => _picked = d == null || (_today != null && d.compareTo(_today!) >= 0) ? null : d);
  }

  Future<void> _pickDate() async {
    final today = businessDateAsDateTime(_today) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: businessDateAsDateTime(_shown) ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (d != null) _choose(isoDay(d));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/poultry-farm-completeness');
    final shown = _shown;
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Farm Completeness')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          Text('Expected farm activities that have not been recorded yet.',
              style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
          const SizedBox(height: 12),
          Text('Business date', style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
          const SizedBox(height: 4),
          Row(children: [
            IconButton.outlined(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: shown == null ? null : () => _choose(shiftBusinessDate(shown, -1)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(shown == null ? 'Today' : formatLongDate(shown)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: _isToday || shown == null ? null : () => _choose(shiftBusinessDate(shown, 1)),
            ),
            if (!_isToday && _picked != null)
              TextButton(onPressed: () => setState(() => _picked = null), child: const Text('Today')),
          ]),
          const SizedBox(height: 14),
          FarmCompletenessCard(
            session: widget.session,
            company: widget.company,
            // Today goes unsent: the server decides it.
            businessDate: _isToday || _picked == null ? null : shown,
            defaultExpanded: true,
            onReport: (r) {
              final t = toBusinessDate(r['companyToday']);
              if (t != null && t != _today) setState(() => _today = t);
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../design/ui/inputs.dart';
import '../models/company.dart';
import '../state/session.dart';
import 'lookup_loader.dart';

/// What a web page offers beyond its primary "Add" button and row Edit /
/// Delete — the second button in the header, a per-row action, the filter
/// panel. Keyed by spec key. Each opens a screen that pops with true when it
/// changed data, so the list reloads.

/// A second header button on a list page. Either opens a screen
/// ("Add Multiple Houses/Pens") or runs a one-tap action ("Create default
/// customers") whose message is shown before the list reloads.
class ListExtra {
  const ListExtra(this.label, this.icon, Widget Function(Session, Company, List<Map<String, dynamic>>) this.builder)
      : run = null;
  const ListExtra.action(this.label, this.icon, Future<String> Function(Session, Company) this.run)
      : builder = null;
  final String label;
  final IconData icon;
  final Widget Function(Session session, Company company, List<Map<String, dynamic>> rows)? builder;
  final Future<String> Function(Session session, Company company)? run;
}

/// A button on one record's screen, e.g. Staff → "Attendance".
class RecordExtra {
  const RecordExtra(this.label, this.icon, this.builder, {this.when});
  final String label;
  final IconData icon;
  final Widget Function(Session session, Company company, Map<String, dynamic> row) builder;

  /// Only for rows this is true for, as the web hides some row buttons
  /// (Products: Recipe only when the product needs one).
  final bool Function(Map<String, dynamic> row)? when;
}

/// Work a page does before listing, as the web's load() does (Products:
/// make sure the default Eggs and Birds products exist). Failures are
/// ignored, as on the web.
typedef BeforeLoad = Future<void> Function(Session session, Company company);

/// Whether one row may be deleted, for pages where the web hides Delete on
/// some rows (Water's system-generated customers).
typedef DeleteGuard = bool Function(Map<String, dynamic> row);

/// One dropdown in a list's Filters panel. The first option ('') is "All".
class ListFilter {
  const ListFilter({
    required this.key,
    required this.label,
    required this.allLabel,
    required this.options,
    required this.matches,
  });
  final String key;
  final String label;
  final String allLabel;
  final Future<List<AppSelectItem<String>>> Function(
      Session session, Company company, List<Map<String, dynamic>> rows) options;
  final bool Function(Map<String, dynamic> row, String value) matches;
}

/// A farm-scoped list fetch for filter options and the like.
Future<List<Map<String, dynamic>>> fetchRows(Session s, Company c, String path) async {
  final res = await s.farmClient.get(path, query: {
    'farmId': c.farmId,
    'userId': s.tokens.userId ?? '',
  });
  return [
    for (final r in LookupLoader.rowsIn(res))
      if (r is Map) Map<String, dynamic>.from(r),
  ];
}

/// The web's filter panel as a bottom sheet: one dropdown per filter, then
/// Reset and Apply. Returns the chosen values, or null when dismissed.
Future<Map<String, String>?> showListFilters(
  BuildContext context, {
  required Session session,
  required Company company,
  required List<ListFilter> filters,
  required List<Map<String, dynamic>> rows,
  required Map<String, String> current,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(
      session: session,
      company: company,
      filters: filters,
      rows: rows,
      current: current,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.session,
    required this.company,
    required this.filters,
    required this.rows,
    required this.current,
  });
  final Session session;
  final Company company;
  final List<ListFilter> filters;
  final List<Map<String, dynamic>> rows;
  final Map<String, String> current;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, String> _values = Map.of(widget.current);
  final Map<String, List<AppSelectItem<String>>> _options = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.filters) {
      f.options(widget.session, widget.company, widget.rows).then((items) {
        if (mounted) setState(() => _options[f.key] = items);
      }).catchError((_) {
        if (mounted) setState(() => _options[f.key] = const []);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final f in widget.filters) ...[
              Text(f.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              AppSelect<String>(
                value: _options[f.key] == null ? null : (_values[f.key] ?? ''),
                enabled: _options[f.key] != null,
                hintText: _options[f.key] == null ? 'Loading…' : f.allLabel,
                items: [
                  AppSelectItem(value: '', label: f.allLabel),
                  ...?_options[f.key],
                ],
                onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(<String, String>{}),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                        {for (final e in _values.entries) if (e.value.isNotEmpty) e.key: e.value}),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

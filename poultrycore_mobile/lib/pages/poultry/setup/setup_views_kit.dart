// Pieces the redesigned Farm Setup views share (9 Nov pull):
//   * RecordsPager   = components/ui/data-pagination.tsx, variant "records"
//   * ViewSwitch     = the Cards / Table switch, remembered on this phone
//   * SetupSearch    = the search box in a view's tools row
//   * pagedSlice     = hooks/use-pagination.ts

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design/ui/inputs.dart';

import 'package:poultrycore_mobile/design/tone.dart';

/// TRACKER_PAGE_SIZE_OPTIONS.
const recordPageSizes = [5, 10, 15, 25, 50, 100];

/// One page of [items] (1-based [page], clamped to the last page).
({List<T> items, int page, int pages}) pagedSlice<T>(List<T> items, int page, int pageSize) {
  final pages = items.isEmpty ? 1 : ((items.length + pageSize - 1) ~/ pageSize);
  final p = page.clamp(1, pages);
  final start = (p - 1) * pageSize;
  return (items: items.sublist(start, (start + pageSize).clamp(0, items.length)), page: p, pages: pages);
}

/// "Showing 1 to 10 of 23 records", the page size, and Previous · 3 / 12 · Next
/// (the web shows "3 / 12" between the arrows on a phone). Hidden with no rows.
class RecordsPager extends StatelessWidget {
  const RecordsPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
  });
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final pages = ((total + pageSize - 1) ~/ pageSize).clamp(1, 1 << 30);
    final first = (page - 1) * pageSize + 1;
    final last = (page * pageSize).clamp(0, total);
    return Container(
      key: const ValueKey('records-pager'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(color: _slate50, border: Border(top: BorderSide(color: _slate200))),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
          Text('Showing $first to $last of $total records', style: const TextStyle(fontSize: 13, color: _slate600)),
          SizedBox(
            width: 120,
            child: AppSelect<int>(
              value: pageSize,
              items: [for (final n in recordPageSizes) AppSelectItem(value: n, label: '$n / page')],
              onChanged: (v) {
                if (v == null) return;
                onPageSize(v);
                onPage(1);
              },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            onPressed: page <= 1 ? null : () => onPage(page - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Previous'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$page / $pages', style: const TextStyle(fontSize: 13, color: _slate600)),
          ),
          TextButton.icon(
            onPressed: page >= pages ? null : () => onPage(page + 1),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
        ]),
        ),
      ]),
    );
  }
}

enum SetupView { cards, table }

/// Reads a view's remembered Cards / Table choice (the web's localStorage key).
Future<SetupView?> loadSetupView(String key) async {
  try {
    final v = (await SharedPreferences.getInstance()).getString(key);
    return v == 'table' ? SetupView.table : v == 'cards' ? SetupView.cards : null;
  } catch (_) {
    return null;
  }
}

Future<void> saveSetupView(String key, SetupView v) async {
  try {
    await (await SharedPreferences.getInstance()).setString(key, v.name);
  } catch (_) {
    // This visit only.
  }
}

/// The Cards / Table switch.
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({super.key, required this.value, required this.onChanged});
  final SetupView value;
  final ValueChanged<SetupView> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, icon, label) in const [
            (SetupView.cards, Icons.grid_view_outlined, 'Cards'),
            (SetupView.table, Icons.view_list_outlined, 'Table'),
          ])
            InkWell(
              key: ValueKey('view-${v.name}'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: value == v ? Tone.button(const Tone.bg(0xFF2563EB)) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 16, color: value == v ? Colors.white : _slate600),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: value == v ? Colors.white : _slate600)),
                ]),
              ),
            ),
        ]),
      );
}

/// The search box of a view's tools row.
class SetupSearch extends StatelessWidget {
  const SetupSearch({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => AppInput(
        key: const ValueKey('setup-search'),
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18, color: Tone.fg(0xFF94A3B8)),
        onChanged: onChanged,
      );
}

/// A rounded white card with a thin border.
class SetupCard extends StatelessWidget {
  const SetupCard({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        padding: padding,
        decoration: BoxDecoration(
          color: const Tone.bg(0xFFFFFFFF),
          border: Border.all(color: _slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

/// A thin used / capacity bar: emerald, amber from 80%, red at 100%.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: _slate100)),
            FractionallySizedBox(
              widthFactor: (pct.clamp(0, 100)) / 100,
              child: ColoredBox(
                color: pct >= 100 ? const Tone.bg(0xFFEF4444) : pct >= 80 ? const Tone.bg(0xFFF59E0B) : const Tone.bg(0xFF10B981),
              ),
            ),
          ]),
        ),
      );
}

const _slate50 = Tone.bg(0xFFF8FAFC);
const _slate100 = Tone.bg(0xFFF1F5F9);
const _slate200 = Tone.line(0xFFE2E8F0);
const _slate600 = Tone.fg(0xFF475569);

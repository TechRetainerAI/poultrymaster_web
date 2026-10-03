import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/dashboard_api.dart';
import '../models/company.dart';
import '../design/tokens.dart';
import '../design/web_mobile.dart';
import '../state/session.dart';
import '../widgets/app_header.dart';
import '../widgets/company_switcher_sheet.dart';

/// The company overview, laid out as the web lays it out on a phone: dark
/// header, dark company strip, then a two-column grid of stat cards with
/// uppercase labels, large figures and coloured icon tiles.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.onSignedOut,
    this.onMenu,
  });

  final Session session;
  final VoidCallback onSignedOut;

  /// The hamburger: the sidebar drawer for Poultry, the "All pages" sheet for
  /// the other company types (see AppShell._openMenu).
  final VoidCallback? onMenu;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final company = widget.session.active;
    if (company == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.session.dashboard.load(company);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // 409 is the platform's "wrong company type for this module" guard.
        _error = e.statusCode == 409
            ? 'This company type does not expose that module.'
            : e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the dashboard.';
        _loading = false;
      });
    }
  }

  Future<void> _switchCompany() async {
    final changed = await showCompanySwitcher(context, widget.session);
    if (changed && mounted) _load();
  }

  static IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('customer')) return Icons.group_outlined;
    if (l.contains('egg')) return Icons.egg_outlined;
    if (l.contains('flock') || l.contains('bird')) return Icons.pets_outlined;
    if (l.contains('production') || l.contains('produced')) return Icons.show_chart;
    if (l.contains('sale') || l.contains('revenue')) return Icons.attach_money;
    if (l.contains('month')) return Icons.trending_up;
    if (l.contains('average')) return Icons.inventory_2_outlined;
    if (l.contains('efficien')) return Icons.check_box_outlined;
    if (l.contains('expense') || l.contains('cost')) return Icons.receipt_long_outlined;
    if (l.contains('profit')) return Icons.savings_outlined;
    if (l.contains('feed')) return Icons.grass_outlined;
    if (l.contains('death') || l.contains('mortal')) return Icons.warning_amber_rounded;
    return Icons.insights_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final company = session.active;
    final tokens = context.tokens;

    if (company == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final metrics = _data?.metrics ?? const <Metric>[];

    return Scaffold(
      backgroundColor: tokens.card,
      appBar: WebAppHeader(
        onMenu: widget.onMenu ?? () {},
        onAvatar: _switchCompany,
      ),
      body: Column(
        children: [
          CompanyBar(company: company, onTap: _switchCompany),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const _SkeletonGrid()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      children: [
                        if (_error != null)
                          _ErrorCard(message: _error!, onRetry: _load)
                        else ...[
                          if (_data?.note != null) ...[
                            _NoteCard(text: _data!.note!),
                            const SizedBox(height: 12),
                          ],
                          if (metrics.isEmpty)
                            _NoteCard(
                              text:
                                  'The ${company.type.label} summary returned no figures for this company yet.',
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.32,
                              ),
                              itemCount: metrics.length,
                              itemBuilder: (context, i) {
                                final m = metrics[i];
                                final v = m.value;
                                final text = v is num
                                    ? (m.isMoney ? ghc(v) : _thousands(v))
                                    : '$v';
                                return WebStatCard(
                                  label: m.label,
                                  value: text,
                                  hint: m.hint,
                                  icon: _iconFor(m.label),
                                  tint: WebMobile.tile(i),
                                );
                              },
                            ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static String _thousands(num v) {
    final s = v is int || v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    final neg = s.startsWith('-');
    final digits = neg ? s.substring(1) : s;
    final parts = digits.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
  }
}

/// The web shows grey placeholder cards while the summary loads; this mirrors
/// that rather than a bare spinner, so the layout does not jump.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: 8,
      itemBuilder: (context, i) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(Dim.radiusXl),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in [0.85, 0.95, 0.55]) ...[
              FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 9),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.muted,
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.mutedForeground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: tokens.mutedForeground)),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.destructive.withValues(alpha: .07),
        border: Border.all(color: tokens.destructive.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(Dim.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.error_outline, size: 18, color: tokens.destructive),
            const SizedBox(width: 8),
            const Text('Could not load',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

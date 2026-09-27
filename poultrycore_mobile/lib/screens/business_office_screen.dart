import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/ui/inputs.dart';
import '../models/company.dart';
import '../state/session.dart';
import '../widgets/company_type_badge.dart';

/// The company-neutral landing, matching `/business-office` on the web.
///
/// Everyone lands here after signing in — no company is selected yet (Doc 3
/// §4/§9) — and picks one from the list. The orange header, the type counts
/// and the company list are the web's, including its wording.
class BusinessOfficeScreen extends StatefulWidget {
  const BusinessOfficeScreen({
    super.key,
    required this.session,
    required this.onPicked,
    required this.onSignedOut,
  });

  final Session session;
  final VoidCallback onPicked;
  final VoidCallback onSignedOut;

  @override
  State<BusinessOfficeScreen> createState() => _BusinessOfficeScreenState();
}

class _BusinessOfficeScreenState extends State<BusinessOfficeScreen> {
  String _query = '';
  CompanyType? _typeFilter;
  bool _switching = false;


  Future<void> _open(Company c) async {
    setState(() => _switching = true);
    final ok = await widget.session.setActive(c);
    if (!mounted) return;
    setState(() => _switching = false);
    if (ok) {
      widget.onPicked();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.session.error ?? 'Could not open that company.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final tokens = context.tokens;
    final all = session.myCompanies;

    final counts = <CompanyType, int>{};
    for (final c in all) {
      counts[c.type] = (counts[c.type] ?? 0) + 1;
    }

    final q = _query.trim().toLowerCase();
    final visible = all.where((c) {
      if (_typeFilter != null && c.type != _typeFilter) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // slate-50
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              userName: session.username ?? '',
              officeName: session.organisationName ?? 'Business Office',
              isAdmin: all.any((c) => c.isAdmin),
              onSignOut: () async {
                await session.signOut();
                widget.onSignedOut();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: session.loadCompanies,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    // "Select a company…" — the web's own selector.
                    _SelectorBar(
                      label: session.active?.name ?? 'Select a company…',
                      onTap: () {},
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Icon(Icons.campaign_outlined,
                            size: 16, color: tokens.mutedForeground),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'VISIBILITYCORE ANNOUNCEMENTS',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .4,
                              color: tokens.mutedForeground,
                            ),
                          ),
                        ),
                        _SmallButton(
                          icon: Icons.add,
                          label: 'Post',
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                                  content: Text('Posting is on the web.'))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Dashed empty card, as the web renders it.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Dim.radiusLg),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0)), // slate-200
                      ),
                      child: Text('No new notifications.',
                          style: TextStyle(
                              fontSize: 13.5, color: tokens.mutedForeground)),
                    ),
                    const SizedBox(height: 18),

                    _CountGrid(total: all.length, counts: counts),
                    const SizedBox(height: 22),

                    const Text('Your companies',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    AppSearchField(
                      hintText: 'Search companies…',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 10),
                    _TypeFilter(
                      value: _typeFilter,
                      counts: counts,
                      onChanged: (t) => setState(() => _typeFilter = t),
                    ),
                    const SizedBox(height: 14),

                    if (session.busy && all.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            all.isEmpty
                                ? 'No companies are linked to this account.'
                                : 'No companies match that filter.',
                            style: TextStyle(color: tokens.mutedForeground),
                          ),
                        ),
                      )
                    else
                      for (final c in visible) ...[
                        _CompanyCard(
                          company: c,
                          busy: _switching,
                          onTap: _switching ? null : () => _open(c),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Orange bar: greeting, office name and role, bell / avatar / help.
class _Header extends StatelessWidget {
  const _Header({
    required this.userName,
    required this.officeName,
    required this.isAdmin,
    required this.onSignOut,
  });

  final String userName;
  final String officeName;
  final bool isAdmin;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF97316), // orange-500
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(Dim.radiusMd),
            ),
            child: const Icon(Icons.menu, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome, ${userName.isEmpty ? "there" : userName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  '$officeName · ${isAdmin ? "Organization Admin" : "Staff"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .92), fontSize: 11.5),
                ),
              ],
            ),
          ),
          const Icon(Icons.notifications_none, size: 21, color: Colors.white),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) {
              if (v == 'signout') onSignOut();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
            child: Container(
              height: 30,
              width: 30,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Text(
                userName.isEmpty ? '?' : userName.characters.first.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFFF97316),
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.help_outline, size: 20, color: Colors.white),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _SelectorBar extends StatelessWidget {
  const _SelectorBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Dim.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusMd),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(Icons.apartment_outlined,
                  size: 17, color: tokens.mutedForeground),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: tokens.mutedForeground)),
              ),
              Icon(Icons.keyboard_arrow_down,
                  size: 19, color: tokens.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

/// Companies / Water / Poultry / Generic / Hotel counts.
class _CountGrid extends StatelessWidget {
  const _CountGrid({required this.total, required this.counts});

  final int total;
  final Map<CompanyType, int> counts;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _CountTile(
        label: 'Companies',
        value: total,
        icon: Icons.apartment_outlined,
        tint: const Color(0xFF64748B),
        bg: const Color(0xFFF1F5F9),
      ),
      for (final t in [
        CompanyType.water,
        CompanyType.poultry,
        CompanyType.generic,
        CompanyType.hotel,
      ])
        _CountTile(
          label: t.label,
          value: counts[t] ?? 0,
          icon: CompanyTypeBadge.iconFor(t),
          tint: TypeColors.accent(t),
          bg: TypeColors.accent(t).withValues(alpha: .12),
        ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.bg,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color tint;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dim.radiusXl),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Dim.radiusLg),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text('$value',
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: Color(0xFF0F172A))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final CompanyType? value;
  final Map<CompanyType, int> counts;
  final ValueChanged<CompanyType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final types = [
      for (final t in CompanyType.values)
        if (t != CompanyType.unknown && (counts[t] ?? 0) > 0) t
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: 'All types',
            selected: value == null,
            onTap: () => onChanged(null),
          ),
          for (final t in types) ...[
            const SizedBox(width: 8),
            _Chip(
              label: '${t.label} (${counts[t]})',
              selected: value == t,
              color: TypeColors.accent(t),
              onTap: () => onChanged(value == t ? null : t),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? const Color(0xFF475569);
    return Material(
      color: selected ? accent.withValues(alpha: .12) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? accent : const Color(0xFFE2E8F0)),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : const Color(0xFF475569),
              )),
        ),
      ),
    );
  }
}

/// A company in the list, with the coloured top edge the web draws.
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.company,
    required this.busy,
    required this.onTap,
  });

  final Company company;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = TypeColors.accent(company.type);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Dim.radiusXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusXl),
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusXl),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Container(height: 4, color: accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      height: 38,
                      width: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(Dim.radiusLg),
                      ),
                      child: Icon(CompanyTypeBadge.iconFor(company.type),
                          size: 19, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(company.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              CompanyTypeBadge(type: company.type),
                              if (company.role != null) ...[
                                const SizedBox(width: 7),
                                Text(company.role!,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF64748B))),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (busy)
                      const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.chevron_right,
                          size: 20, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Dim.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dim.radiusMd),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Dim.radiusMd),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF334155)),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155))),
            ],
          ),
        ),
      ),
    );
  }
}

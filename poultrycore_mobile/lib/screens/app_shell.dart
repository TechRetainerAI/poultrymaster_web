import 'package:flutter/material.dart';

import '../models/company.dart';
import '../models/module.dart';
import '../state/session.dart';
import '../widgets/all_pages_sheet.dart';
import 'dashboard_screen.dart';
import 'module_placeholder_screen.dart';

/// The signed-in shell, matching the web's `mobile-bottom-nav.tsx`.
///
/// The bar is a solid company-coloured surface with four tabs plus More —
/// the same four the web puts there, so a phone user builds the same habits as
/// on a laptop. "More" is a whole navigation tree with its own search, which is
/// how the web describes it: "not an overflow bin".
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.session, required this.onSignedOut});

  final Session session;
  final VoidCallback onSignedOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final company = session.active;
    if (company == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = Modules.mainTabs(company.type);
    final nav = NavTheme.forType(company.type);

    final pages = <Widget>[
      DashboardScreen(
        session: session,
        onSignedOut: widget.onSignedOut,
        onMenu: () => _openMore(context, company.type),
      ),
      for (final m in tabs.skip(1))
        pageFor(module: m, company: company, session: session),
    ];

    return Scaffold(
      body: IndexedStack(index: _index.clamp(0, pages.length - 1), children: pages),
      bottomNavigationBar: _BottomBar(
        theme: nav,
        tabs: tabs,
        selected: _index,
        onSelect: (i) => setState(() => _index = i),
        onMore: () => _openMore(context, company.type),
      ),
    );
  }

  /// The web's "All pages" panel.
  void _openMore(BuildContext context, CompanyType type) {
    showAllPages(context, widget.session, widget.session.active!);
  }
}

/// The coloured bar itself.
///
/// Per the web: solid company colour, a darker top border, 22px icons, 10px
/// labels, and an `h-7 w-12` white/20 pill behind the active icon. Items are
/// `min-h-[44px]`; this uses 56 so the whole target clears 48dp.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.theme,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onMore,
  });

  final NavTheme theme;
  final List<AppModule> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.bar,
        border: Border(top: BorderSide(color: theme.borderTop)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _BarItem(
                  theme: theme,
                  icon: tabs[i].icon,
                  label: tabs[i].label,
                  active: i == selected,
                  onTap: () => onSelect(i),
                ),
              _BarItem(
                theme: theme,
                icon: Icons.more_horiz,
                label: 'More',
                active: false,
                onTap: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.theme,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final NavTheme theme;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : theme.inactive;

    return Expanded(
      child: Semantics(
        label: label,
        selected: active,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // h-7 w-12 rounded-full bg-white/20 behind the active icon
              Container(
                height: 28,
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.white.withValues(alpha: .20) : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 4), // gap-1
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

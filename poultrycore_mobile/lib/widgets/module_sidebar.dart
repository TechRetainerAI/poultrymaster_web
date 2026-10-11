import 'package:flutter/material.dart';

import '../api/quick_links_api.dart';
import '../models/company.dart';
import '../pages/list_screen.dart';
import '../pages/module_registry.dart';
import '../pages/registry.dart';
import '../pages/web_nav.dart';
import '../pages/web_page_screen.dart';
import '../state/session.dart';
import 'quick_links_dialog.dart';

/// The web's sidebar as it appears on a phone, for Poultry, Water and Restaurant (`components/dashboard/sidebar.tsx`,
/// the `lg:hidden` drawer): a slate-900 panel that slides in from the left,
/// 85% of the screen wide and never more than 320, over a black/50 backdrop.
///
/// Same order as the web: Business Office, Dashboard, then one collapsible
/// section per top-nav menu (Quick Links, Operations, Sales Expenses & Money,
/// Trackers, Reports, Tools, Setup), System, and Logout pinned at the foot.
/// Sections start closed; a multi-column menu shows its columns as uppercase
/// sub-headings that collapse on their own, and a one-column menu shows its
/// rows directly, as the web does.
Future<void> showModuleSidebar(
  BuildContext context, {
  required Session session,
  required Company company,
  VoidCallback? onSignedOut,
  String? activeHref,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close sidebar',
    barrierColor: Colors.black.withValues(alpha: .5),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.centerLeft,
      child: _PoultrySidebar(
        session: session,
        company: company,
        onSignedOut: onSignedOut,
        activeHref: activeHref,
      ),
    ),
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
      child: child,
    ),
  );
}

/// The web route a spec is reached from, so a page can tell the sidebar
/// which row is "you are here".
String? hrefForSpec(String specKey, Company company) {
  for (final g in webNavGroups[PageRegistry.moduleOf(company.type)] ?? const <NavGroup>[]) {
    if (g.title == 'Quick Links') continue;
    for (final s in g.subGroups) {
      for (final l in s.links) {
        if (l.specKey == specKey) return l.href;
      }
    }
  }
  return null;
}

/// The left side of every pushed Poultry page's header: the back arrow AND
/// the sidebar button, so the sidebar is one tap away from any page as it is
/// on the web, without losing the way back. A page that is a bottom tab has
/// nothing to go back to and shows the sidebar button alone.
///
/// Other company types get the default leading (null), unchanged.
({Widget? leading, double? width}) sidebarLeading(
  BuildContext context,
  Session? session,
  Company company, {
  String? specKey,
  String? href,
}) {
  if (session == null || !hasSidebar(company.type)) {
    return (leading: null, width: null);
  }
  final canPop = Navigator.of(context).canPop();
  final active = href ?? (specKey == null ? null : hrefForSpec(specKey, company));
  return (
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop) const BackButton(),
        IconButton(
          tooltip: 'Open sidebar',
          icon: const Icon(Icons.menu),
          onPressed: () => showModuleSidebar(
            context,
            session: session,
            company: company,
            activeHref: active,
          ),
        ),
      ],
    ),
    width: canPop ? 100 : 56,
  );
}

/// Company types that have the web's sidebar ported. Others keep the
/// "All pages" sheet until they are done.
bool hasSidebar(CompanyType type) =>
    type == CompanyType.poultry ||
    type == CompanyType.water ||
    type == CompanyType.restaurant;

/// Nav groups that exist only for the All pages sheet — pages the web's
/// sidebar does not list (Water's individual reports, Restaurant's top-nav
/// extras). The sidebar skips them so it shows exactly what the web shows.
const sheetOnlyGroups = {'Report pages', 'More pages'};

/// Opens a nav link the way every menu in the app does: its list screen when
/// the page has an API spec, the real web page otherwise.
void openNavLink(
  NavigatorState nav,
  NavLink link,
  Session session,
  Company company,
) {
  final screen = pageScreens[link.href];
  if (screen != null) {
    nav.push(MaterialPageRoute(builder: (_) => screen(session, company)));
    return;
  }
  final spec = link.specKey == null ? null : PageRegistry.of(link.specKey!);
  nav.push(MaterialPageRoute(
    builder: (_) => spec == null
        ? WebPageScreen(
            label: link.label, href: link.href, company: company, session: session)
        : ListScreen(spec: spec, session: session, company: company),
  ));
}

// Tailwind slate, as the web sidebar uses it.
const _slate900 = Color(0xFF0F172A);
const _slate800 = Color(0xFF1E293B);
const _slate700 = Color(0xFF334155);
const _slate500 = Color(0xFF64748B);
const _slate400 = Color(0xFF94A3B8);
const _slate300 = Color(0xFFCBD5E1);
const _slate200 = Color(0xFFE2E8F0);
const _blue400 = Color(0xFF60A5FA);
const _orange400 = Color(0xFFFB923C);

/// The web's lucide icon for each row, in Material terms.
const Map<String, IconData> _iconByHref = {
  '/production-records': Icons.description_outlined,
  '/batch-production-records': Icons.widgets_outlined,
  '/egg-production': Icons.egg_outlined,
  '/feed-usage': Icons.inventory_2_outlined,
  '/poultry-feed-production': Icons.factory_outlined,
  '/poultry-inventory': Icons.widgets_outlined,
  '/poultry-stock': Icons.widgets_outlined,
  '/poultry-raw-materials': Icons.inventory_outlined,
  '/health': Icons.warning_amber_outlined,
  '/poultry-loss-records': Icons.warning_amber_outlined,
  '/poultry-driver-returns': Icons.local_shipping_outlined,
  '/poultry-driver-report': Icons.bar_chart,
  '/flock-batch': Icons.widgets_outlined,
  '/poultry-raw-materials?purchase=1': Icons.shopping_cart_outlined,
  '/sales': Icons.shopping_cart_outlined,
  '/poultry-payments': Icons.account_balance_wallet_outlined,
  '/customer-balances': Icons.people_outline,
  '/expenses': Icons.attach_money,
  '/poultry-internal-use': Icons.inventory_outlined,
  '/poultry-payroll': Icons.payments_outlined,
  '/poultry-employee-loans': Icons.volunteer_activism_outlined,
  '/supplier-payments': Icons.receipt_long_outlined,
  '/supplier-balances': Icons.local_shipping_outlined,
  '/poultry-deferred-costs': Icons.hourglass_empty,
  '/poultry-assets': Icons.business_outlined,
  '/cash-flow': Icons.account_balance_wallet_outlined,
  '/poultry-financial-activity': Icons.show_chart,
  '/poultry-profit-loss': Icons.trending_up,
  '/poultry-owner-money': Icons.payments_outlined,
  '/poultry-loans': Icons.volunteer_activism_outlined,
  '/poultry-cash-accounts': Icons.account_balance_wallet_outlined,
  '/poultry-cash-transfers': Icons.swap_horiz,
  '/poultry-cash-reconciliation': Icons.balance,
  '/poultry-daily-closing': Icons.event_available_outlined,
  '/egg-tracker': Icons.bar_chart,
  '/feed-tracker': Icons.grass,
  '/feed-inventory-tracker': Icons.history,
  '/birds-left-tracker': Icons.flutter_dash,
  '/medication-tracker': Icons.medication_outlined,
  '/weekly-report': Icons.description_outlined,
  '/feed-ingredient-tracker': Icons.grass,
  '/reports': Icons.bar_chart,
  '/poultry/reports': Icons.menu_book_outlined,
  '/poultry-farm-setup': Icons.auto_awesome_outlined,
  '/poultry-farm-completeness': Icons.fact_check_outlined,
  '/poultry-feed-distribution': Icons.grass,
  '/poultry-days-of-supply': Icons.inventory_2_outlined,
  '/poultry-setup': Icons.settings_outlined,
  '/poultry-company-setup': Icons.settings_outlined,
  '/poultry-financial-settings': Icons.toll_outlined,
  '/companies': Icons.business_outlined,
  '/poultry-drivers': Icons.groups_outlined,
  '/poultry-vehicles': Icons.local_shipping_outlined,
  '/poultry-routes': Icons.local_shipping_outlined,
  '/poultry-products': Icons.inventory_2_outlined,
  '/poultry-feed-formulas': Icons.grass,
  '/business-office/egg-pick-settings': Icons.schedule,
  '/customers': Icons.people_outline,
  '/suppliers': Icons.local_shipping_outlined,
  '/houses': Icons.business_outlined,
  '/flocks': Icons.flutter_dash,
  '/poultry-staff': Icons.groups_outlined,
  '/employees': Icons.manage_accounts_outlined,
  '/profile': Icons.person_outline,
  '#alerts': Icons.notifications_none,
  '/billing': Icons.credit_card,
  '/audit-logs': Icons.show_chart,
  '/resources': Icons.menu_book_outlined,
  '/help': Icons.help_outline,
  '/terms': Icons.checklist,
  // Water
  '/water-production-batches': Icons.factory_outlined,
  '/water-daily-production': Icons.calendar_month_outlined,
  '/water-maintenance': Icons.build_outlined,
  '/water-stock': Icons.widgets_outlined,
  '/water-inventory': Icons.widgets_outlined,
  '/water-raw-materials': Icons.inventory_outlined,
  '/water-loss-records': Icons.warning_amber_outlined,
  '/water-production-losses': Icons.warning_amber_outlined,
  '/water-driver-returns': Icons.local_shipping_outlined,
  '/water-driver-report': Icons.bar_chart,
  '/water-sales': Icons.shopping_cart_outlined,
  '/water-payments': Icons.credit_card,
  '/water-customer-balances': Icons.people_outline,
  '/water-expenses': Icons.receipt_long_outlined,
  '/water-internal-use': Icons.inventory_outlined,
  '/water-payroll': Icons.payments_outlined,
  '/water-employee-loans': Icons.volunteer_activism_outlined,
  '/water-supplier-payments': Icons.receipt_long_outlined,
  '/water-supplier-balances': Icons.local_shipping_outlined,
  '/water-deferred-costs': Icons.hourglass_empty,
  '/water-assets': Icons.business_outlined,
  '/water-cash-flow': Icons.account_balance_wallet_outlined,
  '/water-profit-loss': Icons.trending_up,
  '/water-owner-money': Icons.payments_outlined,
  '/water-loans': Icons.volunteer_activism_outlined,
  '/water-cash-accounts': Icons.account_balance_wallet_outlined,
  '/water-cash-transfers': Icons.swap_horiz,
  '/water-cash-reconciliation': Icons.balance,
  '/water-daily-closing': Icons.description_outlined,
  '/water-inventory-tracker': Icons.history,
  '/water-reports': Icons.bar_chart,
  '/water-setup': Icons.settings_outlined,
  '/water-company-setup': Icons.settings_outlined,
  '/water-financial-settings': Icons.toll_outlined,
  '/water-drivers': Icons.groups_outlined,
  '/water-vehicles': Icons.local_shipping_outlined,
  '/water-routes': Icons.local_shipping_outlined,
  '/water-products': Icons.shopping_bag_outlined,
  '/water-customers': Icons.people_outline,
  '/water-suppliers': Icons.local_shipping_outlined,
  '/water-machines': Icons.precision_manufacturing_outlined,
  '/water-boreholes': Icons.water_outlined,
  '/water-staff': Icons.groups_outlined,
  // Restaurant
  '/restaurant-sales': Icons.shopping_cart_outlined,
  '/restaurant-tills': Icons.calculate_outlined,
  '/restaurant-expenses': Icons.attach_money,
  '/restaurant-cash-flow': Icons.account_balance_wallet_outlined,
  '/restaurant-profit-loss': Icons.trending_up,
  '/restaurant-daily-closing': Icons.event_available_outlined,
  '/restaurant-pos': Icons.point_of_sale,
  '/restaurant-pending-orders': Icons.inbox_outlined,
  '/restaurant-orders': Icons.description_outlined,
  '/restaurant-kds': Icons.show_chart,
  '/restaurant-floor-plan': Icons.business_outlined,
  '/restaurant-reservations': Icons.calendar_month_outlined,
  '/restaurant-online-orders': Icons.shopping_bag_outlined,
  '/restaurant-delivery': Icons.local_shipping_outlined,
  '/restaurant-inventory': Icons.widgets_outlined,
  '/restaurant-payments': Icons.account_balance_wallet_outlined,
  '/restaurant-customer-balances': Icons.people_outline,
  '/restaurant-internal-use': Icons.inventory_outlined,
  '/restaurant-payroll': Icons.payments_outlined,
  '/restaurant-staff-loans': Icons.volunteer_activism_outlined,
  '/restaurant-supplier-payments': Icons.receipt_long_outlined,
  '/restaurant-supplier-balances': Icons.local_shipping_outlined,
  '/restaurant-deferred-costs': Icons.hourglass_empty,
  '/restaurant-assets': Icons.business_outlined,
  '/restaurant-financial-activity': Icons.show_chart,
  '/restaurant-owner-money': Icons.payments_outlined,
  '/restaurant-loans': Icons.volunteer_activism_outlined,
  '/restaurant-cash-accounts': Icons.account_balance_wallet_outlined,
  '/restaurant-cash-transfers': Icons.swap_horiz,
  '/restaurant-cash-reconciliation': Icons.balance,
  '/restaurant-crm': Icons.people_outline,
  '/restaurant-loyalty': Icons.credit_card,
  '/restaurant-events': Icons.calendar_month_outlined,
  '/restaurant-gift-cards': Icons.card_giftcard,
  '/restaurant-notifications': Icons.notifications_none,
  '/restaurant-reports': Icons.bar_chart,
  '/restaurant-menu': Icons.restaurant_menu,
  '/restaurant-staff': Icons.manage_accounts_outlined,
  '/restaurant-setup': Icons.settings_outlined,
  '/business-office/billing': Icons.credit_card,
};

/// "System Alerts and Notifications" (components/dashboard/charts.tsx). The
/// web's alerts store is never filled, so it always reads "No alerts".
Future<void> showSystemAlertsDialog(BuildContext context, {List<({String title, String? description, String? time})> alerts = const []}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('System Alerts and Notifications'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (alerts.isEmpty)
            const Text('No alerts', style: TextStyle(color: Color(0xFF475569)))
          else
            for (final a in alerts)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
                  if (a.description != null) Text(a.description!, style: const TextStyle(fontSize: 14, color: Color(0xFF475569))),
                  if (a.time != null) Text(a.time!, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ]),
              ),
        ]),
      ),
    );

/// The sidebar's icon for a row, for the Quick Links picker.
IconData sidebarIconFor(String href) => _iconByHref[href] ?? Icons.insert_chart_outlined;

const Map<String, IconData> _menuIcons = {
  'Quick Links': Icons.star_border,
  'Operations': Icons.factory_outlined,
  'Sales, Expenses & Money': Icons.account_balance_wallet_outlined,
  'Trackers': Icons.bar_chart,
  'Reports': Icons.bar_chart,
  'Tools': Icons.build_outlined,
  'Setup': Icons.settings_outlined,
  'System': Icons.person_outline,
};

class _PoultrySidebar extends StatefulWidget {
  const _PoultrySidebar({
    required this.session,
    required this.company,
    this.onSignedOut,
    this.activeHref,
  });

  final Session session;
  final Company company;
  final VoidCallback? onSignedOut;

  /// The page the sidebar was opened from. Its row is highlighted and its
  /// menu starts open, as the web opens the menu holding the current page.
  /// Null means the Dashboard.
  final String? activeHref;

  @override
  State<_PoultrySidebar> createState() => _PoultrySidebarState();
}

class _PoultrySidebarState extends State<_PoultrySidebar> {
  /// Open menus. Closed by default, as the web drawer opens only the menu
  /// holding the current page — and the drawer is opened from the Dashboard.
  late final _openMenus = <String>{
    for (final g in _groups)
      if (g.title != 'Quick Links' &&
          g.subGroups.any((s) => s.links.any((l) => l.href == widget.activeHref)))
        g.title,
  };

  /// Sub-groups the user has closed. The web reads an absent entry as open.
  final _closedSubs = <String>{};

  /// The generated nav, with the default Quick Links.
  late final List<NavGroup> _base = webNavGroups[PageRegistry.moduleOf(widget.company.type)] ?? const [];

  /// The user's stored Quick Links (318). Null = never customised, so the
  /// defaults stand; an empty list = they cleared the bar.
  List<String>? _quickHrefs;

  /// The nav as shown: Quick Links resolved from the user's choice.
  List<NavGroup> get _groups => [
        for (final g in _base)
          g.title == 'Quick Links' ? NavGroup(g.title, [NavSubGroup('', resolveQuickLinks(_base, _quickHrefs))]) : g,
      ];

  /// Poultry and Water put "Customise…" at the foot of Quick Links, as the web does.
  bool get _customisable => widget.company.type == CompanyType.poultry || widget.company.type == CompanyType.water;

  @override
  void initState() {
    super.initState();
    _loadQuickLinks();
  }

  Future<void> _loadQuickLinks() async {
    final saved = await QuickLinksApi(widget.session.farmClient).get(
      userId: widget.session.tokens.userId,
      farmId: widget.company.farmId,
    );
    if (!mounted || saved == null || !saved.customised) return;
    setState(() => _quickHrefs = saved.hrefs);
  }

  Future<void> _customise() async {
    final r = await showQuickLinksDialog(
      context,
      farmClient: widget.session.farmClient,
      userId: widget.session.tokens.userId ?? '',
      farmId: widget.company.farmId,
      groups: _base,
      stored: _quickHrefs,
      iconFor: sidebarIconFor,
    );
    if (r != null && mounted) setState(() => _quickHrefs = r.hrefs);
  }

  Widget _customiseRow() => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _Row(icon: Icons.settings_outlined, label: 'Customise…', onTap: _customise),
      );

  void _go(NavLink link) {
    if (link.href == '#alerts') {
      showSystemAlertsDialog(context);
      return;
    }
    final nav = Navigator.of(context);
    nav.pop();
    if (link.href == widget.activeHref) return; // already there
    openNavLink(nav, link, widget.session, widget.company);
  }

  /// Leaves every pushed page, back to the shell the app started in.
  void _toRoot() => Navigator.of(context).popUntil((r) => r.isFirst);

  void _dashboard() => _toRoot();

  void _businessOffice() {
    _toRoot();
    widget.session.clearActive();
  }

  Future<void> _logout() async {
    _toRoot();
    await widget.session.signOut();
    widget.onSignedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * .85;
    final system = _groups.where((g) => g.title == 'System');
    final menus = _groups.where((g) => g.title != 'System' && !sheetOnlyGroups.contains(g.title));

    return Material(
      color: _slate900,
      elevation: 16,
      child: SizedBox(
        width: width > 320 ? 320 : width,
        height: double.infinity,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  children: [
                    _Row(
                      icon: Icons.work_outline,
                      label: 'Business Office',
                      onTap: _businessOffice,
                    ),
                    const SizedBox(height: 16),
                    _Row(
                      icon: switch (widget.company.type) {
                        CompanyType.water => Icons.water_drop_outlined,
                        CompanyType.restaurant => Icons.restaurant,
                        _ => Icons.home_outlined,
                      },
                      label: 'Dashboard',
                      active: widget.activeHref == null,
                      onTap: _dashboard,
                    ),
                    const SizedBox(height: 16),
                    const _Divider(),
                    const SizedBox(height: 16),
                    if (_flat)
                      ..._flatGroups()
                    else ...[
                      for (final g in menus) ...[
                        _menu(g),
                        const SizedBox(height: 4),
                      ],
                      const SizedBox(height: 12),
                      const _Divider(),
                      const SizedBox(height: 16),
                      for (final g in system) _menu(g),
                    ],
                  ],
                ),
              ),
              _logoutBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// h-16 logo strip with the close button, border-b slate-800.
  Widget _header() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _slate800)),
      ),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.visibility, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'VisibilityCore',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close sidebar',
            icon: const Icon(Icons.close, size: 20, color: _slate300),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// One top-nav menu as an in-place collapsible section.
  Widget _menu(NavGroup g) {
    final open = _openMenus.contains(g.title);
    final subs = g.subGroups.where((s) => s.links.isNotEmpty).toList();
    final quick = g.title == 'Quick Links' && _customisable;
    if (subs.isEmpty && !quick) return const SizedBox.shrink();
    final holdsActive = g.title != 'Quick Links' &&
        subs.any((s) => s.links.any((l) => l.href == widget.activeHref));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() {
            if (!_openMenus.remove(g.title)) _openMenus.add(g.title);
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              children: [
                Icon(_menuIcons[g.title] ?? Icons.folder_outlined,
                    size: 20, color: holdsActive ? _orange400 : _slate400),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    g.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: holdsActive ? Colors.white : _slate200,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0 : -.25,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.expand_more, size: 18, color: _slate500),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.only(left: 16, top: 4),
            padding: const EdgeInsets.only(left: 4),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: _slate800)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subs.length == 1)
                  for (final l in subs.first.links) _link(l)
                else
                  for (final s in subs) _subGroup(g.title, s),
                if (quick) _customiseRow(),
              ],
            ),
          ),
      ],
    );
  }

  /// Water and Restaurant render the web's flat layout; Poultry its menus.
  bool get _flat => widget.company.type != CompanyType.poultry;

  /// Water's and Restaurant's layout on the web (sidebar.tsx, the isWater
  /// and isRestaurant branches): not menus but a flat run of titled groups,
  /// each open and collapsible, with a divider where the top nav has a
  /// separate menu. Water's Setup columns are titled "Setup · Company" and
  /// so on, because Delivery and Production also exist under Operations.
  List<Widget> _flatGroups() {
    // Water's Trackers and Reports sit together with no divider between.
    final noDividerBefore =
        widget.company.type == CompanyType.water ? const {'Reports'} : const <String>{};
    final out = <Widget>[];
    for (final g in _groups) {
      if (sheetOnlyGroups.contains(g.title)) continue;
      final subs = g.subGroups.where((s) => s.links.isNotEmpty).toList();
      final quick = g.title == 'Quick Links' && _customisable;
      if (subs.isEmpty && !quick) continue;
      if (out.isNotEmpty && !noDividerBefore.contains(g.title)) {
        out.addAll(const [SizedBox(height: 8), _Divider(), SizedBox(height: 12)]);
      }
      for (final s in subs.isEmpty ? [const NavSubGroup('', [])] : subs) {
        final heading = switch (g.title) {
          'Setup' => 'Setup · ${s.title}',
          'System' => 'System',
          _ => s.title.isEmpty ? g.title : s.title,
        };
        out.add(_subGroup(g.title, s, heading: heading));
      }
      if (quick) out.add(_customiseRow());
    }
    return out;
  }

  /// A column heading inside an open menu: xs, uppercase, slate-500, and
  /// collapsible on its own.
  Widget _subGroup(String menu, NavSubGroup s, {String? heading}) {
    final key = '$menu/${s.title}';
    final open = !_closedSubs.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!_closedSubs.remove(key)) _closedSubs.add(key);
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (heading ?? s.title).toUpperCase(),
                      style: const TextStyle(
                        color: _slate500,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0 : -.25,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 15, color: _slate500),
                  ),
                ],
              ),
            ),
          ),
          if (open) for (final l in s.links) _link(l),
        ],
      ),
    );
  }

  Widget _link(NavLink l) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _Row(
          icon: _iconByHref[l.href] ?? Icons.insert_chart_outlined,
          label: l.label,
          active: l.href == widget.activeHref,
          onTap: () => _go(l),
        ),
      );

  Widget _logoutBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _slate800)),
      ),
      child: _Row(
        icon: Icons.logout,
        label: 'Logout',
        hoverColor: const Color(0x4D7F1D1D), // red-900/30
        onTap: _logout,
      ),
    );
  }
}

/// A sidebar row: `px-4 py-2.5 text-sm font-medium rounded-md`, slate-300
/// text, and when active `bg-slate-700` with a 3px blue-400 left border.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.hoverColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _slate700 : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: hoverColor,
        highlightColor: hoverColor ?? _slate800,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 13, right: 16),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: active ? _blue400 : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: active ? _blue400 : _slate400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : _slate300,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _slate800,
      );
}

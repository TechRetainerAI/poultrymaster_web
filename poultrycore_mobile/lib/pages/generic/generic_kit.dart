// Shared bits for the Generic pages: what a Generic company calls things
// (lib/generic/template-labels.ts), which modules it has
// (hooks/use-generic-modules.ts, with the same per-company cache), and the
// business types it can be set up as (lib/companies/business-types.ts).

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr;
import '../poultry/trackers/tracker_widgets.dart';
import '../shared/companies_screen.dart' show BusinessType, businessTypes;
import '../web_nav.dart';

import 'package:poultrycore_mobile/design/tone.dart';
/// `/api/generic-company/{farmId}`: the base of every Generic company call.
String genericBase(Company c) => '/api/generic-company/${Uri.encodeComponent(c.farmId)}';

// ---------------------------------------------------------------- labels

/// TemplateLabels: what a customer, a plan, a bill are called.
class GenericLabels {
  const GenericLabels({
    required this.customer,
    required this.customerPlural,
    required this.plan,
    required this.planPlural,
    required this.subscription,
    required this.subscriptionPlural,
    required this.invoice,
    required this.invoicePlural,
    required this.payment,
    required this.paymentPlural,
    required this.customerBalance,
    required this.overdueCustomer,
  });
  final String customer, customerPlural, plan, planPlural, subscription, subscriptionPlural;
  final String invoice, invoicePlural, payment, paymentPlural, customerBalance, overdueCustomer;
}

/// labels(): plural by adding "s" unless a label spells its own.
GenericLabels _labels(
  String customer,
  String plan,
  String subscription, {
  String? subscriptionPlural,
  String invoice = 'Invoice',
  String invoicePlural = 'Invoices',
  String payment = 'Payment',
  String paymentPlural = 'Payments',
  String? customerBalance,
  String? overdueCustomer,
}) =>
    GenericLabels(
      customer: customer,
      customerPlural: '${customer}s',
      plan: plan,
      planPlural: '${plan}s',
      subscription: subscription,
      subscriptionPlural: subscriptionPlural ?? '${subscription}s',
      invoice: invoice,
      invoicePlural: invoicePlural,
      payment: payment,
      paymentPlural: paymentPlural,
      customerBalance: customerBalance ?? '$customer Balances',
      overdueCustomer: overdueCustomer ?? 'Overdue $customer',
    );

final Map<String, GenericLabels> _labelTable = {
  'SaaS': _labels('Customer', 'Subscription Plan', 'Subscription',
      payment: 'Subscription Payment', paymentPlural: 'Subscription Payments'),
  'Gym': _labels('Member', 'Membership Plan', 'Membership',
      invoice: 'Membership Bill', invoicePlural: 'Membership Bills',
      payment: 'Membership Payment', paymentPlural: 'Membership Payments', customerBalance: 'Member Balances'),
  'School': _labels('Student', 'Fee Plan', 'Enrollment',
      invoice: 'Fee Bill', invoicePlural: 'Fee Bills', payment: 'Fee Payment', paymentPlural: 'Fee Payments',
      customerBalance: 'Outstanding Fees', overdueCustomer: 'Overdue Student / Parent'),
  'CleaningService': _labels('Client', 'Service Package', 'Service Contract',
      subscriptionPlural: 'Service Contracts', invoice: 'Service Bill', invoicePlural: 'Service Bills',
      payment: 'Client Payment', paymentPlural: 'Client Payments'),
  'SecurityService': _labels('Client', 'Security Service Package', 'Security Contract',
      subscriptionPlural: 'Security Contracts', invoice: 'Service Bill', invoicePlural: 'Service Bills',
      payment: 'Client Payment', paymentPlural: 'Client Payments'),
  'Agency': _labels('Client', 'Retainer Package', 'Support Retainer',
      payment: 'Client Payment', paymentPlural: 'Client Payments'),
  'RetainerBusiness': _labels('Client', 'Retainer Package', 'Retainer',
      payment: 'Client Payment', paymentPlural: 'Client Payments'),
  'MembershipBusiness': _labels('Member', 'Membership Plan', 'Membership',
      invoice: 'Bill', invoicePlural: 'Bills', payment: 'Member Payment', paymentPlural: 'Member Payments',
      customerBalance: 'Member Balances'),
  'Retail': _labels('Customer', 'Service / Plan', 'Subscription'),
  // Phase B: expanded business types (migration 362), template-labels.ts.
  'ProduceSeller': _labels('Customer', 'Service / Plan', 'Subscription'),
  'Grocery': _labels('Customer', 'Service / Plan', 'Subscription'),
  'HardwareShop': _labels('Customer', 'Service / Plan', 'Subscription'),
  'ElectronicsShop': _labels('Customer', 'Service / Plan', 'Subscription'),
  'Wholesaler': _labels('Customer', 'Service / Plan', 'Subscription', customerBalance: 'Customer Balances', overdueCustomer: 'Overdue Customer'),
  'Bakery': _labels('Customer', 'Service / Plan', 'Subscription'),
  'CarDealership': _labels('Customer', 'Service / Plan', 'Subscription',
      invoice: 'Vehicle Invoice', invoicePlural: 'Vehicle Invoices', payment: 'Vehicle Payment', paymentPlural: 'Vehicle Payments'),
  'Pharmacy': _labels('Customer', 'Service / Plan', 'Subscription'),
  'Barbershop': _labels('Customer', 'Service / Plan', 'Subscription / Contract'),
  'Salon': _labels('Customer', 'Service / Plan', 'Subscription / Contract'),
  'AutoRepair': _labels('Customer', 'Service / Plan', 'Subscription / Contract', invoice: 'Job Invoice', invoicePlural: 'Job Invoices'),
  'Tailor': _labels('Customer', 'Service / Plan', 'Subscription / Contract',
      invoice: 'Job Invoice', invoicePlural: 'Job Invoices', payment: 'Job Payment', paymentPlural: 'Job Payments'),
  'Laundry': _labels('Customer', 'Service / Plan', 'Subscription / Contract', invoice: 'Service Invoice', invoicePlural: 'Service Invoices'),
  'Freelancer': _labels('Client', 'Retainer Package', 'Retainer', payment: 'Client Payment', paymentPlural: 'Client Payments'),
  'Other': _labels('Customer', 'Service / Plan', 'Subscription / Contract'),
};

/// templateLabels: an unknown or missing template keeps the neutral words.
GenericLabels genericLabels(String? industry) => _labelTable[industry] ?? _labelTable['Other']!;

// --------------------------------------------------------- business types

/// The module bundle each Generic business type runs (business-types.ts).
String? businessTemplateFor(String? industry) =>
    industry == null ? null : businessTypeForIndustry(industry)?.businessTemplate ?? 'SubscriptionServiceBusiness';

/// GENERIC_BUSINESS_TYPES.
final List<BusinessType> genericBusinessTypes = [
  for (final t in businessTypes)
    if (t.companyType == 'Generic') t,
];

/// businessTypeForIndustry.
BusinessType? businessTypeForIndustry(String? industry) {
  if (industry == null || industry.isEmpty) return null;
  for (final t in genericBusinessTypes) {
    if (t.industryTemplate == industry) return t;
  }
  return null;
}

const _legacyCategory = {
  'SaaS': 'Services Business', 'Agency': 'Services Business', 'RetainerBusiness': 'Services Business',
  'CleaningService': 'Services Business', 'SecurityService': 'Services Business', 'Gym': 'Services Business',
  'MembershipBusiness': 'Services Business', 'School': 'School', 'Retail': 'Retail Shop', 'Other': 'Other',
  // Phase B (business-types.ts LEGACY_CATEGORY_BY_INDUSTRY).
  'ProduceSeller': 'Retail Shop', 'Grocery': 'Retail Shop', 'HardwareShop': 'Retail Shop', 'ElectronicsShop': 'Retail Shop',
  'Wholesaler': 'Retail Shop', 'Bakery': 'Retail Shop', 'CarDealership': 'Retail Shop', 'Pharmacy': 'Retail Shop',
  'Barbershop': 'Other', 'Salon': 'Other', 'AutoRepair': 'Other', 'Tailor': 'Other', 'Laundry': 'Other',
  'Freelancer': 'Services Business',
};

/// legacyCategoryIdFor: the old business-category id for a template, by name,
/// falling back to "Other"; null when neither is in the list.
int? legacyCategoryIdFor(String? industry, List<Map<String, dynamic>> categories) {
  if (industry == null) return null;
  int? byName(String n) {
    for (final c in categories) {
      if (tStr(c['name']).trim().toLowerCase() == n.toLowerCase()) return int.tryParse('${c['businessCategoryId']}');
    }
    return null;
  }

  return byName(_legacyCategory[industry] ?? 'Other') ?? byName('Other');
}

// ------------------------------------------------------- module settings

/// The module switches, in GenericModuleSettings order.
const genericModuleKeys = [
  'enableProducts', 'enableInventory', 'enableStockAdjustments', 'enableInternalUse', 'enablePurchases',
  'enableSubscriptions', 'enableInvoices', 'enableCustomerBalances', 'enableStaffPayments', 'enableCashAccounts',
  'enableRecurringExpenses', 'enableSupplierBalances',
];

/// What useGenericModules returns. `settings` and `businessSettings` are null
/// while loading and when the request failed.
class GenericModules {
  const GenericModules({this.settings, this.industry, this.business, this.businessSettings});
  final Map<String, dynamic>? settings;
  final String? industry;
  final String? business;
  final Map<String, dynamic>? businessSettings;

  GenericLabels get labels => genericLabels(industry);

  /// Bills on a schedule: the subscription bundle, or subscriptions switched on.
  bool get isSubscriptionBusiness => business == 'SubscriptionServiceBusiness' || settings?['enableSubscriptions'] == true;

  /// A NEW menu item: hidden while loading and on failure.
  bool showNew(String key) => settings?[key] == true;

  /// An item everyone already had: shown while loading and on failure.
  bool showExisting(String key) => settings?[key] == null ? true : settings![key] == true;
}

final _cache = <String, GenericModules>{};
final _inflight = <String, Future<GenericModules>>{};

Map<String, dynamic>? _mapOrNull(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// The three settings requests, once per company, shared by every page.
Future<GenericModules> loadGenericModules(Session s, Company c) {
  final hit = _cache[c.farmId];
  if (hit != null) return Future.value(hit);
  return _inflight[c.farmId] ??= () async {
    final base = genericBase(c);
    Future<Object?> quiet(String path) => s.farmClient.get(path).then<Object?>((v) => v, onError: (_) => null);
    final r = await Future.wait([quiet('$base/module-settings'), quiet('$base/business-template'), quiet('$base/business-settings')]);
    final template = _mapOrNull(r[1]);
    final value = GenericModules(
      settings: _mapOrNull(r[0]),
      industry: template == null ? null : (tStr(template['genericIndustryTemplate']).isEmpty ? null : tStr(template['genericIndustryTemplate'])),
      business: template == null ? null : (tStr(template['genericBusinessTemplate']).isEmpty ? null : tStr(template['genericBusinessTemplate'])),
      businessSettings: _mapOrNull(r[2]),
    );
    _cache[c.farmId] = value;
    _inflight.remove(c.farmId);
    return value;
  }();
}

/// What loadGenericModules last returned for this company, or null before it
/// has answered.
GenericModules? cachedGenericModules(String farmId) => _cache[farmId];

/// generic-nav-config.ts: each Catalog row shows unless its module is
/// explicitly switched off (showExisting), so the menu is full while the
/// settings load. Other companies' menus are untouched.
const genericCatalogModules = {
  '/generic-products': 'enableProducts',
  '/generic-inventory': 'enableInventory',
  '/generic-stock-adjustments': 'enableStockAdjustments',
  '/generic-internal-use': 'enableInternalUse',
  // Purchasing (showExisting too).
  '/generic-purchases': 'enablePurchases',
  '/generic-supplier-balances': 'enableSupplierBalances',
  '/recurring-expenses': 'enableRecurringExpenses',
  // Money (showExisting too).
  '/generic-cash': 'enableCashAccounts',
  '/generic-cash-transfers': 'enableCashAccounts',
};

///
/// The Sales rows for customers and payments carry the template's words
/// (labels.customerPlural / paymentPlural), once the settings are known.
List<NavGroup> gateGenericCatalog(List<NavGroup> groups, Company company) {
  final m = cachedGenericModules(company.farmId);
  // The School group is for School businesses only; until the settings are
  // known it stays hidden, as the web's isSchool is false while loading.
  if (m == null) return [for (final g in groups) if (g.title != 'School') g];
  bool keep(NavLink l) => genericCatalogModules[l.href] == null || m.showExisting(genericCatalogModules[l.href]!);
  NavLink word(NavLink l) => switch (l.href) {
        '/generic-customers' => NavLink(m.labels.customerPlural, l.href, l.specKey),
        '/generic-customer-payments' => NavLink(m.labels.paymentPlural, l.href, l.specKey),
        // Subscription businesses call suppliers vendors (generic-nav-config.ts).
        '/generic-suppliers' when m.isSubscriptionBusiness => NavLink('Vendors', l.href, l.specKey),
        '/generic-supplier-payments' when m.isSubscriptionBusiness => NavLink('Vendor payments', l.href, l.specKey),
        '/generic-supplier-balances' when m.isSubscriptionBusiness => NavLink('Vendor balances', l.href, l.specKey),
        '/generic-supplier-credits' when m.isSubscriptionBusiness => NavLink('Vendor credits', l.href, l.specKey),
        _ => l,
      };
  return [
    for (final g in groups)
      if (g.title == 'School' && m.industry != 'School')
        ...const <NavGroup>[]
      else if (NavGroup(g.title, [
        for (final s in g.subGroups)
          if (s.links.where(keep).map(word).toList() case final links when links.isNotEmpty) NavSubGroup(s.title, links),
      ]) case final kept when kept.subGroups.isNotEmpty)
        kept,
  ];
}

/// invalidateGenericModules: after Setup, the wizard or Settings change them.
void invalidateGenericModules([String? farmId]) {
  if (farmId == null) {
    _cache.clear();
    _inflight.clear();
  } else {
    _cache.remove(farmId);
    _inflight.remove(farmId);
  }
}

// ------------------------------------------------------------- widgets

const genericEmerald = Tone(0xFF059669); // emerald-600
const genericIndigo = Tone(0xFF4F46E5); // indigo-600

/// The page title row the Generic pages share: an icon, the title, a line.
class GenericTitle extends StatelessWidget {
  const GenericTitle({super.key, required this.icon, required this.title, this.subtitle, this.iconColor = const Tone.fg(0xFF334155)});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A)))),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ],
        ],
      );
}

/// A white card with a title and a description, as the web's Card + CardHeader.
class GenericCard extends StatelessWidget {
  const GenericCard({super.key, this.title, this.titleWidget, this.description, this.descriptionWidget, required this.children});
  final String? title;
  final Widget? titleWidget;
  final String? description;
  final Widget? descriptionWidget;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tone.bg(0xFFFFFFFF),
          border: Border.all(color: Tone.line(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?titleWidget,
            if (title != null) Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tone.fg(0xFF0F172A))),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description!, style: const TextStyle(fontSize: 13, color: TColors.slate500)),
            ],
            if (descriptionWidget != null) ...[const SizedBox(height: 4), descriptionWidget!],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

/// The settings pages' switch row: a label, an optional hint, the switch.
class GenericToggle extends StatelessWidget {
  const GenericToggle({super.key, required this.label, this.hint, required this.value, required this.onChanged});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, color: Tone.fg(0xFF0F172A))),
                  if (hint != null) Text(hint!, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

/// The uppercase group heading above a set of switches or cards.
Widget genericEyebrow(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(text.toUpperCase(),
          style: const TextStyle(fontSize: 12, letterSpacing: 0.6, color: TColors.slate500)),
    );

/// A spinner on a busy button, or nothing.
Widget busyIcon(bool busy, IconData icon, {Color color = Colors.white}) => busy
    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
    : Icon(icon, size: 18);

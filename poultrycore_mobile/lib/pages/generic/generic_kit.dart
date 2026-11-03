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
  'Other': _labels('Customer', 'Service / Plan', 'Subscription / Contract'),
};

/// templateLabels: an unknown or missing template keeps the neutral words.
GenericLabels genericLabels(String? industry) => _labelTable[industry] ?? _labelTable['Other']!;

// --------------------------------------------------------- business types

/// The module bundle each Generic business type runs (business-types.ts).
String? businessTemplateFor(String? industry) => switch (industry) {
      null => null,
      'Retail' => 'RetailBusiness',
      'Other' => 'GeneralBusiness',
      _ => 'SubscriptionServiceBusiness',
    };

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

const genericEmerald = Color(0xFF059669); // emerald-600
const genericIndigo = Color(0xFF4F46E5); // indigo-600

/// The page title row the Generic pages share: an icon, the title, a line.
class GenericTitle extends StatelessWidget {
  const GenericTitle({super.key, required this.icon, required this.title, this.subtitle, this.iconColor = TColors.slate700});
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
            Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColors.slate900))),
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
          color: Colors.white,
          border: Border.all(color: TColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?titleWidget,
            if (title != null) Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
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
                  Text(label, style: const TextStyle(fontSize: 14, color: TColors.slate900)),
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

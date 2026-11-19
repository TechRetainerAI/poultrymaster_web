// Farm Setup (/poultry-setup) navigation model: its two sections, their tabs,
// and how a link resolves to one of them, as the web's
// lib/nav/poultry-setup-tabs.ts. Free of widgets so the rules can be tested.
//
// Link shape: /poultry-setup?section=production|business&tab=<tab key>

enum SetupSection { production, business }

class SetupTab {
  const SetupTab(this.key, this.label, this.description);
  final String key;
  final String label;

  /// The one line shown under the tab row.
  final String description;
}

class SetupSectionDef {
  const SetupSectionDef(this.label, this.tabs);
  final String label;
  final List<SetupTab> tabs;
}

const setupSections = {
  SetupSection.production: SetupSectionDef('Production Setup', [
    SetupTab('company-settings', 'Company settings',
        'Your business name and contacts, farm type and capacity, currency and business time zone.'),
    SetupTab('houses', 'Houses & pens', 'Manage the houses and pens where your birds are kept.'),
    SetupTab('flock-purchases', 'Flock purchases', 'Record the birds you bought; each batch is later divided into flock groups.'),
    SetupTab('flock-groups', 'Flock groups', 'Manage the groups of birds.'),
    SetupTab('products', 'Products', 'Manage products used in production, purchasing and sales.'),
    SetupTab('feed-formulas', 'Feed formulas', 'Configure ingredient formulas used to produce feed.'),
    SetupTab('egg-settings', 'Egg settings', 'Configure the egg settings used when recording production.'),
    SetupTab('inventory', 'Supply items', 'Set up your supply items.'),
  ]),
  SetupSection.business: SetupSectionDef('Business Setup', [
    SetupTab('customers', 'Customers', 'Manage customer details used in sales and payments.'),
    SetupTab('suppliers', 'Suppliers', 'Manage supplier details used in purchases and payments.'),
    SetupTab('financial-settings', 'Financial settings', 'Choose when inventory costs count towards profit and loss.'),
    SetupTab('cash-accounts', 'Cash accounts', 'Manage the cash and bank accounts money is paid into and out of.'),
    SetupTab('drivers', 'Delivery Drivers', 'Manage the drivers who deliver your eggs, linked to your employees.'),
    SetupTab('vehicles', 'Delivery Vehicles', "Manage the vehicles your eggs are loaded onto for delivery."),
    SetupTab('routes', 'Delivery Routes', 'Manage the delivery routes and the areas each one covers.'),
    SetupTab('staff', 'Staff', "Manage the farm's staff records used for payroll and assignments."),
  ]),
};

const setupPath = '/poultry-setup';

String setupHref(SetupSection section, String tab) => '$setupPath?section=${section.name}&tab=$tab';

/// Which section owns a tab.
SetupSection? sectionOfTab(String tab) {
  for (final MapEntry(key: s, value: def) in setupSections.entries) {
    if (def.tabs.any((t) => t.key == tab)) return s;
  }
  return null;
}

SetupTab? setupTabOf(String tab) {
  for (final def in setupSections.values) {
    for (final t in def.tabs) {
      if (t.key == tab) return t;
    }
  }
  return null;
}

/// Tab aliases: the old wizard's ?step= values, plus a few natural spellings.
/// A value starting with "/" is a page outside Farm Setup.
const _aliases = {
  // old /poultry-setup?step= keys
  'company': 'company-settings',
  // the two profile tabs merged into Company settings (2026-11-07)
  'farm-profile': 'company-settings',
  'company-profile': 'company-settings',
  'flocks': 'flock-groups',
  'raw-materials': 'inventory',
  'employees': '/employees', // Users & Permissions stays in Administration
  // friendly spellings
  'delivery': 'drivers',
  'houses-pens': 'houses',
  'flock-batches': 'flock-purchases',
  'egg-picks': 'egg-settings',
  'finance': 'financial-settings',
};

sealed class SetupLocation {
  const SetupLocation();
}

class SetupAt extends SetupLocation {
  const SetupAt(this.section, this.tab);
  final SetupSection section;
  final String tab;

  @override
  bool operator ==(Object other) => other is SetupAt && other.section == section && other.tab == tab;

  @override
  int get hashCode => Object.hash(section, tab);

  @override
  String toString() => 'SetupAt(${section.name}, $tab)';
}

class SetupRedirect extends SetupLocation {
  const SetupRedirect(this.href);
  final String href;

  @override
  bool operator ==(Object other) => other is SetupRedirect && other.href == href;

  @override
  int get hashCode => href.hashCode;
}

class SetupNone extends SetupLocation {
  const SetupNone();
}

/// Resolve link params to what Farm Setup shows. Order of precedence:
///   1. an explicit, allowed tab (its own section wins over a mismatched section)
///   2. a legacy step
///   3. section alone -> that section's first allowed tab
///   4. nothing usable -> Production, else Business, first allowed tab
/// An unknown or forbidden tab falls through to the next rule, never to an error.
SetupLocation resolveSetupLocation({String? section, String? tab, String? step, required bool Function(String tab) allowed}) {
  String? firstAllowed(SetupSection s) => setupSections[s]!.tabs.where((t) => allowed(t.key)).firstOrNull?.key;

  SetupLocation? tryTab(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final alias = _aliases[raw];
    if (alias != null && alias.startsWith('/')) return SetupRedirect(alias);
    final key = alias ?? raw;
    final s = sectionOfTab(key);
    if (s == null || !allowed(key)) return null;
    return SetupAt(s, key);
  }

  final fromTab = tryTab(tab) ?? tryTab(step);
  if (fromTab != null) return fromTab;

  final order = section == 'business'
      ? [SetupSection.business, SetupSection.production]
      : [SetupSection.production, SetupSection.business];
  for (final s in order) {
    final t = firstAllowed(s);
    if (t != null) return SetupAt(s, t);
  }
  return const SetupNone();
}

/// Resolves a whole link ("/poultry-setup?section=business&tab=staff").
SetupLocation resolveSetupHref(String href, {required bool Function(String tab) allowed}) {
  final q = Uri.tryParse(href)?.queryParameters ?? const {};
  return resolveSetupLocation(section: q['section'], tab: q['tab'], step: q['step'], allowed: allowed);
}

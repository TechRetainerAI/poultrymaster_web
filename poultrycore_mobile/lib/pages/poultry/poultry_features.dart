// Does the active poultry company need its egg screens? Its broiler ones?
// (migrations 399 / 402), as the web's hooks/use-poultry-egg-features.ts.
//
// The answer comes from its flocks: eggs while any open flock is a Layer
// flock, none once only broilers are running; Broiler performance once the
// company has ever had a broiler flock. The company's business type settles
// an empty farm, but that endpoint is admin-only, so for staff an error just
// means "not known", never "hide".
//
// Fails OPEN: while loading, on any error, and on non-poultry companies both
// answers are true. Hiding a screen a layer farm needs is the worse mistake.

import 'package:flutter/foundation.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../lookup_loader.dart';
import '../web_nav.dart';
import 'flock_type.dart';

@immutable
class PoultryFeatures {
  const PoultryFeatures({required this.farmId, this.eggs = true, this.broilers = true});
  final String farmId;
  final bool eggs;
  final bool broilers;
}

/// What the last load found, for the company it was loaded for. Null until
/// one has been loaded: everything shows.
final poultryFeatures = ValueNotifier<PoultryFeatures?>(null);

DateTime? _loadedAt;

/// Pages that only mean anything on a farm whose birds lay
/// (POULTRY_EGG_ONLY_HREFS). Hidden, not removed: the routes still open.
const poultryEggOnlyHrefs = {
  '/poultry-egg-sorting',
  '/egg-production',
  '/egg-tracker',
  '/broken-eggs-tracker',
  '/business-office/egg-pick-settings',
};

const broilerPerformanceHref = '/poultry-broiler-performance';

/// The Home tab's egg cards. The web hides TOTAL EGGS and PRODUCTION
/// EFFICIENCY (metrics-cards.tsx); the phone's Home reads the farm summary,
/// whose egg figures are these.
const poultryEggMetricKeys = {
  'totalEggsProduced',
  'saleableEggs',
  'brokenRejectedEggs',
  'totalEggs',
  'productionEfficiency',
};

/// Whether the Home tab shows the card for summary field [key]: on a
/// broiler-only farm the egg cards go.
bool showsHomeMetric(Company company, String? key) => featuresFor(company).eggs || !poultryEggMetricKeys.contains(key);

/// Loads the answers for [company]. Kept five minutes (the web's staleTime)
/// unless [force], which is what saving, dividing or deleting a flock passes
/// so the menus follow at once (useRefreshPoultryEggFeatures).
Future<void> loadPoultryFeatures(Session session, Company company, {bool force = false}) async {
  if (company.type != CompanyType.poultry) return;
  final have = poultryFeatures.value;
  if (!force &&
      have?.farmId == company.farmId &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
    return;
  }
  List<Map>? flocks;
  try {
    final res = await session.farmClient.get('/api/Flock', query: {
      'farmId': company.farmId,
      'userId': session.tokens.userId ?? '',
    });
    flocks = [for (final f in LookupLoader.rowsIn(res)) if (f is Map) f];
  } catch (_) {
    flocks = null;
  }
  if (flocks == null) {
    poultryFeatures.value = PoultryFeatures(farmId: company.farmId);
    _loadedAt = DateTime.now();
    return;
  }
  final type = await loadPoultryBusinessType(session, company);
  poultryFeatures.value = PoultryFeatures(
    farmId: company.farmId,
    eggs: showEggFeatures(flocks, type),
    broilers: showBroilerFeatures(flocks, type),
  );
  _loadedAt = DateTime.now();
}

/// For tests.
void resetPoultryFeatures() {
  poultryFeatures.value = null;
  _loadedAt = null;
}

/// The answers for [company]: fail-open (both true) until they are known.
PoultryFeatures featuresFor(Company company) {
  final f = poultryFeatures.value;
  if (company.type != CompanyType.poultry || f == null || f.farmId != company.farmId) {
    return PoultryFeatures(farmId: company.farmId);
  }
  return f;
}

/// buildPoultryNavConfig's two rules over the phone's menus: a broiler-only
/// company loses the egg rows, and Broiler performance shows only once the
/// company has had a broiler flock. Applied before the Quick Links resolve,
/// so a pinned egg page goes with them. A section left empty goes too.
List<NavGroup> gatePoultryFeatureLinks(List<NavGroup> groups, Company company) {
  final f = featuresFor(company);
  if (f.eggs && f.broilers) return groups;
  bool keep(NavLink l) =>
      (f.eggs || !poultryEggOnlyHrefs.contains(l.href)) && (f.broilers || l.href != broilerPerformanceHref);
  return [
    for (final g in groups)
      if (NavGroup(g.title, [
        for (final s in g.subGroups)
          if (s.links.where(keep).toList() case final links when links.isNotEmpty) NavSubGroup(s.title, links),
      ]) case final kept when kept.subGroups.isNotEmpty)
        kept,
  ];
}

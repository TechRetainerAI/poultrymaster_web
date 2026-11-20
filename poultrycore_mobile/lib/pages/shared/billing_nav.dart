// Whether the Billing button shows (hooks/use-billing-nav.ts, 1 Nov pull).
//
// Controlled from the admin portal (Operations → Feature Flags) by the
// "billing_nav" flag: a global master toggle plus optional per-company rules.
// On = Billing visible; Off = hidden, resolved for the current company.
//
// Fail-open: if the flag can't be read, errors, or does not exist
// (FlagNotFound), Billing stays visible -- so a flag or API hiccup never hides
// a button that should be there.

import 'package:flutter/foundation.dart';

import '../../state/session.dart';
import '../web_nav.dart';

/// Visible until the flag says otherwise.
final billingNavVisible = ValueNotifier<bool>(true);

/// The Billing pages a menu row may point at.
bool isBillingHref(String href) => href == '/business-office/billing' || href == '/billing';

/// GET /api/PlatformOps/flags/billing_nav/evaluate?companyId=… -- hidden only
/// on an explicit `enabled: false` that is not FlagNotFound.
Future<void> loadBillingNavFlag(Session session, {String? companyId}) async {
  try {
    final d = await session.farmClient.get('/api/PlatformOps/flags/billing_nav/evaluate',
        query: {if (companyId != null && companyId.isNotEmpty) 'companyId': companyId});
    if (d is Map && d['enabled'] == false && d['matchedScope'] != 'FlagNotFound') {
      billingNavVisible.value = false;
    } else if (d is Map) {
      billingNavVisible.value = true;
    }
  } catch (_) {
    // Fail-open: keep Billing visible.
  }
}

/// The phone menus without the Billing rows while the flag hides them
/// (mobile-bottom-nav.tsx); a section left empty goes with them.
List<NavGroup> gateBillingLinks(List<NavGroup> groups) {
  if (billingNavVisible.value) return groups;
  return [
    for (final g in groups)
      if (NavGroup(g.title, [
        for (final s in g.subGroups)
          if (s.links.where((l) => !isBillingHref(l.href)).toList() case final links when links.isNotEmpty) NavSubGroup(s.title, links),
      ]) case final kept when kept.subGroups.isNotEmpty)
        kept,
  ];
}

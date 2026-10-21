// /restaurant-reports (the catalog) and /restaurant-reports/<slug> (one report),
// with the old catalog's slugs sent on to the report that replaced them.

import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../custom_form.dart' show PageScreenBuilder;
import 'restaurant_money_report_defs.dart';
import 'restaurant_report_defs.dart';
import 'restaurant_report_kit.dart';
import 'restaurant_reports_catalog.dart';

/// REPORT_REGISTRY: every slug's definition.
final restaurantReportRegistry = <String, RDef>{...restaurantReportDefs, ...restaurantMoneyReportDefs};

/// The screen for a slug (a legacy slug lands on its replacement); null when unknown.
Widget? restaurantReportScreen(Session s, Company c, String slug) {
  final real = findRestaurantReport(slug) != null ? slug : restaurantLegacySlugs[slug];
  final def = real == null ? null : restaurantReportRegistry[real];
  if (real == null || def == null) return null;
  return RestaurantReportScreen(session: s, company: c, slug: real, def: def);
}

void openRestaurantReport(BuildContext context, Session s, Company c, String slug) {
  final screen = restaurantReportScreen(s, c, slug);
  if (screen != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

final Map<String, PageScreenBuilder> restaurantReportScreens = {
  '/restaurant-reports': (s, c) => RestaurantReportsCatalogScreen(session: s, company: c),
  for (final slug in [...restaurantReportRegistry.keys, ...restaurantLegacySlugs.keys])
    '/restaurant-reports/$slug': (s, c) => restaurantReportScreen(s, c, slug)!,
};

// /hotel-reports (the catalog) and /hotel-reports/<slug>. The reports in the
// web's HOTEL_REPORT_REGISTRY render through the shared report shell in
// Hotel's violet; the rest are mirrored page by page.

import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../custom_form.dart' show PageScreenBuilder;
import '../../poultry/trackers/tracker_widgets.dart' show TColors;
import '../../restaurant/reports/restaurant_report_kit.dart';
import 'hotel_page_report_defs.dart';
import 'hotel_report_defs.dart';
import 'hotel_reports_catalog.dart';

final hotelReportFlavor = ReportFlavor(
  accent: TColors.violet600,
  accentSoft: TColors.violet50,
  accentBorder: const Color(0xFFC4B5FD),
  accentText: TColors.violet700,
  href: '/hotel-reports',
  profilePath: '/api/Hotel/setup/profile',
  nameKey: 'hotelName',
  fallbackName: 'Hotel',
  find: findHotelReport,
  openCatalog: openHotelReportsCatalog,
  pdfViolet: true,
);

/// The screen for a slug; null when the app has none for it yet.
Widget? hotelReportScreen(Session s, Company c, String slug) {
  final def = hotelReportDefs[slug] ?? hotelPageReportDefs[slug];
  if (def == null || findHotelReport(slug) == null) return null;
  return RestaurantReportScreen(session: s, company: c, slug: slug, def: def, flavor: hotelReportFlavor);
}

final Map<String, PageScreenBuilder> hotelReportScreens = {
  '/hotel-reports': (s, c) => HotelReportsCatalogScreen(session: s, company: c),
  for (final slug in [...hotelReportDefs.keys, ...hotelPageReportDefs.keys]) '/hotel-reports/$slug': (s, c) => hotelReportScreen(s, c, slug)!,
};

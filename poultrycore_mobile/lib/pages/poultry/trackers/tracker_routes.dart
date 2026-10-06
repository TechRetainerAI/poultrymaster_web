import 'package:flutter/widgets.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../custom_form.dart';
import 'analytical_report_screen.dart';
import 'birds_tracker_screen.dart';
import 'egg_tracker_screen.dart';
import 'feed_inventory_tracker_screen.dart';
import 'feed_stock_tracker_screen.dart';
import 'medication_tracker_screen.dart';
import 'tracker_logic.dart';

/// Poultry → Trackers, every row of the web's Trackers menu
/// (lib/nav/poultry-nav-config.ts `analytics`) on its native screen. Before
/// these, the sidebar opened unrelated generic lists (Birds tracker showed
/// the Flocks list, Analytical Report the production records) or the web page.
final Map<String, PageScreenBuilder> poultryTrackerScreens = {
  '/egg-tracker': (s, c) => EggTrackerScreen(session: s, company: c),
  '/feed-tracker': (s, c) => FeedStockTrackerScreen(session: s, company: c, kind: FeedKind.finishedFeed),
  '/feed-inventory-tracker': (s, c) => FeedInventoryTrackerScreen(session: s, company: c),
  '/birds-left-tracker': (s, c) => BirdsTrackerScreen(session: s, company: c),
  '/medication-tracker': (s, c) => MedicationTrackerScreen(session: s, company: c),
  '/weekly-report': (s, c) => AnalyticalReportScreen(session: s, company: c),
  '/feed-ingredient-tracker': (s, c) => FeedStockTrackerScreen(session: s, company: c, kind: FeedKind.ingredient),
};

/// A tracker link that carries a query, as other pages build them:
/// Raw Materials / Inventory → `/feed-inventory-tracker?itemId=…`, Inventory →
/// `/medication-tracker?inventoryItemId=…`, `/egg-tracker?inventoryItemId=…`.
/// Only the Feed inventory tracker reads its query (?itemId=), as on the web;
/// the others ignore it there and simply open.
Widget? trackerScreenForHref(String href, Session s, Company c) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  int? id(String k) => int.tryParse(uri.queryParameters[k] ?? '');
  return switch (uri.path) {
    '/feed-inventory-tracker' => FeedInventoryTrackerScreen(session: s, company: c, initialItemId: id('itemId')),
    _ => poultryTrackerScreens[uri.path]?.call(s, c),
  };
}

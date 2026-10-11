import 'package:flutter/material.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../../custom_form.dart';
import '../../web_page_screen.dart';
import 'water_delivery_reports.dart';
import 'water_money_reports.dart';
import 'water_production_reports.dart';
import 'water_reports_catalog_screen.dart';
import 'water_sales_reports.dart';

/// Every Water report slug with its native screen, in the catalogue's order.
final Map<String, PageScreenBuilder> waterReportBySlug = {
  'closing-report': waterClosingReport,
  'profit-loss': (s, c) => WaterProfitLossScreen(session: s, company: c),
  'daily-summary': (s, c) => WaterDailySummaryScreen(session: s, company: c),
  'cash-movement': (s, c) => WaterCashMovementScreen(session: s, company: c),
  'cash-flow-detail': (s, c) => WaterCashMovementScreen(session: s, company: c, detail: true),
  'cash-accounts': waterCashAccountsReport,
  'money-movement': waterMoneyMovementReport,
  'expense-report': waterExpenseReport,
  'supplier-activity': waterSupplierActivityReport,
  'sales-report': waterSalesReport,
  'payments-received': waterPaymentsReceivedReport,
  'customer-balances': waterCustomerBalancesReport,
  'customer-history': waterCustomerHistoryReport,
  'top-customers': waterTopCustomersReport,
  'production-report': waterProductionReport,
  'raw-material-usage': waterRawMaterialUsageReport,
  'raw-material-purchase': waterRawMaterialPurchaseReport,
  'inventory-report': waterInventoryReport,
  'stock-movement': waterStockMovementReport,
  'product-performance': waterProductPerformanceReport,
  'delivery-run-report': waterDeliveryRunReport,
  'driver-accountability': waterDriverAccountabilityReport,
  'route-performance': waterRoutePerformanceReport,
  'driver-collection': waterDriverCollectionReport,
  'vehicle-usage': waterVehicleUsageReport,
  'loss-report': waterLossReport,
  'operational': (s, c) => WaterOperationalScreen(session: s, company: c),
};

/// The Water report routes, keyed by web href, for the sidebar, the All pages
/// sheet and in-page links.
final Map<String, PageScreenBuilder> waterReportScreens = {
  '/water-reports': (s, c) => WaterReportsCatalogScreen(session: s, company: c),
  for (final e in waterReportBySlug.entries) '/water-reports/${e.key}': e.value,
};

/// Opens a Water report: its native screen, or the web page in-app.
void openWaterReport(BuildContext context, Session session, Company company, String slug, {required String label}) {
  final screen = waterReportBySlug[slug];
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => screen != null
        ? screen(session, company)
        : WebPageScreen(label: label, href: '/water-reports/$slug', company: company, session: session),
  ));
}

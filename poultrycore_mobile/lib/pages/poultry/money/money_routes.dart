import 'package:flutter/widgets.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../delivery/deliveries_screen.dart';
import '../expenses/asset_detail_screen.dart';
import '../expenses/asset_logic.dart' show AssetRail;
import '../inventory/stock_movements_screen.dart';
import '../production/batch_production_records_screen.dart';
import '../egg_sorting/egg_sorting_screens.dart' show eggSortingWorkspaceForHref;
import '../production/egg_sorting_screen.dart';
import '../production/feed_production_screen.dart';
import '../production/production_records_screen.dart';
import '../purchase/flock_batches_screen.dart';
import '../purchase_receipts_screen.dart';
import '../purchase/raw_materials_screen.dart';
import '../expenses/deferred_costs_screen.dart';
import '../expenses/expenses_screen.dart';
import '../expenses/payroll_screen.dart';
import 'cash_accounts_screen.dart';
import 'reconciliation_screen.dart';
import '../../water/reports/water_money_reports.dart' show waterMoneyRail;
import '../../water/water_payroll_screen.dart' show WaterPayrollDetailScreen;
import '../../water/water_deferred_costs_screen.dart' show WaterDeferredCostsScreen;
import '../../water/water_production_screen.dart' show WaterProductionDetailScreen;
import '../../water/water_deliveries_screen.dart' show WaterDeliveryRunScreen;
import '../../water/water_raw_materials_screen.dart' show WaterRawMaterialsScreen;
import '../../restaurant/restaurant_forms.dart' show restaurantExpensesScreenForHref, restaurantOrdersScreenForHref;
import '../../restaurant/restaurant_staff_loans_screen.dart' show RestaurantStaffLoansScreen;
import '../../restaurant/restaurant_sales_screen.dart' show RestaurantSalesScreen;
import '../../restaurant/restaurant_inventory_screen.dart' show RestaurantInventoryScreen;
import '../../water/water_batch_production_screen.dart'
    show WaterBatchProductionFormScreen, WaterBatchAllocateScreen, WaterBatchProductionDetailScreen;

/// Money links that carry an id or a query: `/poultry-cash-accounts/{id}` (one
/// account's ledger) and `/poultry-cash-reconciliation?accountId=` (opened on
/// that account). Null for anything else.
Widget? moneyScreenForHref(String href, Session session, Company company) {
  final uri = Uri.parse(href);
  final acc = RegExp(r'^/poultry-cash-accounts/(\d+)$').firstMatch(uri.path);
  if (acc != null) return CashAccountDetailScreen(session: session, company: company, accountId: int.parse(acc[1]!));
  // Water's twins (app/water-cash-accounts/[id], /water-cash-reconciliation?accountId=).
  final wacc = RegExp(r'^/water-cash-accounts/(\d+)$').firstMatch(uri.path);
  if (wacc != null) {
    return CashAccountDetailScreen(session: session, company: company, accountId: int.parse(wacc[1]!), rail: waterMoneyRail);
  }
  final wrun = RegExp(r'^/water-payroll/(\d+)$').firstMatch(uri.path);
  if (wrun != null) return WaterPayrollDetailScreen(session: session, company: company, runId: int.parse(wrun[1]!));
  if (uri.path == '/water-cash-reconciliation' && uri.query.isNotEmpty) {
    return ReconciliationScreen(
        session: session, company: company, accountId: int.tryParse(uri.queryParameters['accountId'] ?? ''), rail: waterMoneyRail);
  }
  final run = RegExp(r'^/poultry-payroll/(\d+)$').firstMatch(uri.path);
  if (run != null) return PayrollRunDetailScreen(session: session, company: company, runId: int.parse(run[1]!));
  final asset = RegExp(r'^/poultry-assets/(\d+)$').firstMatch(uri.path);
  if (asset != null) return AssetDetailScreen(session: session, company: company, assetId: int.parse(asset[1]!));
  final waterBatch = RegExp(r'^/water-production-batches/(\d+)$').firstMatch(uri.path);
  if (waterBatch != null) return WaterProductionDetailScreen(session: session, company: company, batchId: int.parse(waterBatch[1]!));
  final day = RegExp(r'^/water-daily-production/(\d+)(/edit|/allocate)?$').firstMatch(uri.path);
  if (day != null) {
    final id = int.parse(day[1]!);
    return switch (day[2]) {
      '/edit' => WaterBatchProductionFormScreen(session: session, company: company, editId: id),
      '/allocate' => WaterBatchAllocateScreen(session: session, company: company, id: id),
      _ => WaterBatchProductionDetailScreen(session: session, company: company, id: id),
    };
  }
  if (uri.path == '/water-daily-production/new') return WaterBatchProductionFormScreen(session: session, company: company);
  final deliveryRun = RegExp(r'^/water-driver-returns/(\d+)$').firstMatch(uri.path);
  if (deliveryRun != null) return WaterDeliveryRunScreen(session: session, company: company, loadingId: int.parse(deliveryRun[1]!));
  final restaurantAsset = RegExp(r'^/restaurant-assets/(\d+)$').firstMatch(uri.path);
  if (restaurantAsset != null) {
    return AssetDetailScreen(session: session, company: company, assetId: int.parse(restaurantAsset[1]!), rail: AssetRail.restaurant);
  }
  final waterAsset = RegExp(r'^/water-assets/(\d+)$').firstMatch(uri.path);
  if (waterAsset != null) {
    return AssetDetailScreen(session: session, company: company, assetId: int.parse(waterAsset[1]!), rail: AssetRail.water);
  }
  // ?purchase=1[&itemId=&qty=] (the menu's Record Purchase), ?tab=, ?tab=purchases&purchaseId=.
  if (uri.path == '/restaurant-inventory' && uri.query.isNotEmpty) {
    final q = uri.queryParameters;
    return RestaurantInventoryScreen(
      session: session,
      company: company,
      tab: q['tab'],
      purchaseId: int.tryParse(q['purchaseId'] ?? ''),
      openPurchase: q['purchase'] == '1',
      purchaseItemId: int.tryParse(q['itemId'] ?? ''),
      purchaseQty: num.tryParse(q['qty'] ?? ''),
    );
  }
  if (uri.path == '/restaurant-sales' && uri.query.isNotEmpty) {
    return RestaurantSalesScreen(session: session, company: company, focusOrderId: int.tryParse(uri.queryParameters['orderId'] ?? ''));
  }
  if (uri.path == '/restaurant-staff-loans' && uri.query.isNotEmpty) {
    return RestaurantStaffLoansScreen(session: session, company: company, staffId: int.tryParse(uri.queryParameters['staffId'] ?? ''));
  }
  if (uri.path == '/restaurant-deferred-costs' && uri.query.isNotEmpty) {
    return DeferredCostsScreen(
      session: session,
      company: company,
      restaurant: true,
      itemId: int.tryParse(uri.queryParameters['itemId'] ?? ''),
      scope: uri.queryParameters['scope'],
    );
  }
  if (uri.path == '/poultry-deferred-costs' && uri.query.isNotEmpty) {
    return DeferredCostsScreen(
      session: session,
      company: company,
      itemId: int.tryParse(uri.queryParameters['itemId'] ?? ''),
      scope: uri.queryParameters['scope'],
    );
  }
  if ((uri.path == '/water-supply-purchases' || uri.path == '/water-raw-materials') && uri.query.isNotEmpty) {
    return WaterRawMaterialsScreen(
      session: session,
      company: company,
      tab: uri.queryParameters['tab'],
      purchaseId: int.tryParse(uri.queryParameters['purchaseId'] ?? ''),
    );
  }
  if (uri.path == '/water-deferred-costs' && uri.query.isNotEmpty) {
    return WaterDeferredCostsScreen(
      session: session,
      company: company,
      itemId: int.tryParse(uri.queryParameters['itemId'] ?? ''),
      scope: uri.queryParameters['scope'],
    );
  }
  final delivery = deliveriesScreenForHref(href, session, company);
  if (delivery != null) return delivery;
  final production = productionScreenForHref(href, session, company);
  if (production != null) return production;
  final batchProduction = batchProductionScreenForHref(href, session, company);
  if (batchProduction != null) return batchProduction;
  final workspace = eggSortingWorkspaceForHref(href, session, company);
  if (workspace != null) return workspace;
  final eggSorting = eggSortingScreenForHref(href, session, company);
  if (eggSorting != null) return eggSorting;
  final feedProduction = feedProductionScreenForHref(href, session, company);
  if (feedProduction != null) return feedProduction;
  final batch = flockBatchScreenForHref(href, session, company);
  if (batch != null) return batch;
  // The stock page ignores ?productId= / ?rawId=, as the web does.
  if (uri.path == '/poultry-stock') return StockMovementsScreen(session: session, company: company);
  final raw = rawMaterialsScreenForHref(href, session, company);
  if (raw != null) return raw;
  if (uri.path == '/expenses' && uri.query.isNotEmpty) return expensesScreenForHref(href, session, company);
  if (uri.path == '/restaurant-expenses' && uri.query.isNotEmpty) return restaurantExpensesScreenForHref(href, session, company);
  if (uri.path == '/restaurant-orders' && uri.query.isNotEmpty) return restaurantOrdersScreenForHref(href, session, company);
  // Supply Purchases' "Receive Invoice" opens the page with the receive form up.
  if (uri.path == '/poultry-purchase-receipts' && uri.query.isNotEmpty) {
    return PurchaseReceiptsScreen(session: session, company: company, openReceive: uri.queryParameters['receive'] == '1');
  }
  if (uri.path == '/poultry-cash-reconciliation') {
    return ReconciliationScreen(session: session, company: company, accountId: int.tryParse(uri.queryParameters['accountId'] ?? ''));
  }
  return null;
}

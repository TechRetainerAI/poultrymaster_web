import 'package:flutter/widgets.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../delivery/deliveries_screen.dart';
import '../expenses/asset_detail_screen.dart';
import '../inventory/stock_movements_screen.dart';
import '../production/batch_production_records_screen.dart';
import '../production/egg_sorting_screen.dart';
import '../production/feed_production_screen.dart';
import '../production/production_records_screen.dart';
import '../purchase/flock_batches_screen.dart';
import '../purchase/raw_materials_screen.dart';
import '../expenses/deferred_costs_screen.dart';
import '../expenses/expenses_screen.dart';
import '../expenses/payroll_screen.dart';
import 'cash_accounts_screen.dart';
import 'reconciliation_screen.dart';

/// Money links that carry an id or a query: `/poultry-cash-accounts/{id}` (one
/// account's ledger) and `/poultry-cash-reconciliation?accountId=` (opened on
/// that account). Null for anything else.
Widget? moneyScreenForHref(String href, Session session, Company company) {
  final uri = Uri.parse(href);
  final acc = RegExp(r'^/poultry-cash-accounts/(\d+)$').firstMatch(uri.path);
  if (acc != null) return CashAccountDetailScreen(session: session, company: company, accountId: int.parse(acc[1]!));
  final run = RegExp(r'^/poultry-payroll/(\d+)$').firstMatch(uri.path);
  if (run != null) return PayrollRunDetailScreen(session: session, company: company, runId: int.parse(run[1]!));
  final asset = RegExp(r'^/poultry-assets/(\d+)$').firstMatch(uri.path);
  if (asset != null) return AssetDetailScreen(session: session, company: company, assetId: int.parse(asset[1]!));
  if (uri.path == '/poultry-deferred-costs' && uri.query.isNotEmpty) {
    return DeferredCostsScreen(
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
  if (uri.path == '/poultry-cash-reconciliation') {
    return ReconciliationScreen(session: session, company: company, accountId: int.tryParse(uri.queryParameters['accountId'] ?? ''));
  }
  return null;
}

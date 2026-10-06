import 'package:flutter/widgets.dart';

import '../../../models/company.dart';
import '../../../state/session.dart';
import '../expenses/asset_detail_screen.dart';
import '../expenses/deferred_costs_screen.dart';
import '../expenses/expenses_screen.dart';
import 'cash_accounts_screen.dart';
import 'reconciliation_screen.dart';

/// Money links that carry an id or a query: `/poultry-cash-accounts/{id}` (one
/// account's ledger) and `/poultry-cash-reconciliation?accountId=` (opened on
/// that account). Null for anything else.
Widget? moneyScreenForHref(String href, Session session, Company company) {
  final uri = Uri.parse(href);
  final acc = RegExp(r'^/poultry-cash-accounts/(\d+)$').firstMatch(uri.path);
  if (acc != null) return CashAccountDetailScreen(session: session, company: company, accountId: int.parse(acc[1]!));
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
  if (uri.path == '/expenses' && uri.query.isNotEmpty) return expensesScreenForHref(href, session, company);
  if (uri.path == '/poultry-cash-reconciliation') {
    return ReconciliationScreen(session: session, company: company, accountId: int.tryParse(uri.queryParameters['accountId'] ?? ''));
  }
  return null;
}

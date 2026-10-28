// The Hotel's Money pages (Owner Money, Loans (Financing), Cash Account) are
// Poultry's pages word for word, in violet, over /api/Hotel (migration 331).
// This is the rail the shared screens run them on.

import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../poultry/reports/money_reports.dart' show MoneyRail;
import '../poultry/trackers/tracker_widgets.dart' show TColors;
import 'reports/hotel_reports_catalog.dart';

Widget _catalog(Session s, Company c) => HotelReportsCatalogScreen(session: s, company: c);

const hotelMoneyRail = MoneyRail(
  api: '/api/Hotel',
  idPrefix: 'hotel',
  // Poultry's Cash Account Report button; the Hotel's nearest report is its Cash Flow Report.
  cashAccountsHref: '/hotel-reports/cash-flow-report',
  moneyHref: '/hotel-reports',
  cashTitle: 'Hotel Cash Account Report',
  cashFilename: 'hotel-cash-accounts',
  cashFlowHref: '/hotel-cash-flow',
  reconcileHref: '/hotel-cash-reconciliation',
  entity: 'hotel',
  catalog: _catalog,
  cashAccountsPath: '/api/Hotel/finance/cash-accounts',
  accent: TColors.violet600,
);

import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import 'hotel_company_setup_screen.dart';
import 'hotel_expenses_screen.dart';
import 'hotel_payroll_screen.dart';
import 'hotel_employee_loans_screen.dart';
import 'hotel_cash_flow_screen.dart';
import 'hotel_money_rail.dart';
import 'hotel_restaurant_screens.dart';
import 'hotel_guest_service_screens.dart';
import 'hotel_rooms_screens.dart';
import 'hotel_front_desk_screens.dart';
import 'hotel_front_desk2_screens.dart';
import 'hotel_quick_links_screens.dart';
import 'hotel_dashboard_view.dart';
import '../poultry/money/owner_money_screen.dart' show OwnerMoneyScreen;
import '../poultry/money/loans_screen.dart' show LoansScreen;
import '../poultry/money/cash_accounts_screen.dart' show CashAccountsScreen;
import '../poultry/money/cash_transfers_screen.dart' show CashTransfersScreen;
import '../poultry/money/reconciliation_screen.dart' show ReconciliationScreen;
import 'hotel_profit_loss_screen.dart';
import '../poultry/money/financial_activity_screen.dart' show FinancialActivityScreen;
import '../poultry/expenses/deferred_costs_screen.dart';
import '../poultry/expenses/assets_screen.dart' show AssetsScreen;
import '../poultry/expenses/asset_logic.dart' show AssetRail;
import '../poultry/expenses/recurring_expenses_screen.dart';
import '../restaurant/restaurant_internal_use_screen.dart' show RestaurantInternalUseScreen, hotelInternalUseFlavor;
import 'hotel_maintenance_screen.dart';
import '../poultry/sales/balances_logic.dart' show BalanceRail, BalanceSide;
import '../poultry/sales/customer_balances_screen.dart';
import '../poultry/sales/payments_received_screen.dart';
import '../poultry/expenses/supplier_payments_screen.dart';
import 'hotel_parties_screen.dart';
import 'hotel_sales_screen.dart';
import 'hotel_setup_screen.dart';
import 'hotel_staff_screen.dart';
import 'hotel_supplies_screen.dart';

/// Hotel routes that open a screen of their own, keyed by web href.
const Map<String, PageScreenBuilder> hotelPageScreens = {
  '/hotel-company-setup': _companySetup,
  '/hotel-setup': _setup,
  '/hotel-staff': _staff,
  '/hotel-customers': _customers,
  '/hotel-suppliers': _suppliers,
  '/hotel-inventory': _supplies,
  '/hotel-maintenance': _maintenance,
  '/hotel-sales': _sales,
  '/hotel-payments': _payments,
  '/hotel-customer-balances': _customerBalances,
  '/hotel-expenses': _expenses,
  '/hotel-supplier-payments': _supplierPayments,
  '/hotel-supplier-balances': _supplierBalances,
  '/hotel-recurring-expenses': _recurring,
  '/hotel-internal-use': _internalUse,
  '/hotel-payroll': _payroll,
  '/hotel-employee-loans': _employeeLoans,
  '/hotel-deferred-costs': _deferredCosts,
  '/hotel-assets': _assets,
  '/hotel-cash-flow': _cashFlow,
  '/hotel-financial-activity': _financialActivity,
  '/hotel-profit-loss': _profitLoss,
  '/hotel-owner-money': _ownerMoney,
  '/hotel-loans': _loans,
  '/hotel-cash-accounts': _cashAccounts,
  '/hotel-cash-transfers': _cashTransfers,
  '/hotel-cash-reconciliation': _reconciliation,
  '/hotel-restaurant': _restaurantOrders,
  '/hotel-menu': _menu,
  '/hotel-kitchen': _kitchen,
  '/hotel-restaurant-tables': _tables,
  '/hotel-communications': _guestLog,
  '/hotel-guest-requests': _guestRequests,
  '/hotel-lost-found': _lostFound,
  '/hotel-rooms': _rooms,
  '/hotel-housekeeping': _housekeeping,
  '/hotel-housekeeping-schedule': _hkSchedule,
  '/hotel-room-service': _roomService,
  '/hotel-bookings': _bookings,
  '/hotel-guests': _guests,
  '/hotel-check-in': _checkIn,
  '/hotel-check-out': _checkOut,
  '/hotel-availability': _availability,
  '/hotel-guest-folio': _guestFolio,
  '/hotel-billing': _billing,
  '/hotel-invoices': _invoices,
  '/hotel-stay-history': _stayHistory,
  '/hotel-daily-closing': _dailyClosing,
  '/hotel-night-audit': _nightAudit,
  '/hotel-shift-handover': _shiftHandover,
  '/hotel-dashboard': _dashboard,
};

Widget _dashboard(Session s, Company c) => HotelDashboardScreen(session: s, company: c);

Widget _dailyClosing(Session s, Company c) => HotelDailyClosingScreen(session: s, company: c);
Widget _nightAudit(Session s, Company c) => HotelNightAuditScreen(session: s, company: c);
Widget _shiftHandover(Session s, Company c) => HotelShiftHandoverScreen(session: s, company: c);

Widget _billing(Session s, Company c) => HotelBillingScreen(session: s, company: c);
Widget _invoices(Session s, Company c) => HotelInvoicesScreen(session: s, company: c);
Widget _stayHistory(Session s, Company c) => HotelStayHistoryScreen(session: s, company: c);

Widget _checkOut(Session s, Company c) => HotelCheckOutScreen(session: s, company: c);
Widget _availability(Session s, Company c) => HotelAvailabilityScreen(session: s, company: c);
Widget _guestFolio(Session s, Company c) => HotelGuestFolioScreen(session: s, company: c);

Widget _bookings(Session s, Company c) => HotelBookingsScreen(session: s, company: c);
Widget _guests(Session s, Company c) => HotelGuestsScreen(session: s, company: c);
Widget _checkIn(Session s, Company c) => HotelCheckInScreen(session: s, company: c);

Widget _rooms(Session s, Company c) => HotelRoomsScreen(session: s, company: c);
Widget _housekeeping(Session s, Company c) => HotelHousekeepingScreen(session: s, company: c);
Widget _hkSchedule(Session s, Company c) => HotelHKScheduleScreen(session: s, company: c);
Widget _roomService(Session s, Company c) => HotelRoomServiceScreen(session: s, company: c);

Widget _guestLog(Session s, Company c) => HotelGuestLogScreen(session: s, company: c);
Widget _guestRequests(Session s, Company c) => HotelGuestRequestsScreen(session: s, company: c);
Widget _lostFound(Session s, Company c) => HotelLostFoundScreen(session: s, company: c);

Widget _restaurantOrders(Session s, Company c) => HotelRestaurantOrdersScreen(session: s, company: c);
Widget _menu(Session s, Company c) => HotelMenuScreen(session: s, company: c);
Widget _kitchen(Session s, Company c) => HotelKitchenScreen(session: s, company: c);
Widget _tables(Session s, Company c) => HotelTablesScreen(session: s, company: c);

Widget _cashTransfers(Session s, Company c) => CashTransfersScreen(session: s, company: c, rail: hotelMoneyRail);
Widget _reconciliation(Session s, Company c) => ReconciliationScreen(session: s, company: c, rail: hotelMoneyRail);

Widget _ownerMoney(Session s, Company c) => OwnerMoneyScreen(session: s, company: c, rail: hotelMoneyRail);
Widget _loans(Session s, Company c) => LoansScreen(session: s, company: c, rail: hotelMoneyRail);
Widget _cashAccounts(Session s, Company c) => CashAccountsScreen(session: s, company: c, rail: hotelMoneyRail);

Widget _cashFlow(Session s, Company c) => HotelCashFlowScreen(session: s, company: c);
Widget _financialActivity(Session s, Company c) => FinancialActivityScreen(session: s, company: c, hotel: true);
Widget _profitLoss(Session s, Company c) => HotelProfitLossScreen(session: s, company: c);

Widget _recurring(Session s, Company c) => RecurringExpensesScreen(session: s, company: c);
Widget _internalUse(Session s, Company c) => RestaurantInternalUseScreen(session: s, company: c, flavor: hotelInternalUseFlavor);
Widget _payroll(Session s, Company c) => HotelPayrollScreen(session: s, company: c);
Widget _employeeLoans(Session s, Company c) => HotelEmployeeLoansScreen(session: s, company: c);
Widget _deferredCosts(Session s, Company c) => DeferredCostsScreen(session: s, company: c, hotel: true);
Widget _assets(Session s, Company c) => AssetsScreen(session: s, company: c, rail: AssetRail.hotel);

Widget _companySetup(Session s, Company c) => HotelCompanySetupScreen(session: s, company: c);
Widget _setup(Session s, Company c) => HotelSetupScreen(session: s, company: c);
Widget _staff(Session s, Company c) => HotelStaffScreen(session: s, company: c);
Widget _customers(Session s, Company c) => HotelPartiesScreen(session: s, company: c, kind: HotelPartyKind.customers);
Widget _suppliers(Session s, Company c) => HotelPartiesScreen(session: s, company: c, kind: HotelPartyKind.suppliers);
Widget _supplies(Session s, Company c) => HotelSuppliesScreen(session: s, company: c);
Widget _maintenance(Session s, Company c) => HotelMaintenanceScreen(session: s, company: c);
Widget _sales(Session s, Company c) => HotelSalesScreen(session: s, company: c);
Widget _payments(Session s, Company c) => PaymentsReceivedScreen(session: s, company: c, rail: BalanceRail.hotel);
Widget _customerBalances(Session s, Company c) => CustomerBalancesScreen(session: s, company: c, rail: BalanceRail.hotel);
Widget _expenses(Session s, Company c) => HotelExpensesScreen(session: s, company: c);
Widget _supplierPayments(Session s, Company c) => SupplierPaymentsScreen(session: s, company: c, rail: BalanceRail.hotel);
Widget _supplierBalances(Session s, Company c) =>
    CustomerBalancesScreen(session: s, company: c, side: BalanceSide.supplier, rail: BalanceRail.hotel);

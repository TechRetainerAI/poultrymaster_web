import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/companies_api.dart';
import '../api/dashboard_api.dart';
import '../config/env.dart';
import '../models/company.dart';
import 'token_store.dart';

/// Single source of truth for "who is signed in and which company are they in".
///
/// Deliberately plain [ChangeNotifier] — no state-management package — so the
/// app has one fewer dependency to keep current.
class Session extends ChangeNotifier {
  Session._(this.tokens, this.loginClient, this.farmClient)
      : auth = AuthApi(loginClient, tokens),
        companies = CompaniesApi(loginClient, tokens),
        dashboard = DashboardApi(farmClient);

  final TokenStore tokens;
  final ApiClient loginClient;
  final ApiClient farmClient;
  final AuthApi auth;
  final CompaniesApi companies;
  final DashboardApi dashboard;

  static Future<Session> create() async {
    final tokens = await TokenStore.open();
    final loginClient = ApiClient(baseUrl: Env.loginApi, tokens: tokens);
    final farmClient = ApiClient(baseUrl: Env.farmApi, tokens: tokens);
    final session = Session._(tokens, loginClient, farmClient);

    // Both clients refresh through the same auth endpoint, and a refresh
    // failure means the session is over for both.
    loginClient.refreshCallback = session.auth.refresh;
    farmClient.refreshCallback = session.auth.refresh;
    loginClient.onAuthLost = session._onAuthLost;
    farmClient.onAuthLost = session._onAuthLost;

    return session;
  }

  bool get isSignedIn => tokens.hasSession;
  String? get username => tokens.username;

  List<Company> _myCompanies = const [];
  List<Company> get myCompanies => _myCompanies;

  Company? _active;
  Company? get active => _active;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  void _onAuthLost() {
    _active = null;
    _myCompanies = const [];
    notifyListeners();
  }

  Future<void> loadCompanies() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final all = await companies.mine();

      // When signed in with an organisation code, show only that office's
      // companies — matching the web's ownerUserId filter.
      _myCompanies = _orgScope == null
          ? all
          : all.where((c) => (c.ownerUserId ?? '') == _orgScope).toList();
      if (_orgScope != null && _myCompanies.isEmpty) _orgMismatch = true;

      // Restore the previously active company across restarts.
      final savedId = tokens.farmId;
      if (savedId != null && savedId.isNotEmpty) {
        for (final c in _myCompanies) {
          if (c.farmId == savedId) {
            _active = c;
            break;
          }
        }
      }
      // Note: no auto-selection, even for a single-company user. The web makes
      // this choice deliberately (Doc 3 §4/§9) — everyone lands company-neutral
      // in the Business Office and picks a company explicitly, rather than
      // defaulting into one. Auto-selecting here would diverge from that.
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not load your companies.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Scopes the company list to a Business Office after sign-in.
  ///
  /// An empty code means "all my companies". A code that resolves to nothing,
  /// or to an organisation the user has no companies in, is a mismatch — the
  /// web surfaces that as an error rather than silently showing everything.
  Future<void> applyOrgScope({required String orgCode, required bool remember}) async {
    final code = orgCode.trim().toUpperCase();
    await tokens.saveOrgCode(code, remember: remember);
    _orgScope = null;

    if (code.isEmpty) return;

    final org = await auth.resolveOrgCode(code);
    if (org == null || org.ownerUserId.isEmpty) {
      _orgMismatch = true;
      notifyListeners();
      return;
    }
    _orgScope = org.ownerUserId;
    _orgName = org.businessOfficeName;
  }

  String? _orgScope;
  String? _orgName;
  bool _orgMismatch = false;

  String? get organisationName => _orgName;
  bool get orgMismatch => _orgMismatch;

  void clearOrgMismatch() {
    _orgMismatch = false;
    notifyListeners();
  }

  /// Switching is a server call — it returns a new token scoped to the company.
  Future<bool> setActive(Company company) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await companies.switchTo(company);
      _active = company;
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await auth.logout();
    _active = null;
    _myCompanies = const [];
    notifyListeners();
  }
}

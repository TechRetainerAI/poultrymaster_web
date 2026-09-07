import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/session.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AppState extends ChangeNotifier {
  AuthStatus status = AuthStatus.unknown;
  Session? get session => ApiClient.instance.session;

  AppState() {
    ApiClient.instance.onSessionExpired = () => signOut(remote: false);
    _restore();
  }

  Future<void> _restore() async {
    final s = await ApiClient.instance.restoreSession();
    status = (s != null && s.token.isNotEmpty) ? AuthStatus.signedIn : AuthStatus.signedOut;
    notifyListeners();
  }

  void onSignedIn() {
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> signOut({bool remote = true}) async {
    if (remote) {
      await AuthService.logout();
    } else {
      await ApiClient.instance.clearSession();
    }
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

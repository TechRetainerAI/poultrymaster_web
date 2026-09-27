import 'package:flutter/material.dart';

import 'design/app_theme.dart';
import 'screens/business_office_screen.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await Session.create();
  runApp(PoultryCoreApp(session: session));
}

class PoultryCoreApp extends StatelessWidget {
  const PoultryCoreApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PoultryCore',
      debugShowCheckedModeBanner: false,
      // Ported from the web's globals.css — see design/tokens.dart.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: RootGate(session: session),
    );
  }
}

/// Decides, on every session change, which of the three states the user is in:
/// signed out, signed in but no company chosen, or working inside a company.
class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.session});
  final Session session;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// A stored token is not proof of a usable session — it may have expired
  /// while the app was closed. Loading the company list is the cheapest real
  /// check, and it populates the picker at the same time.
  Future<void> _bootstrap() async {
    if (widget.session.isSignedIn) {
      await widget.session.loadCompanies();
    }
    if (mounted) setState(() => _bootstrapping = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final session = widget.session;

        if (!session.isSignedIn) {
          return LoginScreen(
            session: session,
            onSignedIn: () async {
              await session.loadCompanies();
              if (mounted) setState(() {});
            },
          );
        }

        if (session.active == null) {
          // The web lands everyone in the company-neutral Business Office.
          return BusinessOfficeScreen(
            session: session,
            onPicked: () => setState(() {}),
            onSignedOut: () => setState(() {}),
          );
        }

        return AppShell(
          session: session,
          onSignedOut: () => setState(() {}),
        );
      },
    );
  }
}

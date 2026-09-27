import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/env.dart';
import '../design/tokens.dart';
import '../design/ui/buttons.dart';
import '../models/company.dart';
import '../state/session.dart';

/// For the web routes that have no API of their own to list — the report
/// dashboards, the setup wizards, and written pages like Terms.
///
/// These are composite pages: a reports dashboard stitches many endpoints
/// together, so there is no single one a generated spec could point at. Rather
/// than leave them as a link to copy, the real page is rendered here, signed in
/// as the same user and the same company the app is already on.
///
/// The sign-in is done by writing the browser session the web app expects
/// BEFORE its JavaScript runs, then navigating. A WebView starts with empty
/// storage, so without this the page would only ever show its login screen.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({
    super.key,
    required this.label,
    required this.href,
    required this.company,
    this.session,
  });

  final String label;
  final String href;
  final Company company;

  /// When absent the page still loads, but as a signed-out visitor.
  final Session? session;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  static String get _base => Env.isProd
      ? 'https://www.visibilitycore.com'
      : 'https://poultrymaster-web-dev-t6tn7geswq-ew.a.run.app';

  String get _url => '$_base${widget.href}';

  /// The web app keeps its session in two places and reads both: a Zustand
  /// `auth-storage` blob, and the loose `farmId` / `farmType` keys that
  /// lib/api/config.ts reads directly. Both are written, because a page that
  /// finds one but not the other throws "No active company" and blanks itself.
  String get _sessionScript {
    final s = widget.session;
    if (s == null) return '';
    final t = s.tokens;
    final c = widget.company;

    final auth = jsonEncode({
      'state': {
        'token': t.accessToken,
        'refreshToken': t.refreshToken,
        'user': {'id': t.userId, 'username': t.username, 'farmId': c.farmId},
        'isAuthenticated': true,
        'companies': [
          {'farmId': c.farmId, 'name': c.name, 'type': c.type.wire},
        ],
        'activeFarmId': c.farmId,
        'activeFarmName': c.name,
        'activeFarmType': c.type.wire,
      },
      'version': 0,
    });

    final pairs = <String, String>{
      'auth-storage': auth,
      'farmId': c.farmId,
      'farmName': c.name,
      'farmType': c.type.wire,
      if (t.userId != null) 'userId': t.userId!,
      if (t.accessToken != null) 'token': t.accessToken!,
    };

    final sets = pairs.entries
        .map((e) =>
            'localStorage.setItem(${jsonEncode(e.key)}, ${jsonEncode(e.value)});')
        .join('\n');
    return 'try { $sets } catch (e) {}';
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          // Sub-resource failures (an icon, an analytics call) are not the page
          // failing, and reporting them would cry wolf on a page that rendered.
          if (!e.isForMainFrame!) return;
          if (mounted) setState(() => _error = e.description);
        },
      ));
    _start();
  }

  /// Storage is per-origin and only exists once a document from that origin is
  /// loaded, so a blank page on the same origin is loaded first, the session is
  /// written into it, and only then is the real page opened.
  Future<void> _start() async {
    final script = _sessionScript;
    if (script.isEmpty) {
      await _controller.loadRequest(Uri.parse(_url));
      return;
    }
    _controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) async {
        await _controller.runJavaScript(script);
        _controller
          ..setNavigationDelegate(NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (e) {
              if (!e.isForMainFrame!) return;
              if (mounted) setState(() => _error = e.description);
            },
          ))
          ..loadRequest(Uri.parse(_url));
      },
    ));
    await _controller.loadRequest(Uri.parse('$_base/login'));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied')),
              );
            },
          ),
        ],
      ),
      body: _error != null
          ? _Failed(message: _error!, url: _url, onRetry: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _start();
            })
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  Container(
                    color: tokens.card,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message, required this.url, required this.onRetry});

  final String message;
  final String url;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 42, color: tokens.mutedForeground),
            const SizedBox(height: 16),
            const Text('This page could not be loaded',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: tokens.mutedForeground)),
            const SizedBox(height: 18),
            AppButton(label: 'Try again', icon: Icons.refresh, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

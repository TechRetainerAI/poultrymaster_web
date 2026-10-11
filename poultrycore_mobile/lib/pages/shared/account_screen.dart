// Settings → Account (app/profile/page.tsx): "User Profile" — About you,
// Contact information, Farm details, Account status and Security (2FA), with
// Edit / Cancel / Save through the Login API.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_logic.dart' show tStr;
import '../poultry/trackers/tracker_widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, Object?>? _p;
  bool _loading = true, _editing = false, _saving = false, _toggling = false;
  String _error = '';
  final _first = TextEditingController(), _last = TextEditingController(), _email = TextEditingController();
  final _phone = TextEditingController(), _farm = TextEditingController();

  ApiClient get _auth => widget.session.loginClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _phone, _farm]) {
      c.dispose();
    }
    super.dispose();
  }

  Object? _pick(Map r, List<String> keys) {
    for (final k in keys) {
      if (r[k] != null) return r[k];
    }
    return null;
  }

  void _fill() {
    final p = _p!;
    _first.text = tStr(p['firstName']);
    _last.text = tStr(p['lastName']);
    _email.text = tStr(p['email']);
    _phone.text = tStr(p['phoneNumber']);
    _farm.text = tStr(p['farmName']);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final raw = await _auth.get('/api/Authentication/get-current-user');
      final r = raw is Map ? raw : {};
      _p = {
        'id': tStr(_pick(r, ['id', 'Id'])),
        'userName': tStr(_pick(r, ['userName', 'UserName', 'username'])),
        'email': tStr(_pick(r, ['email', 'Email'])),
        'emailConfirmed': true,
        'phoneNumber': tStr(_pick(r, ['phoneNumber', 'PhoneNumber'])),
        'phoneNumberConfirmed': false,
        'twoFactorEnabled': _pick(r, ['twoFactorEnabled', 'TwoFactorEnabled']) == true,
        'farmId': tStr(_pick(r, ['farmId', 'FarmId'])),
        'farmName': tStr(_pick(r, ['farmName', 'FarmName'])),
        'isStaff': _pick(r, ['isStaff', 'IsStaff']) == true,
        'isSubscriber': _pick(r, ['isSubscriber', 'IsSubscriber']) == true,
        'firstName': tStr(_pick(r, ['firstName', 'FirstName'])),
        'lastName': tStr(_pick(r, ['lastName', 'LastName'])),
      };
      _fill();
    } on ApiException catch (e) {
      final t = widget.session.tokens;
      if (e.statusCode == 404 && (t.userId ?? '').isNotEmpty && (t.username ?? '').isNotEmpty) {
        // As the web: fall back to what the session already knows.
        _p = {
          'id': t.userId,
          'userName': t.username,
          'email': t.username,
          'emailConfirmed': false,
          'phoneNumber': '',
          'phoneNumberConfirmed': false,
          'twoFactorEnabled': false,
          'farmId': widget.company.farmId,
          'farmName': widget.company.name,
          'isStaff': (widget.company.role ?? '').toLowerCase() == 'staff',
          'isSubscriber': false,
          'firstName': '',
          'lastName': '',
        };
        _fill();
      } else {
        _error = e.message.isNotEmpty ? e.message : 'Failed to load profile. Please try again.';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _cancel() => setState(() {
        _editing = false;
        _error = '';
        if (_p != null) _fill();
      });

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await _auth.put('/api/Authentication/update-profile', body: {
        'firstName': _first.text,
        'lastName': _last.text,
        'email': _email.text,
        'phoneNumber': _phone.text,
        'farmName': _farm.text,
      });
      if (!mounted) return;
      setState(() => _editing = false);
      await _success('Profile Updated Successfully!', 'Your profile information has been updated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to update profile (HTTP ${e.statusCode})');
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _toggle2fa(bool enabled) async {
    setState(() {
      _toggling = true;
      _error = '';
    });
    try {
      await _auth.post('/api/Authentication/${enabled ? 'enable-2fa' : 'disable-2fa'}');
      if (!mounted) return;
      setState(() => _p = {...?_p, 'twoFactorEnabled': enabled});
      await _success(
        enabled ? '2FA Enabled!' : '2FA Disabled!',
        enabled
            ? "Two-factor authentication has been enabled. You'll receive OTP codes via email during login."
            : 'Two-factor authentication has been disabled. You can enable it again anytime from your profile.',
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message.isNotEmpty ? e.message : 'Failed to ${enabled ? 'enable' : 'disable'} 2FA (HTTP ${e.statusCode})');
      }
    }
    if (mounted) setState(() => _toggling = false);
  }

  Future<void> _success(String title, String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: TColors.emerald600, size: 40),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(message, textAlign: TextAlign.center),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue'))],
        ),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _row(String label, Object? value, {IconData? icon, bool mono = false, Widget? trailing}) {
    final s = value is String ? value : tStr(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: TColors.slate400), const SizedBox(width: 8)],
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 14, color: TColors.slate500))),
        Expanded(
          flex: 3,
          child: value is Widget
              ? Align(alignment: Alignment.centerLeft, child: value)
              : s.isEmpty
                  ? const Text('Not set', style: TextStyle(fontSize: 14, color: TColors.slate400))
                  : Row(children: [
                      Flexible(child: Text(s, style: TextStyle(fontSize: mono ? 12 : 14, fontFamily: mono ? 'monospace' : null, color: TColors.slate900))),
                      ?trailing,
                    ]),
        ),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 14, color: TColors.slate600)),
          const SizedBox(height: 4),
          AppInput(controller: c, hintText: hint, enabled: !_saving, keyboardType: type),
        ]),
      );

  Widget _verified(bool v) => v
      ? const TBadge('Verified', bg: TColors.emerald50, fg: TColors.emerald700, border: Color(0xFFA7F3D0))
      : const TBadge('Not Verified', bg: TColors.slate50, fg: TColors.slate600, border: TColors.slate200);

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/profile');
    final p = _p;
    final fullName = '${tStr(p?['firstName'])} ${tStr(p?['lastName'])}'.trim();
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('User Profile')),
      body: _loading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading profile...', style: TextStyle(color: TColors.slate600)),
              ]),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('User Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
                    Text('Manage information about you and this account', style: TextStyle(fontSize: 14, color: TColors.slate600)),
                  ]),
                ),
                if (!_editing)
                  OutlinedButton.icon(onPressed: () => setState(() {
                    _editing = true;
                    _error = '';
                  }), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
              ]),
              if (_editing) ...[
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TColors.red600),
                    onPressed: _saving ? null : _cancel,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: TColors.blue600),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              if (_error.isNotEmpty) ...[TrackerBanner.error(_error), const SizedBox(height: 14)],
              if (p != null) ...[
                _section('About you', [
                  if (_editing) ...[
                    _field('First Name', _first, 'John'),
                    _field('Last Name', _last, 'Doe'),
                  ] else ...[
                    _row('Account type', p['isStaff'] == true ? 'Staff' : (p['isSubscriber'] == true ? 'Subscriber' : 'Organization')),
                    _row('User ID', p['id'], mono: true),
                    _row('Username', p['userName']),
                    _row('Full name', fullName.isNotEmpty ? fullName : 'Not set'),
                  ],
                ]),
                _section('Contact information', [
                  if (_editing) ...[
                    _field('Email address', _email, 'john@example.com', type: TextInputType.emailAddress),
                    _field('Phone number', _phone, '+1 (555) 123-4567', type: TextInputType.phone),
                  ] else ...[
                    _row('Email address', p['email'],
                        icon: Icons.mail_outline,
                        trailing: p['emailConfirmed'] == true
                            ? const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check, size: 16, color: Color(0xFF10B981)))
                            : null),
                    _row('Phone number', p['phoneNumber'], icon: Icons.phone_outlined),
                  ],
                ]),
                _section('Farm details', [
                  if (_editing)
                    _field('Farm name', _farm, 'My Farm')
                  else ...[
                    _row('Farm name', p['farmName'], icon: Icons.business_outlined),
                    _row('Farm ID', p['farmId'], mono: true),
                  ],
                ]),
                _section('Account status', [
                  _row('Email verified', _verified(p['emailConfirmed'] == true)),
                  _row('Phone verified', _verified(p['phoneNumberConfirmed'] == true)),
                ]),
                _section('Security', [
                  Row(children: [
                    const Icon(Icons.shield_outlined, size: 20, color: TColors.slate400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Two-factor authentication', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                        Text(p['twoFactorEnabled'] == true ? 'Enabled - OTP codes sent via email' : 'Add extra security to your account',
                            style: const TextStyle(fontSize: 12, color: TColors.slate500)),
                      ]),
                    ),
                    Switch(value: p['twoFactorEnabled'] == true, onChanged: _toggling ? null : _toggle2fa),
                  ]),
                ]),
              ],
            ]),
    );
  }
}

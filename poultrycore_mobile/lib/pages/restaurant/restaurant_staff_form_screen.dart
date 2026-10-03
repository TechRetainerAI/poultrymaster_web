import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'restaurant_roles.dart';

/// Restaurant → Menu & Setup → Staff → Add / Edit, as the web's dialog in
/// `app/restaurant-staff/page.tsx`: the person, a grid of role tiles (icon,
/// name, what the role does) with the chosen one ringed in rose, then pay.
/// Saves to `/api/Restaurant/staff` — PUT takes farmId in the query.
class RestaurantStaffFormScreen extends StatefulWidget {
  const RestaurantStaffFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<RestaurantStaffFormScreen> createState() => _RestaurantStaffFormScreenState();
}

/// SALARY_TYPES — Restaurant's own, with Hourly.
const _payTypes = ['Monthly', 'Weekly', 'Daily', 'Hourly', 'Commission'];

class _RestaurantStaffFormScreenState extends State<RestaurantStaffFormScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _basePay = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _role = 'Waiter';
  String _payType = 'Monthly';
  bool _saving = false;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _editing => _row != null;

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r == null) return;
    String s(String k) => r[k] == null ? '' : '${r[k]}';
    _first.text = s('firstName');
    _last.text = s('lastName');
    _phone.text = s('phone');
    _email.text = s('email');
    _role = s('role').isEmpty ? 'Waiter' : s('role');
    _payType = _payTypes.contains(s('salaryType')) ? s('salaryType') : 'Monthly';
    _basePay.text = s('basePay').isEmpty ? '0' : s('basePay');
    _notes.text = s('notes');
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _basePay, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      return _snack('Name and phone required');
    }
    setState(() => _saving = true);
    final farmId = widget.company.farmId;
    final input = <String, dynamic>{
      'firstName': _first.text.trim(),
      'lastName': _last.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'role': _role,
      'salaryType': _payType,
      'basePay': double.tryParse(_basePay.text.trim()) ?? 0,
      'notes': _notes.text.trim(),
    };
    try {
      final client = widget.session.farmClient;
      if (_editing) {
        await client.put(
          '/api/Restaurant/staff/${_row!['restaurantStaffId']}?farmId=${Uri.encodeComponent(farmId)}',
          body: input,
        );
      } else {
        await client.post('/api/Restaurant/staff', body: {...input, 'farmId': farmId});
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _snack(_editing ? 'Staff updated' : 'Staff member added');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed. ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editing ? 'Edit Staff Member' : 'Add Staff Member',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('Add team members and assign their restaurant role',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(title: 'Team member', color: SectionColor.rose, children: [
            AppField(label: 'First Name', required: true, child: AppInput(controller: _first)),
            AppField(label: 'Last Name', child: AppInput(controller: _last)),
            AppField(label: 'Phone', required: true,
                child: AppInput(controller: _phone, keyboardType: TextInputType.phone)),
            AppField(label: 'Email',
                child: AppInput(controller: _email, keyboardType: TextInputType.emailAddress)),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Role', color: SectionColor.rose, columns: 1, children: [
            AppField(label: '', full: true, child: _roleGrid()),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Pay', color: SectionColor.rose, children: [
            AppField(
              label: 'Pay Type',
              child: AppSelect<String>(
                value: _payType,
                items: [for (final t in _payTypes) AppSelectItem(value: t, label: t)],
                onChanged: (v) => setState(() => _payType = v ?? _payType),
              ),
            ),
            AppField(label: 'Base Pay',
                child: AppNumberInput(controller: _basePay, allowDecimal: true)),
            AppField(label: 'Notes', full: true,
                child: AppInput(controller: _notes, hintText: 'Optional notes')),
          ]),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.outline,
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: restaurantRose,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_editing ? 'Update' : 'Add Member'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Two tiles a row, the chosen one with a rose border and tint.
  Widget _roleGrid() {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in restaurantRoles)
            SizedBox(
              width: w,
              child: _RoleTile(
                role: r,
                selected: _role == r.value,
                onTap: () => setState(() => _role = r.value),
              ),
            ),
        ],
      );
    });
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({required this.role, required this.selected, required this.onTap});
  final RestaurantRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: selected ? const Color(0xFFFFF1F2) : Colors.transparent, // rose-50
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(width: 2, color: selected ? restaurantRose : tokens.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Text(role.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: selected ? const Color(0xFFBE123C) : null)), // rose-700
                    Text(role.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: tokens.mutedForeground)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

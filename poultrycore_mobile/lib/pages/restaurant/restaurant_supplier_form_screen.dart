import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import 'restaurant_roles.dart';

/// Restaurant → Suppliers → Add / Edit, as `app/restaurant-suppliers/page.tsx`:
/// Contact (with a Category list whose "Other" switches to typing) and
/// Address. Saves to `/api/Restaurant/setup/suppliers`.
///
/// Rows come back with raw lowercase column names (`restaurantsupplierid`,
/// `contactname`, `isactive`), so edit reads those.
class RestaurantSupplierFormScreen extends StatefulWidget {
  const RestaurantSupplierFormScreen({
    super.key,
    required this.session,
    required this.company,
    this.existing,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic>? existing;

  @override
  State<RestaurantSupplierFormScreen> createState() => _RestaurantSupplierFormScreenState();
}

/// SUPPLIER_CATEGORIES in lib/api/restaurant-suppliers.ts.
const _categories = [
  'Food ingredients', 'Vegetables & fruit', 'Meat & poultry', 'Fish & seafood', 'Drinks',
  'Cooking materials', 'Packaging', 'Tableware', 'Cleaning & kitchen supplies',
];
const _other = '__other__';

class _RestaurantSupplierFormScreenState extends State<RestaurantSupplierFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _category = TextEditingController();
  final _contact = TextEditingController();
  final _address = TextEditingController();
  String _categoryPick = '';
  bool _typing = false;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _row => widget.existing;
  bool get _editing => _row != null;
  Object? get _id => _row?['restaurantsupplierid'] ?? _row?['restaurantSupplierId'];

  @override
  void initState() {
    super.initState();
    final r = _row;
    if (r == null) return;
    String s(String a, [String? b]) => '${r[a] ?? (b == null ? null : r[b]) ?? ''}';
    _name.text = s('name');
    _phone.text = s('phone');
    _email.text = s('email');
    _contact.text = s('contactname', 'contactName');
    _address.text = s('address');
    final cat = s('category');
    if (cat.isEmpty || _categories.contains(cat)) {
      _categoryPick = cat;
    } else {
      _typing = true;
      _categoryPick = _other;
      _category.text = cat;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _category, _contact, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty || _address.text.trim().isEmpty) {
      setState(() => _error = 'Name, phone, and address are required.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final farmId = widget.company.farmId;
    final input = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'category': _typing ? _category.text.trim() : _categoryPick,
      'contactName': _contact.text.trim(),
      'notes': '${_row?['notes'] ?? ''}',
      'farmId': farmId,
    };
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = widget.session.farmClient;
      final q = '?farmId=${Uri.encodeComponent(farmId)}';
      if (_editing) {
        await client.put('/api/Restaurant/setup/suppliers/$_id$q', body: {...input, 'isActive': true});
      } else {
        await client.post('/api/Restaurant/setup/suppliers$q', body: input);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
          content: Text(_editing ? 'Supplier updated successfully.' : 'Supplier created successfully.')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
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
            Text(_editing ? 'Edit supplier' : 'Add new supplier',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              _editing ? 'Update the supplier information below' : 'Enter the supplier information below',
              style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FormSection(title: 'Contact', color: SectionColor.rose, children: [
            AppField(label: 'Business / name', required: true,
                child: AppInput(controller: _name, hintText: 'e.g. Makola Fresh Supplies')),
            AppField(label: 'Phone', required: true,
                child: AppInput(controller: _phone, hintText: '+233 …', keyboardType: TextInputType.phone)),
            AppField(label: 'Email', child: AppInput(controller: _email, hintText: 'optional')),
            AppField(
              label: 'Category',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSelect<String>(
                    value: _categoryPick.isEmpty ? null : _categoryPick,
                    hintText: 'What they supply',
                    items: [
                      for (final c in _categories) AppSelectItem(value: c, label: c),
                      const AppSelectItem(value: _other, label: 'Other'),
                    ],
                    onChanged: (v) => setState(() {
                      _categoryPick = v ?? '';
                      _typing = v == _other;
                      if (_typing) _category.clear();
                    }),
                  ),
                  if (_typing) ...[
                    const SizedBox(height: 8),
                    AppInput(controller: _category, hintText: 'Type the category'),
                  ],
                ],
              ),
            ),
            AppField(label: 'Contact person', full: true,
                child: AppInput(controller: _contact, hintText: 'optional')),
          ]),
          const SizedBox(height: 12),
          FormSection(title: 'Address', color: SectionColor.green, columns: 1, children: [
            AppField(label: 'Full address', required: true, full: true,
                child: AppInput(controller: _address, hintText: 'Street, city, region')),
          ]),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.destructive,
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
                      : Text(_editing ? 'Save changes' : 'Create supplier'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:intl/intl.dart';

import '../core/config.dart';
import '../core/json.dart';
import '../core/theme.dart';
import 'resource_spec.dart';

final _money = NumberFormat.currency(symbol: AppConfig.currencySymbol, decimalDigits: 2);
final _date = DateFormat('d MMM yyyy');

String fmtDate(Map<String, dynamic> item, List<String> keys) {
  final d = pickDate(item, keys);
  return d == null ? '' : _date.format(d);
}

String fmtMoney(num v) => _money.format(v);

// Field names below come from the Farm API C# models
// (PoultryFarmAPI/Models/*.cs), not the stale Postman collection.

const _flockRef = FieldSpec('flockId', 'Flock', FieldType.reference,
    required: true, refEndpoint: 'Flock', refIdKey: 'flockId', refLabelKeys: ['name', 'flockName']);

final flocksSpec = ResourceSpec(
  title: 'Flocks',
  singular: 'Flock',
  endpoint: 'Flock',
  idKey: 'flockId',
  icon: Iconsax.pet,
  color: AppColors.primary,
  titleKeys: ['name', 'flockName'],
  subtitle: (i) =>
      '${pickString(i, ['breed'])} • ${pickNum(i, ['quantity'])} birds • ${fmtDate(i, ['startDate'])}',
  trailing: (i) => pickBool(i, ['active'], true) ? 'Active' : 'Inactive',
  fields: const [
    FieldSpec('name', 'Flock name', FieldType.text, required: true),
    FieldSpec('breed', 'Breed', FieldType.text, required: true),
    FieldSpec('quantity', 'Number of birds', FieldType.integer, required: true),
    FieldSpec('startDate', 'Start date', FieldType.date, required: true),
    FieldSpec('batchId', 'Batch', FieldType.reference,
        refEndpoint: 'MainFlockBatch', refIdKey: 'batchId', refLabelKeys: ['batchName']),
    FieldSpec('houseId', 'House', FieldType.reference,
        refEndpoint: 'House', refIdKey: 'houseId', refLabelKeys: ['houseName']),
    FieldSpec('active', 'Active', FieldType.toggle),
    FieldSpec('notes', 'Notes', FieldType.multiline),
  ],
);

final batchesSpec = ResourceSpec(
  title: 'Batches',
  singular: 'Batch',
  endpoint: 'MainFlockBatch',
  idKey: 'batchId',
  icon: Iconsax.box,
  color: AppColors.info,
  titleKeys: ['batchName'],
  subtitle: (i) =>
      '${pickString(i, ['breed'])} • ${pickNum(i, ['numberOfBirds'])} birds • ${fmtDate(i, ['startDate'])}',
  trailing: (i) => pickString(i, ['status']),
  fields: const [
    FieldSpec('batchName', 'Batch name', FieldType.text, required: true),
    FieldSpec('breed', 'Breed', FieldType.text, required: true),
    FieldSpec('numberOfBirds', 'Number of birds', FieldType.integer, required: true),
    FieldSpec('startDate', 'Start date', FieldType.date, required: true),
    FieldSpec('status', 'Status', FieldType.dropdown, options: ['active', 'inactive', 'sold']),
    FieldSpec('costPerChick', 'Cost per chick', FieldType.decimal),
    FieldSpec('supplierName', 'Supplier name', FieldType.text),
    FieldSpec('notes', 'Notes', FieldType.multiline),
  ],
);

final housesSpec = ResourceSpec(
  title: 'Houses',
  singular: 'House',
  endpoint: 'House',
  idKey: 'houseId',
  icon: Iconsax.home_2,
  color: AppColors.accent,
  titleKeys: ['houseName'],
  subtitle: (i) {
    final loc = pickString(i, ['location']);
    return 'Capacity ${pickNum(i, ['capacity'])}${loc.isEmpty ? '' : ' • $loc'}';
  },
  fields: const [
    FieldSpec('houseName', 'House name', FieldType.text, required: true),
    FieldSpec('capacity', 'Capacity (birds)', FieldType.integer),
    FieldSpec('location', 'Location', FieldType.text),
  ],
);

final eggProductionSpec = ResourceSpec(
  title: 'Egg Production',
  singular: 'Egg Record',
  endpoint: 'EggProduction',
  idKey: 'productionId',
  icon: Iconsax.cake,
  derive: _sumPicks,
  color: AppColors.accent,
  titleKeys: ['flockName'],
  subtitle: (i) =>
      '${fmtDate(i, ['productionDate'])} • broken ${pickNum(i, ['brokenEggs'])}',
  trailing: (i) => '${pickNum(i, ['totalProduction'])} eggs',
  fields: const [
    _flockRef,
    FieldSpec('productionDate', 'Date', FieldType.date, required: true),
    FieldSpec('production9AM', '9 AM pick', FieldType.integer),
    FieldSpec('production12PM', '12 PM pick', FieldType.integer),
    FieldSpec('production4PM', '4 PM pick', FieldType.integer),
    FieldSpec('production4thPick', '4th pick', FieldType.integer),
    FieldSpec('brokenEggs', 'Broken eggs', FieldType.integer),
    FieldSpec('eggGrade', 'Egg size', FieldType.dropdown,
        options: ['Small', 'Medium', 'Large', 'Extra Large']),
    FieldSpec('notes', 'Notes', FieldType.multiline),
  ],
);

final feedUsageSpec = ResourceSpec(
  title: 'Feed Usage',
  singular: 'Feed Record',
  endpoint: 'FeedUsage',
  idKey: 'feedUsageId',
  icon: Iconsax.milk,
  color: AppColors.success,
  titleKeys: ['feedType'],
  subtitle: (i) => fmtDate(i, ['usageDate']),
  trailing: (i) => '${pickNum(i, ['quantityKg'])} kg',
  fields: const [
    _flockRef,
    FieldSpec('feedType', 'Feed type', FieldType.text, required: true),
    FieldSpec('quantityKg', 'Quantity (kg)', FieldType.decimal, required: true),
    FieldSpec('usageDate', 'Date', FieldType.date, required: true),
  ],
);

final productionRecordsSpec = ResourceSpec(
  title: 'Daily Records',
  singular: 'Daily Record',
  endpoint: 'ProductionRecord',
  idKey: 'id',
  icon: Iconsax.clipboard_text,
  derive: _dailyRecordDerive,
  color: AppColors.info,
  titleKeys: ['date'],
  subtitle: (i) =>
      '${fmtDate(i, ['date'])} • ${pickNum(i, ['noOfBirds'])} birds • mortality ${pickNum(i, ['mortality'])}',
  trailing: (i) => '${pickNum(i, ['totalProduction'])} eggs',
  extraUpdateBody: (i) => {'updatedBy': ''},
  fields: const [
    FieldSpec('date', 'Date', FieldType.date, required: true),
    FieldSpec('noOfBirds', 'Number of birds', FieldType.integer, required: true),
    FieldSpec('mortality', 'Mortality', FieldType.integer),
    FieldSpec('feedKg', 'Feed used (kg)', FieldType.decimal),
    FieldSpec('medication', 'Medication', FieldType.text),
    FieldSpec('production9AM', '9 AM pick', FieldType.integer),
    FieldSpec('production12PM', '12 PM pick', FieldType.integer),
    FieldSpec('production4PM', '4 PM pick', FieldType.integer),
    FieldSpec('production4thPick', '4th pick', FieldType.integer),
  ],
);

final expensesSpec = ResourceSpec(
  title: 'Expenses',
  singular: 'Expense',
  endpoint: 'Expense',
  idKey: 'expenseId',
  icon: Iconsax.money_send,
  color: AppColors.danger,
  titleKeys: ['category'],
  subtitle: (i) {
    final d = pickString(i, ['description']);
    return '${fmtDate(i, ['expenseDate'])}${d.isEmpty ? '' : ' • $d'}';
  },
  trailing: (i) => fmtMoney(pickNum(i, ['amount'])),
  fields: const [
    FieldSpec('expenseDate', 'Date', FieldType.date, required: true),
    FieldSpec('category', 'Category', FieldType.dropdown, required: true, options: [
      'Feed', 'Medication', 'Labor', 'Utilities', 'Equipment', 'Transport', 'Maintenance', 'Other'
    ]),
    FieldSpec('amount', 'Amount', FieldType.decimal, required: true),
    FieldSpec('paymentMethod', 'Payment method', FieldType.dropdown,
        options: ['Cash', 'Bank Transfer', 'Mobile Money', 'Cheque', 'Credit']),
    FieldSpec('flockId', 'Flock (optional)', FieldType.reference,
        refEndpoint: 'Flock', refIdKey: 'flockId', refLabelKeys: ['name', 'flockName']),
    FieldSpec('supplier', 'Supplier', FieldType.text),
    FieldSpec('description', 'Description', FieldType.multiline),
  ],
);

final salesSpec = ResourceSpec(
  title: 'Sales',
  singular: 'Sale',
  endpoint: 'Sale',
  idKey: 'saleId',
  icon: Iconsax.shopping_cart,
  derive: _saleDerive,
  color: AppColors.success,
  titleKeys: ['product'],
  subtitle: (i) {
    final c = pickString(i, ['customerName']);
    return '${fmtDate(i, ['saleDate'])}${c.isEmpty ? '' : ' • $c'} • ${pickNum(i, ['quantity'])} @ ${fmtMoney(pickNum(i, ['unitPrice']))}';
  },
  trailing: (i) => fmtMoney(pickNum(i, ['totalAmount'])),
  fields: const [
    FieldSpec('saleDate', 'Date', FieldType.date, required: true),
    FieldSpec('product', 'Product', FieldType.dropdown, required: true,
        options: ['Eggs', 'Broilers', 'Layers', 'Manure', 'Other']),
    FieldSpec('quantity', 'Quantity', FieldType.decimal, required: true),
    FieldSpec('unitPrice', 'Unit price', FieldType.decimal, required: true),
    FieldSpec('customerId', 'Customer', FieldType.reference,
        refEndpoint: 'Customer', refIdKey: 'customerId', refLabelKeys: ['name', 'customerName']),
    FieldSpec('flockId', 'Flock (optional)', FieldType.reference,
        refEndpoint: 'Flock', refIdKey: 'flockId', refLabelKeys: ['name', 'flockName']),
    FieldSpec('paymentMethod', 'Payment method', FieldType.dropdown,
        options: ['Cash', 'Bank Transfer', 'Mobile Money', 'Cheque', 'Credit']),
    FieldSpec('paid', 'Paid in full', FieldType.toggle),
    FieldSpec('saleDescription', 'Notes', FieldType.multiline),
  ],
);

final customersSpec = ResourceSpec(
  title: 'Customers',
  singular: 'Customer',
  endpoint: 'Customer',
  idKey: 'customerId',
  icon: Iconsax.profile_2user,
  color: AppColors.info,
  titleKeys: ['name', 'customerName'],
  subtitle: (i) {
    final phone = pickString(i, ['contactPhone', 'contactNumber']);
    final city = pickString(i, ['city']);
    return [phone, city].where((s) => s.isNotEmpty).join(' • ');
  },
  fields: const [
    FieldSpec('name', 'Customer name', FieldType.text, required: true),
    FieldSpec('contactPhone', 'Phone', FieldType.text),
    FieldSpec('contactEmail', 'Email', FieldType.text),
    FieldSpec('address', 'Address', FieldType.text),
    FieldSpec('city', 'City', FieldType.text),
  ],
);

final inventorySpec = ResourceSpec(
  title: 'Inventory',
  singular: 'Item',
  endpoint: 'InventoryItem',
  idKey: 'itemId',
  icon: Iconsax.box_1,
  color: AppColors.primaryDark,
  titleKeys: ['itemName'],
  subtitle: (i) {
    final cat = pickString(i, ['category']);
    final reorder = pickNum(i, ['reorderLevel']);
    return '$cat${reorder > 0 ? ' • reorder at $reorder' : ''}';
  },
  trailing: (i) =>
      '${pickNum(i, ['quantityInStock'])} ${pickString(i, ['unitOfMeasure'])}',
  fields: const [
    FieldSpec('itemName', 'Item name', FieldType.text, required: true),
    FieldSpec('category', 'Category', FieldType.dropdown, required: true,
        options: ['Feed', 'Medication', 'Vaccines', 'Equipment', 'Packaging', 'Other']),
    FieldSpec('quantityInStock', 'Quantity in stock', FieldType.decimal, required: true),
    FieldSpec('unitOfMeasure', 'Unit', FieldType.dropdown, required: true,
        options: ['kg', 'bags', 'litres', 'pieces', 'boxes', 'doses']),
    FieldSpec('reorderLevel', 'Reorder level', FieldType.decimal),
    FieldSpec('cost', 'Unit cost', FieldType.decimal),
    FieldSpec('location', 'Storage location', FieldType.text),
    FieldSpec('isActive', 'Active', FieldType.toggle),
    FieldSpec('notes', 'Notes', FieldType.multiline),
  ],
);

num _n(Map<String, dynamic> b, String k) => pickNum(b, [k]);

Map<String, dynamic> _sumPicks(Map<String, dynamic> b) => {
      'totalProduction': _n(b, 'production9AM') +
          _n(b, 'production12PM') +
          _n(b, 'production4PM') +
          _n(b, 'production4thPick'),
    };

Map<String, dynamic> _dailyRecordDerive(Map<String, dynamic> b) => {
      ..._sumPicks(b),
      'noOfBirdsLeft': _n(b, 'noOfBirds') - _n(b, 'mortality'),
    };

Map<String, dynamic> _saleDerive(Map<String, dynamic> b) {
  final total = _n(b, 'quantity') * _n(b, 'unitPrice');
  final paid = b['paid'] == true;
  return {'totalAmount': total, 'amountPaid': paid ? total : 0};
}

/// Modules surfaced on the Production tab, Finance tab and More screen.
final productionSpecs = [eggProductionSpec, feedUsageSpec, productionRecordsSpec, flocksSpec];
final financeSpecs = [salesSpec, expensesSpec, customersSpec];
final farmSetupSpecs = [flocksSpec, batchesSpec, housesSpec, inventorySpec];

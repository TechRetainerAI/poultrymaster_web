// How Poultry records are worded in dropdowns and list cells, shared by
// the forms and the list specs.

/// A vehicle as the web's Routes and Drivers dropdowns word it:
/// "Truck 1 (Truck)", plus " — UnderMaintenance" when it is not Active.
String vehicleOptionLabel(Map row) {
  final status = '${row['status'] ?? 'Active'}';
  return '${row['vehicleName'] ?? ''} (${row['vehicleType'] ?? ''})'
      '${status != 'Active' ? ' — $status' : ''}';
}

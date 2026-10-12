// How the Water web pages word a record in a picker or a table cell.

/// The Edit driver dialog's vehicle option in `app/water-drivers/page.tsx`:
/// `Truck 1 (Truck)`, with ` — Inactive` when it is not Active.
String waterVehicleOptionLabel(Map row) {
  final status = '${row['status'] ?? 'Active'}';
  return '${row['vehicleName'] ?? ''} (${row['vehicleType'] ?? ''})'
      '${status != 'Active' ? ' — $status' : ''}';
}

/// The drivers list's `vehicleLabel()`: `Truck 1 (Truck)`, no status.
String waterVehicleCellLabel(Map row) =>
    '${row['vehicleName'] ?? ''} (${row['vehicleType'] ?? ''})';

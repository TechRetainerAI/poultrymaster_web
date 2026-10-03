import '../../api/api_client.dart';
import '../../models/company.dart';
import '../../state/session.dart';

/// The web's `usePermissions().can(key)` for one key (`hooks/use-permissions.ts`
/// with `lib/iam/resolve.ts`):
/// - While the API does not enforce IAM (`/Iam/status` enforced = false), an
///   admin holds every key.
/// - Otherwise only the keys granted by `/Iam/effective-permissions` count.
///
/// Both calls failing is the web's "endpoint unavailable" case: no IAM grants,
/// not enforced, so an admin still qualifies and nobody else does.
Future<bool> canDo(Session session, Company company, String key) async {
  final c = session.farmClient;
  Object? status;
  Object? effective;
  try {
    status = await c.get('/api/Iam/status');
  } on ApiException {
    status = null;
  }
  try {
    effective = await c.get('/api/Iam/effective-permissions', query: {'farmId': company.farmId});
  } on ApiException {
    effective = null;
  }
  final enforced = status is Map && status['enforced'] == true;
  if (!enforced && company.isAdmin) return true;
  final grants = effective is Map ? effective['grants'] : null;
  if (grants is! List) return false;
  return grants.any((g) => g is Map && g['permissionKey'] == key);
}

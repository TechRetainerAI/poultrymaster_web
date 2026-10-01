/// Which record fields belong to the plumbing rather than to the business.
///
/// The API returns a lot that exists for the system, not for the person
/// running the farm: row GUIDs, the caller's IP, the browser's user-agent,
/// the raw request JSON, audit columns. A changes report was printing all of
/// it, which made a client app read like a debug console.
///
/// One rule, used everywhere a record reaches the screen or a file — the
/// detail view, the list cards, a derived form and the CSV/email export — so
/// a field hidden in one place cannot reappear in another.
library;

final _guid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

final _auditPrefix = RegExp(r'^(created|updated|modified|deleted)by');

const _exactKeys = {
  'ipaddress', 'useragent', 'data', 'payload', 'requestjson', 'responsejson',
  'rowversion', 'concurrencystamp', 'isdeleted', 'farmid', 'userid',
  'companyid', 'tenantid', 'correlationid', 'traceid', 'sessionid',
  'passwordhash', 'securitystamp', 'refreshtoken', 'accesstoken',
};

/// True when [key]/[value] is infrastructure the client should not see.
bool isPlumbingField(String key, Object? value) {
  final k = key.toLowerCase();
  if (_exactKeys.contains(k)) return true;
  if (_auditPrefix.hasMatch(k)) return true;

  // A bare GUID is an identifier nobody reads out loud. A numeric id is
  // different — those are the short reference numbers people do quote.
  if (value is String && _guid.hasMatch(value)) return true;

  // A JSON document stuffed into a string column.
  if (value is String &&
      value.length > 120 &&
      (value.trimLeft().startsWith('{') || value.trimLeft().startsWith('['))) {
    return true;
  }
  return false;
}

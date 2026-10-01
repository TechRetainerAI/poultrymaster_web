/// The five company types the platform gates on (`Farms.Type`).
///
/// The web renders a completely different navigation set per type, and the API
/// returns 409 Conflict if you call a module's endpoint for the wrong type — so
/// this enum drives routing throughout the app.
enum CompanyType { poultry, water, generic, restaurant, hotel, unknown }

CompanyType companyTypeFrom(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'poultry':
      return CompanyType.poultry;
    case 'water':
      return CompanyType.water;
    case 'generic':
      return CompanyType.generic;
    case 'restaurant':
      return CompanyType.restaurant;
    case 'hotel':
      return CompanyType.hotel;
    default:
      return CompanyType.unknown;
  }
}

extension CompanyTypeLabel on CompanyType {
  String get label {
    switch (this) {
      case CompanyType.poultry:
        return 'Poultry';
      case CompanyType.water:
        return 'Water';
      case CompanyType.generic:
        return 'Generic';
      case CompanyType.restaurant:
        return 'Restaurant';
      case CompanyType.hotel:
        return 'Hotel';
      case CompanyType.unknown:
        return 'Unknown';
    }
  }

  String get wire => label;
}

class Company {
  Company({
    required this.farmId,
    required this.name,
    required this.type,
    this.role,
    this.email,
    this.phoneNumber,
    this.ownerUserId,
  });

  final String farmId;
  final String name;
  final CompanyType type;
  final String? role;
  final String? email;
  final String? phoneNumber;

  /// Which Business Office owns this company. Used to scope the list when the
  /// user signs in with an organisation code.
  final String? ownerUserId;

  bool get isAdmin => (role ?? '').toLowerCase() == 'admin';

  /// Reads camelCase — [ApiClient.normalise] has already lowered the first
  /// letter, because `/Companies/mine` answers in PascalCase.
  factory Company.fromJson(Map<String, dynamic> json) => Company(
        farmId: '${json['farmId'] ?? json['id'] ?? ''}',
        name: '${json['name'] ?? json['farmName'] ?? 'Unnamed company'}',
        type: companyTypeFrom(json['type'] as String?),
        role: json['role'] as String?,
        email: json['email'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        ownerUserId: json['ownerUserId']?.toString(),
      );
}

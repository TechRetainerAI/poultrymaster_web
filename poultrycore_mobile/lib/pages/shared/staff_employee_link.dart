// Staff <-> Employee link (migration 362), as lib/api/staff-user-link.ts,
// hooks/use-staff-employee-link.tsx and components/employees/link-badges.tsx.
// An Employee is a login (Login API); a Staff member is a payroll record in
// the company type's staff table. A linked pair is one person, shown on both
// the Employees and the Staff page. Creating either side still uses that
// side's own form; these calls only read and set the link.

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../form_screen.dart';
import '../hotel/hotel_staff_screen.dart';
import '../module_registry.dart' show formForSpec;
import '../page_extras.dart';
import '../registry.dart';
import '../restaurant/restaurant_staff_form_screen.dart';
import '../water/water_staff_form_screen.dart';
import 'employee_form_screen.dart';

/// What a new employee or staff form starts from.
class EmployeePrefill {
  const EmployeePrefill({required this.firstName, required this.lastName, this.phoneNumber = '', this.email = ''});
  final String firstName, lastName, phoneNumber, email;
}

/// first_last, lower-case letters and digits only.
String suggestUserName(EmployeePrefill p) => [p.firstName, p.lastName]
    .map((x) => x.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''))
    .where((x) => x.isNotEmpty)
    .join('_');

/// staffPagePath: the Staff page of each company type. The app has Poultry's,
/// Water's, Restaurant's and Hotel's; Generic is not in the app.
String? staffPagePath(CompanyType t) => switch (t) {
      CompanyType.poultry => '/poultry-staff',
      CompanyType.water => '/water-staff',
      CompanyType.restaurant => '/restaurant-staff',
      CompanyType.hotel => '/hotel-staff',
      _ => null,
    };

/// Each Staff page's spec key and id field.
const _staffIdKey = {'poultry-staff': 'poultryStaffId', 'water-staff': 'waterStaffId'};

/// GET /api/StaffUserLink: (staffId, userId) pairs for the company.
Future<List<({int staffId, String userId})>> getStaffUserLinks(Session s, Company c) async {
  final res = await s.farmClient.get('/api/StaffUserLink', query: {'farmId': c.farmId});
  return [
    if (res is List)
      for (final l in res)
        if (l is Map && int.tryParse('${l['staffId']}') != null && '${l['userId'] ?? ''}'.isNotEmpty)
          (staffId: int.parse('${l['staffId']}'), userId: '${l['userId']}'),
  ];
}

/// PUT /api/StaffUserLink: link a staff row to an employee login.
Future<void> setStaffUserLink(Session s, Company c, int staffId, String userId) =>
    s.farmClient.put('/api/StaffUserLink', body: {'farmId': c.farmId, 'staffId': staffId, 'userId': userId});

Widget _badge(String text, String tip, Color bg, Color fg, Color border) => Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ),
    );

/// EmployeeBadge: on a staff row that has a login.
Widget employeeBadge() =>
    _badge('Employee', 'Also an employee: has a login', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), const Color(0xFFBFDBFE));

/// StaffBadge: on an employee who is also on the Staff page.
Widget staffBadge() =>
    _badge('Staff', 'Also on the Staff page (payroll)', const Color(0xFFEEF2FF), const Color(0xFF4338CA), const Color(0xFFC7D2FE));

const _linkedUser = '_employeeUserId';
const _isStaff = '_isStaff';
const _staffPage = '_staffPage';

/// Marks the Staff rows that have a login.
RowEnrich _markEmployees(String idKey) => (s, c, rows) async {
      final links = {for (final l in await getStaffUserLinks(s, c)) l.staffId: l.userId};
      for (final r in rows) {
        final user = links[int.tryParse('${r[idKey]}')];
        if (user != null) r[_linkedUser] = user;
      }
    };

final Map<String, RowEnrich> staffLinkRowEnrich = {
  for (final MapEntry(:key, :value) in _staffIdKey.entries) key: _markEmployees(value),
  'admin-company-employees': (s, c, rows) async {
    final page = staffPagePath(c.type);
    if (page == null) return;
    for (final r in rows) {
      r[_staffPage] = page;
    }
    final users = {for (final l in await getStaffUserLinks(s, c)) l.userId};
    for (final r in rows) {
      if (users.contains('${r['id']}')) r[_isStaff] = true;
    }
  },
};

final Map<String, RowBadge> staffLinkRowBadges = {
  for (final key in _staffIdKey.keys) key: (r) => r[_linkedUser] != null ? employeeBadge() : null,
  'admin-company-employees': (r) => r[_isStaff] == true ? staffBadge() : null,
};

EmployeePrefill _prefillOf(Map r) => EmployeePrefill(
      firstName: '${r['firstName'] ?? ''}',
      lastName: '${r['lastName'] ?? ''}',
      // Restaurant staff rows call it `phone`.
      phoneNumber: '${r['phoneNumber'] ?? r['phone'] ?? ''}',
      email: '${r['email'] ?? ''}',
    );

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Make employee from a Staff page with a screen of its own (Restaurant): Add
/// Employee prefilled from [row], the new login linked back by [idKey].
Widget makeEmployeeScreen(Session session, Company company, Map<String, dynamic> row, String idKey) =>
    _MakeEmployee(session, company, row, idKey);

/// Staff "Make employee": Add Employee prefilled; the new login is linked back.
class _MakeEmployee extends StatelessWidget {
  const _MakeEmployee(this.session, this.company, this.row, this.idKey);
  final Session session;
  final Company company;
  final Map<String, dynamic> row;
  final String idKey;

  @override
  Widget build(BuildContext context) => EmployeeFormScreen(
        session: session,
        company: company,
        prefill: _prefillOf(row),
        onCreated: (userId) async {
          final staffId = int.tryParse('${row[idKey]}');
          if (staffId == null || userId == null) return;
          try {
            await setStaffUserLink(session, company, staffId, userId);
          } catch (_) {
            if (context.mounted) _toast(context, 'Employee created, but not linked to this staff member');
          }
        },
      );
}

/// Employees "Add as staff": New staff prefilled from the employee; the saved
/// row is linked to them.
class _AddAsStaff extends StatelessWidget {
  const _AddAsStaff(this.session, this.company, this.row);
  final Session session;
  final Company company;
  final Map<String, dynamic> row;

  Future<void> _link(BuildContext context, int? staffId) async {
    final userId = '${row['id'] ?? ''}';
    if (staffId == null || userId.isEmpty) return;
    try {
      await setStaffUserLink(session, company, staffId, userId);
      if (context.mounted) _toast(context, 'Linked to employee. They now show on both Employees and Staff.');
    } catch (_) {
      if (context.mounted) _toast(context, 'Staff added, but not linked to the employee');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefillOf(row);
    if (row[_staffPage] == '/restaurant-staff') {
      return RestaurantStaffFormScreen(
        session: session,
        company: company,
        prefill: p,
        onCreated: (created) => _link(context, created is Map ? int.tryParse('${created['staffId']}') : null),
      );
    }
    if (row[_staffPage] == '/hotel-staff') {
      return HotelStaffScreen(
        session: session,
        company: company,
        prefill: p,
        onCreated: (created) => _link(context, created is Map ? int.tryParse('${created['hotelStaffId']}') : null),
      );
    }
    if (row[_staffPage] == '/water-staff') {
      return WaterStaffFormScreen(
        session: session,
        company: company,
        prefill: p,
        onCreated: (created) => _link(context, created is Map ? int.tryParse('${created['waterStaffId']}') : null),
      );
    }
    return FormScreen(
      def: formForSpec('poultry-staff')!,
      title: 'Add Staff',
      company: company,
      session: session,
      spec: PageRegistry.of('poultry-staff'),
      initial: {'firstName': p.firstName, 'lastName': p.lastName, 'phoneNumber': p.phoneNumber, 'email': p.email},
      onCreated: (created) => _link(context, created is Map ? int.tryParse('${created['poultryStaffId']}') : null),
    );
  }
}

final Map<String, List<RecordExtra>> staffLinkRecordExtras = {
  for (final MapEntry(:key, :value) in _staffIdKey.entries)
    key: [
      RecordExtra('Make employee', Icons.key_outlined, (s, c, row) => _MakeEmployee(s, c, row, value),
          when: (row) => row[_linkedUser] == null),
    ],
  'admin-company-employees': [
    RecordExtra('Add as staff', Icons.person_add_alt, (s, c, row) => _AddAsStaff(s, c, row),
        when: (row) => row[_staffPage] != null && row[_isStaff] != true),
  ],
};

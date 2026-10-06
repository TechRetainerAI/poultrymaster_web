import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import 'companies_screen.dart';
import 'employee_form_screen.dart';

/// Pages the web shares between company types. Users & Permissions is one
/// route (/employees) for every type; what differs per type (the staff
/// permission switches) is decided inside the screen from the company.
const Map<String, CustomFormBuilder> sharedCustomForms = {
  'admin-company-employees': _employee,
};

Widget _employee(Session s, Company c, Map<String, dynamic>? e) =>
    EmployeeFormScreen(session: s, company: c, existing: e);

/// Shared routes that open a screen of their own.
const Map<String, PageScreenBuilder> sharedPageScreens = {
  '/companies': _companies,
};

Widget _companies(Session s, Company c) => CompaniesScreen(session: s, company: c);

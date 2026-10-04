import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../form_spec.dart';
import 'restaurant_staff_form_screen.dart';
import 'restaurant_supplier_form_screen.dart';

/// Restaurant's forms, copied from the Restaurant web pages — never from
/// Poultry's or Water's.
const Map<String, FormDef> restaurantForms = {
  // app/restaurant-crm/page.tsx — Customers tab, "Add Customer". Segment
  // defaults to New, as the web's `custForm.segment || "New"`.
  'restaurant-crm-customers': FormDef(
    route: '/restaurant-crm',
    specKey: 'restaurant-crm-customers',
    sections: [
      FormSectionDef(title: 'Customer', color: 'rose', columns: 2,
          description: 'Track guest preferences and visit history', fields: [
        FormFieldDef(label: 'Name', kind: FormFieldKind.text, required: true, name: 'name'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'email'),
        FormFieldDef(label: 'Segment', kind: FormFieldKind.select, name: 'segment', initial: 'New'),
        FormFieldDef(label: 'Birthday', kind: FormFieldKind.date, name: 'dateOfBirth'),
        FormFieldDef(label: 'Anniversary', kind: FormFieldKind.date, name: 'anniversary'),
      ]),
      FormSectionDef(title: 'Preferences', color: 'rose', columns: 1, fields: [
        FormFieldDef(label: 'Dietary Preferences', kind: FormFieldKind.text, placeholder: 'e.g. Vegetarian, No spicy', name: 'dietaryPreferences'),
        FormFieldDef(label: 'Allergies', kind: FormFieldKind.text, placeholder: 'e.g. Nuts, Shellfish, Dairy', name: 'allergies'),
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),
};

/// Restaurant pages with a screen of their own.
const Map<String, CustomFormBuilder> restaurantCustomForms = {
  'restaurant-staff': _staff,
  'restaurant-setup-suppliers': _supplier,
};

Widget _staff(Session s, Company c, Map<String, dynamic>? e) =>
    RestaurantStaffFormScreen(session: s, company: c, existing: e);

Widget _supplier(Session s, Company c, Map<String, dynamic>? e) =>
    RestaurantSupplierFormScreen(session: s, company: c, existing: e);

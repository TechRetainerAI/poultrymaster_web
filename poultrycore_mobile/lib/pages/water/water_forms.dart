import 'package:flutter/widgets.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../custom_form.dart';
import '../form_spec.dart';
import 'water_staff_form_screen.dart';

/// Water's forms, copied from the Water web pages' own dialogs — never from
/// Poultry's. Same sections, colours, labels, placeholders, required marks,
/// defaults (each page's EMPTY) and the body each `lib/api/water.ts` call
/// sends, including the record id on update.
const Map<String, FormDef> waterForms = {
  // app/water-customers/page.tsx
  'water-customers': FormDef(
    route: '/water-customers',
    specKey: 'water-customers',
    idKey: 'waterCustomerId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Name', kind: FormFieldKind.text, required: true, full: true, name: 'name'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'contactPhone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'contactEmail'),
      ]),
      FormSectionDef(title: 'Address', color: 'green', columns: 2, fields: [
        FormFieldDef(label: 'Address', kind: FormFieldKind.text, full: true, name: 'address'),
        FormFieldDef(label: 'City', kind: FormFieldKind.text, name: 'city'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-suppliers/page.tsx — Active is a yes/no select over a boolean.
  'water-suppliers': FormDef(
    route: '/water-suppliers',
    specKey: 'water-suppliers',
    idKey: 'waterSupplierId',
    createdByKey: 'createdBy',
    updatedByKey: 'updatedBy',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Supplier name', kind: FormFieldKind.text, required: true, full: true, name: 'supplierName'),
        FormFieldDef(label: 'Supplier type', kind: FormFieldKind.select, name: 'supplierType', initial: 'Other'),
        FormFieldDef(label: 'Active', kind: FormFieldKind.select, name: 'isActive', yesNo: true, initial: 'yes'),
      ]),
      FormSectionDef(title: 'Contact', color: 'green', columns: 2, fields: [
        FormFieldDef(label: 'Contact person', kind: FormFieldKind.text, name: 'contactPerson'),
        FormFieldDef(label: 'Phone', kind: FormFieldKind.text, name: 'phone'),
        FormFieldDef(label: 'Email', kind: FormFieldKind.text, name: 'email'),
        FormFieldDef(label: 'Address', kind: FormFieldKind.text, full: true, name: 'address'),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-machines/page.tsx — Setup → Plant.
  'water-machines': FormDef(
    route: '/water-machines',
    specKey: 'water-machines',
    idKey: 'waterMachineId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Machine name', kind: FormFieldKind.text, required: true, full: true, name: 'machineName'),
        FormFieldDef(label: 'Machine number', kind: FormFieldKind.text, name: 'machineNumber'),
        FormFieldDef(label: 'Type', kind: FormFieldKind.text, placeholder: 'e.g. Sachet filling, Bottling', name: 'machineType'),
        FormFieldDef(label: 'Manufacturer', kind: FormFieldKind.text, name: 'manufacturer'),
      ]),
      FormSectionDef(title: 'Details', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Capacity / hour (bags)', kind: FormFieldKind.number, name: 'capacityPerHour'),
        FormFieldDef(label: 'Purchase date', kind: FormFieldKind.date, name: 'purchaseDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Maintenance', color: 'amber', columns: 2, fields: [
        FormFieldDef(label: 'Maintenance frequency (days)', kind: FormFieldKind.number, full: true, name: 'maintenanceFrequencyDays'),
        FormFieldDef(label: 'Last maintenance', kind: FormFieldKind.date, name: 'lastMaintenanceDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Next maintenance', kind: FormFieldKind.date, name: 'nextMaintenanceDate', dateBound: DateBound.future),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),

  // app/water-boreholes/page.tsx — Setup → Plant.
  'water-boreholes': FormDef(
    route: '/water-boreholes',
    specKey: 'water-boreholes',
    idKey: 'waterBoreholeId',
    sections: [
      FormSectionDef(title: 'Identity', color: 'indigo', columns: 2, fields: [
        FormFieldDef(label: 'Borehole name', kind: FormFieldKind.text, required: true, full: true, name: 'boreholeName'),
        FormFieldDef(label: 'Location', kind: FormFieldKind.text, full: true, name: 'location'),
      ]),
      FormSectionDef(title: 'Pump & Tank', color: 'blue', columns: 2, fields: [
        FormFieldDef(label: 'Pump type', kind: FormFieldKind.text, name: 'pumpType'),
        FormFieldDef(label: 'Pump capacity', kind: FormFieldKind.text, placeholder: 'e.g. 5000 L/hr', name: 'pumpCapacity'),
        FormFieldDef(label: 'Tank capacity', kind: FormFieldKind.text, full: true, placeholder: 'e.g. 10000 L', name: 'tankCapacity'),
      ]),
      FormSectionDef(title: 'Treatment', color: 'sky', columns: 2, fields: [
        FormFieldDef(label: 'Treatment method', kind: FormFieldKind.text, name: 'waterTreatmentMethod'),
        FormFieldDef(label: 'Filtration', kind: FormFieldKind.text, name: 'filtrationSystem'),
        FormFieldDef(label: 'UV sterilization', kind: FormFieldKind.bool, full: true, name: 'uvSterilizationAvailable', placeholder: 'Available', initial: 'false'),
        FormFieldDef(label: 'Status', kind: FormFieldKind.select, full: true, name: 'status', initial: 'Active'),
      ]),
      FormSectionDef(title: 'Maintenance', color: 'amber', columns: 2, fields: [
        FormFieldDef(label: 'Maint. frequency (days)', kind: FormFieldKind.number, full: true, name: 'maintenanceFrequencyDays'),
        FormFieldDef(label: 'Last maintenance', kind: FormFieldKind.date, name: 'lastMaintenanceDate', dateBound: DateBound.past),
        FormFieldDef(label: 'Next maintenance', kind: FormFieldKind.date, name: 'nextMaintenanceDate', dateBound: DateBound.future),
        FormFieldDef(label: 'Water quality test due date', kind: FormFieldKind.date, full: true, name: 'waterQualityTestDueDate', dateBound: DateBound.future),
      ]),
      FormSectionDef(title: 'Notes', color: 'slate', columns: 1, fields: [
        FormFieldDef(label: 'Notes', kind: FormFieldKind.text, name: 'notes'),
      ]),
    ],
  ),
};

/// Water pages with a screen of their own.
const Map<String, CustomFormBuilder> waterCustomForms = {
  'water-staff': _staff,
};

Widget _staff(Session s, Company c, Map<String, dynamic>? e) =>
    WaterStaffFormScreen(session: s, company: c, existing: e);

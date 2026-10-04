import '../design/ui/form_section.dart';

/// The input kinds the web uses inside a `<FormField>`.
///
/// `calc` is the web's `<CalcField>`: a figure the form works out and shows
/// read-only (total feed cost, net sellable). It is never typed into and
/// never sent — the server recomputes it — so it renders disabled.
enum FormFieldKind { text, select, number, money, date, textarea, bool, calc }

/// A date input's `max={today}` (past) or `min={today}` (future) on the web.
enum DateBound { past, future }

class FormFieldDef {
  const FormFieldDef({
    required this.label,
    required this.kind,
    this.required = false,
    this.full = false,
    this.placeholder,
    this.hint,
    this.name,
    this.initial,
    this.decimal = false,
    this.yesNo = false,
    this.dateBound,
    this.optionLabel,
    this.emptyHint,
  });

  final String label;
  final FormFieldKind kind;
  final bool required;

  /// Spans every column of its section, as `full` does on the web.
  final bool full;

  final String? placeholder;
  final String? hint;

  /// The form-state key the web binds to, kept so a submit payload can be
  /// assembled with the same field names the API expects.
  final String? name;

  /// The value a new record starts with, as the web's empty form sets it
  /// (a select's option value, 'true'/'false' for a switch).
  final String? initial;

  /// A number field that takes decimals (the web's `step="0.01"`).
  final bool decimal;

  /// A select whose options are 'yes' / 'no' but whose value is a boolean,
  /// as the web's `value={x ? "yes" : "no"}` pattern.
  final bool yesNo;

  final DateBound? dateBound;

  /// How each option of a looked-up select is worded, when the web words it
  /// from several fields. A top-level function, so the def stays const.
  final String Function(Map row)? optionLabel;

  /// What an empty option list says, e.g. "No vehicles. Add one on the
  /// Vehicles page first."
  final String? emptyHint;
}

/// A repeatable row of fields, as the web's line editors work: Feed and
/// Medication each let you add as many lines as you need and remove any of
/// them, and the section's totals are summed from those lines.
///
/// The payload carries them as a list under [name], one map per row keyed by
/// each field's own name — the shape the web posts.
class FormLineDef {
  const FormLineDef({
    required this.name,
    required this.addLabel,
    required this.fields,
  });

  /// Payload key holding the list of rows, e.g. `feedLines`.
  final String name;

  /// What the add button says on the web, e.g. "Add line".
  final String addLabel;

  /// The columns of one row.
  final List<FormFieldDef> fields;
}

class FormSectionDef {
  const FormSectionDef({
    required this.title,
    required this.color,
    required this.columns,
    required this.fields,
    this.description,
    this.lines,
  });

  final String title;
  final String color;
  final int columns;
  final List<FormFieldDef> fields;

  /// The web shows a sentence under each section heading saying what it is
  /// for. Carried across so the phone explains the form the same way.
  final String? description;

  /// Repeatable rows shown above this section's own fields, where the web
  /// has a line editor.
  final FormLineDef? lines;

  SectionColor get sectionColor => switch (color) {
        'blue' => SectionColor.blue,
        'green' => SectionColor.green,
        'sky' => SectionColor.sky,
        'emerald' => SectionColor.emerald,
        'amber' => SectionColor.amber,
        'rose' => SectionColor.rose,
        'purple' => SectionColor.purple,
        'slate' => SectionColor.slate,
        _ => SectionColor.indigo,
      };
}

/// One page's form, as the web defines it.
class FormDef {
  const FormDef({
    required this.route,
    required this.sections,
    this.specKey,
    this.idKey,
    this.carry = const [],
    this.createdByKey,
    this.updatedByKey,
  });

  final String route;
  final List<FormSectionDef> sections;

  /// The list page this form belongs to, where one was matched.
  final String? specKey;

  /// The record's own id in the body: 0 on create and the id on update, as
  /// the web sends it. Most PUT endpoints here reject a body without it.
  final String? idKey;

  /// Fields copied from the record being edited and sent back unchanged,
  /// such as createdDate, which the server would otherwise overwrite.
  final List<String> carry;

  /// Body keys stamped with the signed-in user's id on create / update, as
  /// the web adds `createdBy: currentUserId()`.
  final String? createdByKey;
  final String? updatedByKey;

  int get fieldCount => sections.fold(
      0, (n, s) => n + s.fields.length + (s.lines?.fields.length ?? 0));
}

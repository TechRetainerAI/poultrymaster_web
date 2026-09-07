import 'package:flutter/material.dart';

enum FieldType { text, multiline, integer, decimal, date, dropdown, reference, toggle }

/// One form field on a resource. [refEndpoint]/[refIdKey]/[refLabelKeys]
/// power dropdowns populated from another Farm API resource (e.g. pick a
/// flock on an egg-production record).
class FieldSpec {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String>? options;
  final String? refEndpoint;
  final String? refIdKey;
  final List<String>? refLabelKeys;
  final String? hint;

  const FieldSpec(
    this.key,
    this.label,
    this.type, {
    this.required = false,
    this.options,
    this.refEndpoint,
    this.refIdKey,
    this.refLabelKeys,
    this.hint,
  });
}

/// A full CRUD module: endpoint, identity, look-and-feel, list rendering and
/// form fields. All module screens are generated from these.
class ResourceSpec {
  final String title;
  final String singular;
  final String endpoint;
  final String idKey;
  final IconData icon;
  final Color color;
  final List<String> titleKeys;
  final String Function(Map<String, dynamic> item)? subtitle;
  final String Function(Map<String, dynamic> item)? trailing;
  final List<FieldSpec> fields;

  /// Extra keys copied into the update body from the loaded item (audit
  /// fields like createdBy that the SP expects back).
  final Map<String, dynamic> Function(Map<String, dynamic> item)? extraUpdateBody;

  /// Computes derived fields the API expects on the wire (e.g. totalProduction
  /// from the pick counts, totalAmount from quantity × unit price).
  final Map<String, dynamic> Function(Map<String, dynamic> body)? derive;

  const ResourceSpec({
    required this.title,
    required this.singular,
    required this.endpoint,
    required this.idKey,
    required this.icon,
    required this.color,
    required this.titleKeys,
    required this.fields,
    this.subtitle,
    this.trailing,
    this.extraUpdateBody,
    this.derive,
  });
}

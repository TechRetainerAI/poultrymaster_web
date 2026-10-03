import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'form_section.dart' show Slate;

/// Text input — the web `Input`: h-9, px-3, 1px border, rounded-md, 14px.
///
/// Height and padding come from [InputDecorationTheme]; this widget adds only
/// the behaviour each variant needs.
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.controller,
    this.hintText,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      onChanged: onChanged,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      autofocus: autofocus,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Textarea — the web uses `Textarea` with a 3-row default.
class AppTextarea extends StatelessWidget {
  const AppTextarea({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.validator,
    this.rows = 3,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final int rows;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AppInput(
        controller: controller,
        hintText: hintText,
        onChanged: onChanged,
        validator: validator,
        enabled: enabled,
        keyboardType: TextInputType.multiline,
        minLines: rows,
        maxLines: rows + 4,
      );
}

/// Money input.
///
/// The platform's currency is the Ghana cedi and every amount on the web is
/// rendered with the ₵ prefix, so the symbol sits inside the field rather than
/// in the label. Input is restricted to digits with at most two decimals —
/// these values post straight to accounting endpoints.
class AppMoneyInput extends StatelessWidget {
  const AppMoneyInput({
    super.key,
    this.controller,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.symbol = '₵',
    this.hintText = '0.00',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool enabled;
  final String symbol;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: controller,
      onChanged: onChanged,
      validator: validator,
      enabled: enabled,
      hintText: hintText,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 6),
        child: Text(symbol,
            style: TextStyle(fontSize: 14, color: context.tokens.mutedForeground)),
      ),
    );
  }
}

/// Whole-number input (quantities, bird counts, crates).
class AppNumberInput extends StatelessWidget {
  const AppNumberInput({
    super.key,
    this.controller,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.allowDecimal = false,
    this.hintText = '0',
    this.suffix,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool allowDecimal;
  final String hintText;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return AppInput(
      controller: controller,
      onChanged: onChanged,
      validator: validator,
      enabled: enabled,
      hintText: hintText,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        allowDecimal
            ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      suffixIcon: suffix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 12, left: 6),
              child: Text(suffix!,
                  style:
                      TextStyle(fontSize: 13, color: context.tokens.mutedForeground)),
            ),
    );
  }
}

/// Select — the web `Select`. Styled to match [AppInput] exactly so a form of
/// mixed controls reads as one row of identical boxes.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText = 'Select…',
    this.enabled = true,
    this.validator,
  });

  final T? value;
  final List<AppSelectItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hintText;
  final bool enabled;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DropdownButtonFormField<T>(
      // initialValue is read once, when the field is first built. Keying on
      // the value (and on how many options there are) rebuilds the field
      // whenever either changes, so a value set in code — a prefill, an
      // option list that arrives late, one choice switching another — shows.
      key: ValueKey('$value|${items.length}'),
      initialValue: value,
      isExpanded: true,
      validator: validator,
      onChanged: enabled ? onChanged : null,
      hint: Text(hintText,
          style: TextStyle(fontSize: 14, color: tokens.mutedForeground)),
      icon: Icon(Icons.keyboard_arrow_down, size: 18, color: tokens.mutedForeground),
      style: TextStyle(fontSize: 14, color: tokens.cardForeground),
      dropdownColor: tokens.card,
      borderRadius: BorderRadius.circular(Dim.radiusMd),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            child: Text(item.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
          ),
      ],
    );
  }
}

class AppSelectItem<T> {
  const AppSelectItem({required this.value, required this.label});
  final T value;
  final String label;
}

/// Date field — opens the platform picker and renders as a normal input.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Pick a date',
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String hintText;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  static String format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();

    return InkWell(
      borderRadius: BorderRadius.circular(Dim.radiusMd),
      onTap: !enabled
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: firstDate ?? DateTime(now.year - 5),
                lastDate: lastDate ?? DateTime(now.year + 5),
              );
              if (picked != null) onChanged(picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIcon: Icon(Icons.calendar_today_outlined,
              size: 16, color: tokens.mutedForeground),
        ),
        child: Text(
          value == null ? hintText : format(value!),
          style: TextStyle(
            fontSize: 14,
            color: value == null ? tokens.mutedForeground : tokens.cardForeground,
          ),
        ),
      ),
    );
  }
}

/// Checkbox with a label to its right, as the web renders it.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(Dim.radiusSm),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 22,
              width: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, height: 1.2)),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!,
                        style:
                            TextStyle(fontSize: 12, color: tokens.mutedForeground)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switch row — label on the left, control on the right.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              if (description != null)
                Text(description!,
                    style: TextStyle(fontSize: 12, color: tokens.mutedForeground)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Search field used above list screens.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'Search…',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) => AppInput(
        controller: controller,
        onChanged: onChanged,
        hintText: hintText,
        prefixIcon: Icon(Icons.search, size: 18, color: Slate.s400),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// The one text input. Label above the box (never floating inside it, so a
/// filled field still shows what it is), 48 px tall, helper and error text
/// below that wrap rather than clip. An [error] turns the border red and
/// shows the message; pass null once the person has fixed it.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.helper,
    this.error,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.autofocus = false,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.suffix,
    this.prefixText,
    this.required = false,
    this.textCapitalization = TextCapitalization.none,
    this.onTap,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.prefixIcon,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? helper;
  final String? error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool obscure;
  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final Widget? suffix;
  final String? prefixText;

  /// Adds the asterisk to the label. Validation is the caller's.
  final bool required;
  final TextCapitalization textCapitalization;
  final VoidCallback? onTap;
  final bool autocorrect;
  final bool enableSuggestions;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          onTap: onTap,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          autofocus: autofocus,
          obscureText: obscure,
          enabled: enabled,
          readOnly: readOnly,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            errorText: error,
            prefixText: prefixText,
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20, color: p.textMuted),
            suffixIcon: suffix,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            isDense: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
    );
  }
}

/// The small uppercase label above a field or a picker. Shared so the two
/// line up.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Text.rich(
      TextSpan(
        text: text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: p.textSecondary),
        children: [
          if (required) TextSpan(text: ' *', style: TextStyle(color: p.danger)),
        ],
      ),
    );
  }
}

/// A search box: magnifier on the left, clear button when there is text, no
/// label above (the hint says what it searches). Same height as every other
/// field.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
        decoration: InputDecoration(
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          prefixIcon: Icon(Icons.search, size: 20, color: p.textMuted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close, size: 20, color: p.textSecondary),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
        ),
      ),
    );
  }
}

/// A date shown as a field: tap opens the platform date picker. Displays the
/// date the way the app does everywhere ("19 Sep 2026") and hands back the
/// picked [DateTime].
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.error,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool required;
  final String? error;
  final DateTime? firstDate;
  final DateTime? lastDate;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String format(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, required: required),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: firstDate ?? DateTime(now.year - 5),
              lastDate: lastDate ?? DateTime(now.year + 1, 12, 31),
            );
            if (picked != null) onChanged(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.never,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18, color: p.textMuted),
              errorText: error,
            ),
            child: Text(
              value == null ? 'Pick a date' : format(value!),
              style: TextStyle(
                fontSize: 16,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                color: value == null ? p.textMuted : p.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';

/// A field that picks several values at once.
///
/// Only one attribute needs it — Descriptor, the adjectives a design carries.
/// Every other question the catalogue asks has exactly one answer, which is
/// why the app's [PickerField] is a wheel; a saree can be Soft *and* Pure, and
/// a wheel would make whoever filed it choose half the truth.
class MultiPickerField extends StatelessWidget {
  const MultiPickerField({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<CoreOption> options;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    final chosen = [
      for (final o in options)
        if (values.contains(o.id)) o.label,
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: options.isEmpty
          ? null
          : () async {
              final picked = await showModalBottomSheet<List<String>>(
                context: context,
                isScrollControlled: true,
                backgroundColor: p.surface2,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => _MultiSheet(
                  title: label,
                  options: options,
                  chosen: values,
                ),
              );

              if (picked != null) onChanged(picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Text(
          chosen.isEmpty ? 'None' : chosen.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: chosen.isEmpty ? p.textMuted : p.text,
            fontWeight: chosen.isEmpty ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MultiSheet extends StatefulWidget {
  const _MultiSheet({
    required this.title,
    required this.options,
    required this.chosen,
  });

  final String title;
  final List<CoreOption> options;
  final List<String> chosen;

  @override
  State<_MultiSheet> createState() => _MultiSheetState();
}

class _MultiSheetState extends State<_MultiSheet> {
  late final Set<String> _picked = {...widget.chosen};

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: p.textSecondary)),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _picked.toList()),
                  child: Text(
                    'Done',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: p.primary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.options.length,
              itemBuilder: (context, i) {
                final o = widget.options[i];
                final on = _picked.contains(o.id);

                return CheckboxListTile(
                  value: on,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(o.label),
                  onChanged: (_) => setState(() {
                    if (on) {
                      _picked.remove(o.id);
                    } else {
                      _picked.add(o.id);
                    }
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

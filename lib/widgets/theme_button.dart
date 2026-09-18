import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// A palette icon that lives in every screen's app bar. Tapping it opens a
/// bottom sheet of theme swatches so the look can be changed from anywhere —
/// the full list also lives in Settings › Appearance.
class ThemeButton extends StatelessWidget {
  const ThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Theme',
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => showThemeSheet(context),
    );
  }
}

/// Shows the theme picker as a modal bottom sheet. `isScrollControlled` lets
/// it grow past the default sheet height — needed once `SlkThemes.all` holds
/// more entries than fit on a short phone in one screen.
Future<void> showThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.p.surface1,
    builder: (_) => const _ThemeSheet(),
  );
}

class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeControllerProvider);
    return SafeArea(
      top: false,
      // Bounded, not unbounded: the title stays put and only the swatch
      // list scrolls once SlkThemes.all outgrows the sheet's own height —
      // an unbounded Column here is what overflowed off the bottom of the
      // screen the moment a 6th theme was added.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Theme',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.p.text)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final t in SlkThemes.all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SheetTile(
                        theme: t,
                        selected: t.id == current.id,
                        onTap: () {
                          ref.read(themeControllerProvider.notifier).select(t);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.theme, required this.selected, required this.onTap});
  final SlkTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? context.p.primary : context.p.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(child: Container(color: theme.palette.appBar)),
                    Row(
                      children: [
                        Expanded(child: Container(height: 13, color: theme.palette.primary)),
                        Expanded(child: Container(height: 13, color: theme.palette.accent)),
                        Expanded(child: Container(height: 13, color: theme.palette.surface1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(theme.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(theme.description, style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: context.p.primary),
            ],
          ),
        ),
      ),
    );
  }
}

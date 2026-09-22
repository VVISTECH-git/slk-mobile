import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One row in a list: a leading thing (icon, swatch, photo), a title, an
/// optional subtitle, a trailing thing (badge, count, chevron). 56 px minimum
/// so every row is a target, 16 px side padding to match the page.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.titleMono = false,
    this.dense = false,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Show a chevron on the right (implies the row opens something).
  final bool chevron;

  /// Codes read better fixed-width.
  final bool titleMono;
  final bool dense;

  /// Tinted with the brand colour: a ticked row in a multi-select list.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: dense ? 48 : 56),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                      fontFamily: titleMono ? 'monospace' : null,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(fontSize: 13, color: p.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            if (chevron) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, color: p.textMuted)],
          ],
        ),
      ),
    );
    final tinted = selected ? ColoredBox(color: p.primary.withValues(alpha: 0.08), child: row) : row;
    if (onTap == null) return tinted;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: tinted));
  }
}

/// A list inside a card: rows separated by hairlines, the card's own border
/// around them. Pass [AppListRow]s (or anything) as [children].
class AppListGroup extends StatelessWidget {
  const AppListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A small square swatch or photo thumbnail for a row's leading slot.
class RowThumb extends StatelessWidget {
  const RowThumb({super.key, this.color, this.image, this.size = 44, this.icon});

  final Color? color;
  final ImageProvider? image;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? p.surface3,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
        image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      child: icon == null ? null : Icon(icon, size: size * 0.5, color: p.textSecondary),
    );
  }
}

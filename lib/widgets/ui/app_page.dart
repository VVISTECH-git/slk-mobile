import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_button.dart';

/// Every screen's frame: a flat header with a title, an optional one-line
/// subtitle and up to two actions; the body; and, when a screen has a main
/// action, a [BottomActionBar] pinned above the system bar so the primary
/// button is always in thumb reach and never scrolls away.
///
/// Header colour comes from the palette's `appBar`, which is the brand
/// colour in the default theme — the one place the screen is allowed to be
/// loud.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.padded = true,
    this.scrollable = false,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottomBar;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// 16 px around the body (off for full-bleed lists and scanners).
  final bool padded;

  /// Wrap the body in a scroll view that dismisses the keyboard on drag.
  final bool scrollable;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget content = padded ? Padding(padding: const EdgeInsets.all(16), child: body) : body;
    if (scrollable) {
      content = SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: content,
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        titleSpacing: leading == null && !automaticallyImplyLeading ? 20 : null,
        title: subtitle == null
            ? Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: p.onAppBar.withValues(alpha: 0.8)),
                  ),
                ],
              ),
        actions: [...actions, const SizedBox(width: 6)],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(top: false, bottom: bottomBar == null, child: content),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// The action strip at the bottom of a screen: one primary button, optionally
/// one secondary beside it, and an optional note above them ("All four records
/// go in as one bill."). Sits on the surface colour with a top border, and
/// pads itself past the system navigation bar.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.note,
  });

  final AppButton primary;
  final AppButton? secondary;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.surface2,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note != null) ...[
                  Text(note!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                  const SizedBox(height: 10),
                ],
                if (secondary == null)
                  primary
                else
                  Row(
                    children: [
                      Expanded(child: secondary!),
                      const SizedBox(width: 10),
                      Expanded(child: primary),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading between groups on a screen — "Scanned", "Recent" — with an
/// optional trailing count or action. 12 px above, 8 below, so groups read
/// as groups.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.top = 12});

  final String title;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text))),
          if (trailing != null) DefaultTextStyle(style: TextStyle(fontSize: 13, color: p.textSecondary), child: trailing!),
        ],
      ),
    );
  }
}

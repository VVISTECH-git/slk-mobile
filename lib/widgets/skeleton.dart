import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A subtle shimmering placeholder box used to build skeleton screens while
/// data loads — calmer and more "finished" than a spinner.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 14, this.width = double.infinity, this.radius = 8});
  final double height;
  final double width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(context.p.border, context.p.surface3, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A list of card-shaped skeletons — the default loading state for list screens.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6});
  final int rows;

  @override
  Widget build(BuildContext context) {
    // shrinkWrap: a skeleton list sits inside whatever is loading — a
    // Column in a bottom sheet as often as a full page — and must size to
    // its rows rather than demand a height nobody can give it.
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.p.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Skeleton(height: 16, width: 180),
            SizedBox(height: 10),
            Skeleton(height: 12, width: 120),
            SizedBox(height: 14),
            Row(children: [
              Expanded(child: Skeleton(height: 12)),
              SizedBox(width: 40),
              Skeleton(height: 12, width: 60),
            ]),
          ],
        ),
      ),
    );
  }
}

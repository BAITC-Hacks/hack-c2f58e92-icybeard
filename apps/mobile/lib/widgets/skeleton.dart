import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Скелетон загрузки: мягкий пульс прозрачности без сторонних пакетов; уважает prefers-reduced-motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 14, this.width, this.radius = AppRadius.sm});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppDurations.pulse)..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Opacity(
        opacity: reduceMotion ? 0.5 : 0.35 + 0.35 * _controller.value,
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(color: colors.faint, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      ),
    );
  }
}

/// Три плитки KPI в ряд, как на экранах ожидания и маршрута.
class KpiRowSkeleton extends StatelessWidget {
  const KpiRowSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Skeleton(height: 72, radius: AppRadius.md)),
          ],
        ],
      );
}

class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 4, this.itemHeight = 56});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Skeleton(height: itemHeight, radius: AppRadius.md),
          ],
        ],
      );
}

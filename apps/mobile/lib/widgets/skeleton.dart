import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Скелетон загрузки: soft-блок с мягким пульсом прозрачности без сторонних пакетов; уважает prefers-reduced-motion.
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
        opacity: reduceMotion ? 0.7 : 0.5 + 0.5 * _controller.value,
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(color: colors.neutralSoft, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      ),
    );
  }
}

/// Плейсхолдер карточки: блок radius 18 нужной высоты.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) => Skeleton(height: height, radius: AppRadius.card);
}

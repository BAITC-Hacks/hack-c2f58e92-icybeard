import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Цвета знака Darumen из darumen-assets/README.md: Navy, Sky, Mist. Знак живёт в своей палитре
/// независимо от темы интерфейса (Clinical Minimal остаётся акцентом экранов).
abstract final class DarumenBrand {
  static const navy = Color(0xFF0B2A4A);
  static const sky = Color(0xFF29B6D8);
  static const mist = Color(0xFFF1F8FB);
}

/// Знак «D»: блок со скруглёнными левыми углами, дуга и сектор — геометрия из svg/mark.svg (viewBox 20 20 63 60).
/// Три прогресса 0…1 рисуют части по очереди: блок вырастает, дуга прорисовывается, сектор раскрывается.
class DarumenMarkPainter extends CustomPainter {
  const DarumenMarkPainter({
    required this.block,
    required this.arc,
    required this.fill,
    this.onDark = false,
  });

  final double block;
  final double arc;
  final double fill;
  final bool onDark;

  static const _viewW = 63.0;
  static const _viewH = 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _viewW, size.height / _viewH);
    canvas.save();
    canvas.translate(
      (size.width - _viewW * scale) / 2,
      (size.height - _viewH * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-20, -20);

    if (block > 0) {
      final rect = RRect.fromLTRBAndCorners(
        22,
        22,
        49,
        78,
        topLeft: const Radius.circular(8),
        bottomLeft: const Radius.circular(8),
      );
      final t = Curves.easeOutBack.transform(block.clamp(0, 1));
      canvas.save();
      canvas.translate(35.5, 50);
      canvas.scale(0.6 + 0.4 * t);
      canvas.translate(-35.5, -50);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = (onDark ? DarumenBrand.mist : DarumenBrand.navy).withValues(
            alpha: block.clamp(0, 1),
          ),
      );
      canvas.restore();
    }

    if (arc > 0) {
      final sweep = math.pi / 2 * Curves.easeInOut.transform(arc.clamp(0, 1));
      final paint = Paint()
        ..color = DarumenBrand.sky
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(53, 50), radius: 25),
        -math.pi / 2,
        sweep,
        false,
        paint,
      );
    }

    if (fill > 0) {
      final t = Curves.easeOutCubic.transform(fill.clamp(0, 1));
      final path = Path()
        ..moveTo(53, 50)
        ..lineTo(81, 50)
        ..arcTo(
          Rect.fromCircle(center: const Offset(53, 50), radius: 28),
          0,
          math.pi / 2,
          false,
        )
        ..close();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(48, 50, 40 * t, 32));
      canvas.drawPath(path, Paint()..color = DarumenBrand.sky);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DarumenMarkPainter old) =>
      old.block != block ||
      old.arc != arc ||
      old.fill != fill ||
      old.onDark != onDark;
}

/// Статичный знак для шапок и экрана входа.
class DarumenMark extends StatelessWidget {
  const DarumenMark({super.key, this.size = 40, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 60 / 63),
    painter: DarumenMarkPainter(block: 1, arc: 1, fill: 1, onDark: onDark),
  );
}

/// Заставка при открытии: знак собирается на фоне Navy (блок → дуга → сектор → слово), затем растворяется
/// в приложение. Общее время ~1.6 с; при отключённых анимациях в системе показывается один кадр и сразу уходит.
class DarumenIntro extends StatefulWidget {
  const DarumenIntro({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.onDone,
  });

  final Widget child;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<DarumenIntro> createState() => _DarumenIntroState();
}

class _DarumenIntroState extends State<DarumenIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
        widget.onDone?.call();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stack остаётся всегда: ребёнок не переезжает по дереву после заставки, иначе приложение пересоздаётся.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              // Тайминг: блок 0–0.3, дуга 0.25–0.6, сектор 0.55–0.8, слово 0.7–0.9, растворение 0.85–1.
              double seg(double from, double to) =>
                  ((t - from) / (to - from)).clamp(0, 1);
              final fade = 1 - seg(0.85, 1);
              return IgnorePointer(
                child: Opacity(
                  opacity: fade,
                  child: Material(
                    color: DarumenBrand.navy,
                    child: Center(
                      // Пока слова нет, знак стоит по центру; со словом ряд уезжает влево на половину его ширины.
                      child: Transform.translate(
                        offset: Offset(96 * (1 - seg(0.65, 0.9)), 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomPaint(
                              size: const Size(84, 80),
                              painter: DarumenMarkPainter(
                                block: seg(0, 0.3),
                                arc: seg(0.25, 0.6),
                                fill: seg(0.55, 0.8),
                                onDark: true,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Opacity(
                              opacity: seg(0.7, 0.9),
                              child: Transform.translate(
                                offset: Offset(12 * (1 - seg(0.7, 0.9)), 0),
                                child: Text(
                                  'darumen',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: DarumenBrand.mist,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -1.4,
                                        height: 1,
                                        decoration: TextDecoration.none,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

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

/// Знак в шапке главной: сюда прилетает знак из заставки. Пока заставка идёт, якорь невидим (его место занимает
/// летящий знак), после — рисует статичный знак. Один якорь на дерево (GlobalKey).
final GlobalKey homeMarkKey = GlobalKey(debugLabel: 'homeMark');

class HomeMarkAnchor extends StatelessWidget {
  const HomeMarkAnchor({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: ValueListenableBuilder<bool>(
      valueListenable: DarumenIntro.done,
      builder: (_, done, _) => Opacity(
        opacity: done ? 1 : 0,
        child: DarumenMark(key: homeMarkKey, size: size),
      ),
    ),
  );
}

/// Заставка при открытии: знак собирается по центру Navy-фона (блок → дуга → сектор), под ним появляется слово,
/// затем фон и слово растворяются, а знак улетает в шапку главной (в [HomeMarkAnchor]) — плавный переход в приложение.
/// Если якоря на экране нет (вход, другой маршрут), знак просто растворяется. При отключённых анимациях — сразу приложение.
class DarumenIntro extends StatefulWidget {
  const DarumenIntro({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 4000),
    this.onDone,
  });

  final Widget child;
  final Duration duration;
  final VoidCallback? onDone;

  /// true после заставки: якорь в шапке показывает знак.
  static final ValueNotifier<bool> done = ValueNotifier<bool>(false);

  @override
  State<DarumenIntro> createState() => _DarumenIntroState();
}

class _DarumenIntroState extends State<DarumenIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _finished = false;

  static const double _centerSize = 126;

  @override
  void initState() {
    super.initState();
    DarumenIntro.done.value = false;
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        DarumenIntro.done.value = true;
        setState(() => _finished = true);
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

  /// Прямоугольник якоря в координатах экрана; null, если якоря нет в дереве.
  Rect? _anchorRect() {
    final box = homeMarkKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    // Stack остаётся всегда: ребёнок не переезжает по дереву после заставки, иначе приложение пересоздаётся.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_finished)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              // Тайминг: блок 0–0.2, дуга 0.15–0.4, сектор 0.35–0.55, слово 0.5–0.65, пауза, полёт в шапку 0.78–1.
              double seg(double from, double to) =>
                  ((t - from) / (to - from)).clamp(0, 1);
              final fly = Curves.easeInOutCubic.transform(seg(0.78, 1));
              final textStyle = Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(
                    color: DarumenBrand.mist,
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.4,
                    height: 1,
                    decoration: TextDecoration.none,
                  );
              return IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screen = Offset.zero & constraints.biggest;
                    final centerRect = Rect.fromCenter(
                      center: screen.center.translate(0, -34),
                      width: _centerSize,
                      height: _centerSize * 60 / 63,
                    );
                    final target = fly > 0 ? _anchorRect() : null;
                    final markRect = target == null
                        ? centerRect
                        : Rect.lerp(centerRect, target, fly)!;
                    final markOpacity = target == null ? 1 - fly : 1.0;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: 1 - fly,
                            child: const Material(color: DarumenBrand.navy),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: centerRect.bottom + 28,
                          child: Opacity(
                            opacity: seg(0.5, 0.65) * (1 - fly),
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - seg(0.5, 0.65))),
                              child: Text(
                                'darumen',
                                textAlign: TextAlign.center,
                                style: textStyle,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: markRect,
                          child: Opacity(
                            opacity: markOpacity,
                            child: CustomPaint(
                              painter: DarumenMarkPainter(
                                block: seg(0, 0.2),
                                arc: seg(0.15, 0.4),
                                fill: seg(0.35, 0.55),
                                onDark: fly < 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }
}

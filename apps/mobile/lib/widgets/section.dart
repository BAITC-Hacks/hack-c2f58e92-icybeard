import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'circle_button.dart';

/// Каркас экрана: без AppBar — топбар 56 `padding 0 16 12` с круглой кнопкой назад 40 на surface-muted (если есть
/// куда вернуться) или знаком слева, заголовок 24/800 (до двух строк, перенос только между словами — см. [PageTitle])
/// и круглыми кнопками справа; контент — ListView `padding 4 16`,
/// gap 12 между детьми; нижняя зона `padding 12 16 24` для primary-кнопки. Pull-to-refresh при наличии onRefresh.
/// `hero` — голубой градиент `--bg-hero-gradient` вместо серого фона (ТОЛЬКО стартовый вход и главная гражданина).
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    required this.children,
    this.onRefresh,
    this.bottom,
    this.showBack,
    this.gap = AppSpacing.md,
    this.hero = false,
  });

  final String title;

  /// Виджет слева от заголовка, когда кнопки «назад» нет (знак Darumen на корневых экранах).
  final Widget? leading;
  final List<Widget>? actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Primary-кнопка в нижней зоне.
  final Widget? bottom;

  /// null — кнопка назад показывается, если роутер или навигатор может вернуться.
  final bool? showBack;

  /// Расстояние между детьми контента.
  final double gap;

  /// Голубой градиент фона — только стартовый вход и главная гражданина (m-welcome-new, m-home-new).
  final bool hero;

  static bool _canPop(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    return router?.canPop() ?? Navigator.of(context).canPop();
  }

  static void _pop(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.pop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final back = showBack ?? _canPop(context);
    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xl),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
      itemBuilder: (_, i) => children[i],
    );
    final page = Scaffold(
      backgroundColor: hero ? ColorTokens.transparent : null,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            Padding(
              // топбар 56: кнопка 40 + по 8 сверху и снизу (доски m-*)
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
              child: Row(
                children: [
                  if (back) CircleIconButton(icon: Icons.arrow_back, label: s.back, onTap: () => _pop(context)) else ?leading,
                  if (back || leading != null) const SizedBox(width: AppSpacing.md),
                  Expanded(child: PageTitle(title)),
                  if (actions != null)
                    for (final action in actions!) ...[const SizedBox(width: AppSpacing.md), action],
                ],
              ),
            ),
            Expanded(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null ? null : BottomAction(child: bottom!),
    );
    if (!hero) {
      return page;
    }
    return Container(decoration: BoxDecoration(gradient: heroGradient(context)), child: page);
  }
}

/// Заголовок экрана 24/800 до двух строк с многоточием. Переносится только между словами: если самое длинное слово
/// не помещается в строку (одно слово казахского заголовка при крупном шрифте рядом с кнопками), шрифт уменьшается
/// ровно настолько, чтобы слово встало целиком; помещается — размер прежний.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(Theme.of(context).textTheme.headlineMedium);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Text(
        title,
        style: _fitLongestWord(title, style, maxWidth: constraints.maxWidth, textScaler: scaler, textDirection: direction),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// [style], уменьшенный так, чтобы самое длинное слово [text] уместилось в [maxWidth] одной строкой; если помещается
/// (или ширина не ограничена) — [style] как есть.
TextStyle _fitLongestWord(String text, TextStyle style, {required double maxWidth, required TextScaler textScaler, required TextDirection textDirection}) {
  final words = text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  final size = style.fontSize;
  if (words.isEmpty || size == null || !maxWidth.isFinite) {
    return style;
  }
  double widest(TextStyle candidate) => words.map((word) {
        final painter = TextPainter(text: TextSpan(text: word, style: candidate), textDirection: textDirection, textScaler: textScaler, maxLines: 1)
          ..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }).reduce(math.max);
  var fitted = style;
  // ширина текста почти пропорциональна кеглю; второй и третий шаг добирают округления метрик шрифта
  for (var step = 0; step < 3; step++) {
    final width = widest(fitted);
    if (width <= maxWidth) {
      break;
    }
    fitted = fitted.copyWith(fontSize: fitted.fontSize! * maxWidth / width);
  }
  return fitted;
}

/// Голубой градиент `--bg-hero-gradient` (150deg, остановки 0/30/55/100 %) из токенов текущей темы.
LinearGradient heroGradient(BuildContext context) => LinearGradient(
      begin: const Alignment(-0.5, -1),
      end: const Alignment(0.5, 1),
      colors: AppPalette.of(context).heroGradient,
      stops: ColorTokens.heroGradientStops,
    );

/// Нижняя зона экрана `padding 12 16 24` с учётом системного отступа — под primary-кнопку.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
          child: child,
        ),
      );
}

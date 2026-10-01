import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'circle_button.dart';

/// Каркас экрана: без AppBar — топбар 56 `padding 0 16 12` с круглой кнопкой назад 40 на surface-muted (если есть
/// куда вернуться) или знаком слева, заголовок 24/800 и круглыми кнопками справа; контент — ListView `padding 4 16`,
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
    final theme = Theme.of(context);
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
                  Expanded(
                    child: Text(title, style: theme.textTheme.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
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

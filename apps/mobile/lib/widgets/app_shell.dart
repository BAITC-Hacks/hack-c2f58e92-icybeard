import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'count_badge.dart';
import 'notice_card.dart';

/// Вкладка плавающей нижней навигации: подпись, иконка, корневой путь и индекс ветки StatefulShellRoute (вкладки
/// без разрешения скрываются, поэтому позиция в пилюле и номер ветки могут не совпадать). [badge] — счётчик на
/// иконке ([CountBadge], 0 — нет), [badgeLabel] — что он значит для чтения с экрана («новых: 3»); вкладка тогда
/// озвучивается как «Уведомления, новых: 3».
class ShellDestination {
  const ShellDestination({required this.label, required this.icon, required this.path, required this.branch, this.badge = 0, this.badgeLabel});

  final String label;
  final IconData icon;
  final String path;
  final int branch;
  final int badge;
  final String? badgeLabel;

  /// Подпись вкладки для чтения с экрана: с непустым счётчиком — вместе с его смыслом.
  String semanticsLabel(S s) => badge > 0 && badgeLabel != null ? s.tabWithBadge(label, badgeLabel!) : label;
}

/// Плавающая пилюля навигации поверх StatefulShellRoute: `margin 12 16 16`, высота 64, белая, тень `--shadow-pop`;
/// три-четыре пункта — иконка 22 (со счётчиком [CountBadge], если он есть), подпись 11/700, полоска 16×3 accent под
/// активным (активный пункт — accent-strong, остальные text-muted — доска m-home-new). Показывается только на
/// корневых экранах веток: на вложенных («Мой путь», «Сколько ждут», маршрут пациента) вместо неё нижняя кнопка
/// экрана. Повторное нажатие на активную вкладку возвращает её в корень. Над экранами обоих shell'ов — баннер
/// «Почтовый сервер недоступен» ([EmailOutageBanner]), пока почта не работает и пользователь его не закрыл.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, required this.destinations});

  final StatefulNavigationShell shell;
  final List<ShellDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    final atRoot = destinations.any((d) => d.path == location);
    final banner = EmailOutageBanner.visible(context);
    return Scaffold(
      // контент уходит под плавающую пилюлю (гранит градиента главной дотягивается до низа экрана),
      // нижний отступ содержимому возвращает MediaQuery через SafeArea экранов
      extendBody: true,
      // форма дерева не меняется при показе баннера — ветки shell'а не пересоздаются; под баннером верхний
      // системный отступ уже занят, экран его не повторяет
      // Builder: нижний отступ под пилюлю (extendBody) есть только в MediaQuery тела Scaffold; с контекстом самого
      // AppShell экраны его не получали, и последние строки списка прятались под пилюлей
      body: Builder(
        builder: (context) => Column(
          children: [
            const EmailOutageBanner(),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: banner, child: shell)),
          ],
        ),
      ),
      bottomNavigationBar: atRoot
          ? FloatingNav(
              selectedIndex: destinations.indexWhere((d) => d.branch == shell.currentIndex),
              destinations: destinations,
              onSelected: (index) {
                final branch = destinations[index].branch;
                shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
              },
            )
          : null,
    );
  }
}

class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.selectedIndex, required this.destinations, required this.onSelected});

  final int selectedIndex;
  final List<ShellDestination> destinations;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.page),
        child: Container(
          height: AppSizes.nav,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: colors.popShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              for (final (i, d) in destinations.indexed)
                Expanded(child: _NavItem(destination: d, selected: i == selectedIndex, onTap: () => onSelected(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final color = selected ? colors.accentHover : colors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.semanticsLabel(S.at(context)),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CountBadge(count: destination.badge, child: Icon(destination.icon, size: 22, color: color)),
            const SizedBox(height: 3),
            Text(
              destination.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: AppType.navLabelSize, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Container(
              width: AppSizes.navPipWidth,
              height: AppSizes.bar,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: selected ? colors.accent : ColorTokens.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

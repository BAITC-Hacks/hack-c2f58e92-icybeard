import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Вкладка плавающей нижней навигации: подпись, иконка и корневой путь ветки.
class ShellDestination {
  const ShellDestination({required this.label, required this.icon, required this.path});

  final String label;
  final IconData icon;
  final String path;
}

/// Плавающая пилюля навигации поверх StatefulShellRoute: `margin 12 20 20`, высота 64, белая, тень; три пункта —
/// иконка 22, подпись 12/500, точка 6 px coral под активным. Показывается только на корневых экранах веток: на
/// вложенных («Мой путь», «Сколько ждут», маршрут пациента) вместо неё нижняя кнопка экрана. Повторное нажатие
/// на активную вкладку возвращает её в корень.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, required this.destinations});

  final StatefulNavigationShell shell;
  final List<ShellDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    final atRoot = destinations.any((d) => d.path == location);
    return Scaffold(
      body: shell,
      bottomNavigationBar: atRoot
          ? FloatingNav(
              selectedIndex: shell.currentIndex,
              destinations: destinations,
              onSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
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
            boxShadow: [BoxShadow(color: colors.navShadow, offset: const Offset(0, -4), blurRadius: 16)],
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
    final color = selected ? colors.ink : colors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(destination.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? colors.accent : AppColors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}

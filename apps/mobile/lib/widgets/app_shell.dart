import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Вкладка нижней навигации shell'а.
class ShellDestination {
  const ShellDestination({required this.label, required this.icon, required this.selectedIcon});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Нижняя навигация поверх StatefulShellRoute: три вкладки у гражданина, четыре у врача. Повторное нажатие на
/// активную вкладку возвращает её в корень (initialLocation) — как в системных приложениях.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, required this.destinations});

  final StatefulNavigationShell shell;
  final List<ShellDestination> destinations;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label, tooltip: d.label),
          ],
        ),
      );
}

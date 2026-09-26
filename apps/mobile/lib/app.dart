import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'router/app_router.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';
import 'widgets/darumen_mark.dart';

/// Корень приложения: роутер создаётся один раз от сессии, тема светлая/тёмная по системе, локаль — из сессии
/// (меняется без пересоздания роутера, системные виджеты локализуются делегатами).
class DarumenApp extends StatefulWidget {
  const DarumenApp({super.key});

  @override
  State<DarumenApp> createState() => _DarumenAppState();
}

class _DarumenAppState extends State<DarumenApp> {
  late final GoRouter _router = buildRouter(context.read<Session>());

  @override
  Widget build(BuildContext context) {
    final locale = context.select<Session, String>((s) => s.locale);
    return MaterialApp.router(
      title: 'Darumen',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      // Заставка со знаком поверх первого экрана: один раз при холодном старте, дальше роутер живёт как обычно.
      // INTRO_MS — длительность заставки в мс (для отладки: --dart-define=INTRO_MS=6000).
      builder: (_, child) => DarumenIntro(duration: const Duration(milliseconds: int.fromEnvironment('INTRO_MS', defaultValue: 1400)), child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
    );
  }
}

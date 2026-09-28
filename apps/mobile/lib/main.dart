import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/service_status_notifier.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Первый кадр — сразу: заставка DarumenIntro закрывает экран на 4 с, а сессия (prefs и secure storage) читается
  // параллельно; когда она загрузится, роутер сам перейдёт на домашний экран роли ещё под заставкой.
  final session = Session();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        // статус почты, push, SMS и eGov — сразу при запуске (без ожидания входа), дальше при возвращении в
        // приложение и каждые 5 минут на переднем плане
        ChangeNotifierProvider(create: (_) => ServiceStatusNotifier(fetch: session.api.serviceStatus)..start(), lazy: false),
      ],
      child: const DarumenApp(),
    ),
  );
  unawaited(session.load());
}

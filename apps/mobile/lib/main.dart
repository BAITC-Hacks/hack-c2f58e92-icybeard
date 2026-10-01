import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_scope.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Первый кадр — сразу: заставка DarumenIntro закрывает экран на 4 с, а сессия (prefs и secure storage) читается
  // параллельно; когда она загрузится, роутер сам перейдёт на домашний экран роли ещё под заставкой.
  final session = Session();
  // Держатели состояния над всем приложением: статус сервисов (опрос сразу при запуске, без ожидания входа),
  // маршрут гражданина и колокольчики, которые включаются сами по роли вошедшего пользователя.
  runApp(AppScope(session: session, child: const DarumenApp()));
  unawaited(session.load());
}

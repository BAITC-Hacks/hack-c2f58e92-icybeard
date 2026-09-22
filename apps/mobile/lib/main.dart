import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // сессия загружается до первого кадра: роутер сразу знает роль и не мигает экраном входа
  final session = Session();
  await session.load();
  runApp(ChangeNotifierProvider.value(value: session, child: const DarumenApp()));
}

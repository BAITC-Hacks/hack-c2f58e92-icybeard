import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController baseUrl = TextEditingController(text: context.read<Session>().baseUrl);
  late final TextEditingController region = TextEditingController(text: context.read<Session>().region);
  late final TextEditingController keycloakUrl = TextEditingController(text: context.read<Session>().keycloakUrl);
  final TextEditingController username = TextEditingController(text: 'doctor1');
  final TextEditingController password = TextEditingController();
  bool loggingIn = false;
  String? loginError;

  Future<void> _login() async {
    final session = context.read<Session>();
    setState(() {
      loggingIn = true;
      loginError = null;
    });
    try {
      await session.update(keycloakUrl: keycloakUrl.text.trim());
      await session.login(username.text.trim(), password.text);
    } catch (e) {
      setState(() => loginError = '$e');
    } finally {
      if (mounted) setState(() => loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: baseUrl, decoration: const InputDecoration(labelText: 'Адрес API', helperText: 'эмулятор Android: http://10.0.2.2:8000')),
          const SizedBox(height: 8),
          TextField(controller: region, decoration: const InputDecoration(labelText: 'Регион (КАТО, две цифры)')),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ru', label: Text('RU')), ButtonSegment(value: 'kk', label: Text('KK'))],
            selected: {session.locale},
            onSelectionChanged: (s) => session.update(locale: s.first),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await session.update(baseUrl: baseUrl.text.trim(), region: region.text.trim());
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Сохранить'),
          ),
          const Divider(height: 32),
          Text('Вход через Keycloak', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (session.isKeycloak) ...[
            Text('Вы вошли как ${session.actor} (роль: ${session.role}, регион: ${session.region})'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => session.logout(), child: const Text('Выйти (вернуться в демо-режим)')),
          ] else ...[
            TextField(controller: keycloakUrl, decoration: const InputDecoration(labelText: 'Адрес Keycloak', helperText: 'эмулятор Android: http://10.0.2.2:8080')),
            const SizedBox(height: 8),
            TextField(controller: username, decoration: const InputDecoration(labelText: 'Пользователь', helperText: 'демо: doctor1 / citizen1, пароль darumen')),
            const SizedBox(height: 8),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: loggingIn ? null : _login,
              child: loggingIn ? const Text('Вход…') : const Text('Войти'),
            ),
            if (loginError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(loginError!, style: const TextStyle(color: Colors.red, fontSize: 12))),
            const SizedBox(height: 8),
            const Text('Без входа работает демо-режим с заголовками X-Actor/X-Role. После входа роль и регион берутся из токена (клиент darumen-mobile).',
                style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

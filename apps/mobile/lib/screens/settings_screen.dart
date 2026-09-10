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
          const SizedBox(height: 16),
          const Text('Вход: демо-режим с заголовками X-Actor/X-Role. Вход через Keycloak (клиент darumen-mobile, PKCE) подключается в сборке для стенда.', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

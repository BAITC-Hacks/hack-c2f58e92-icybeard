import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final cards = <(String, String, String, IconData)>[
      ('/wait', 'Сколько ждать', 'Ожидание плановой госпитализации по региону и профилю, где быстрее', Icons.hourglass_bottom),
      ('/medicines', 'Проверка рецепта', 'Покрытие, сроки обеспечения, признаки дефицита', Icons.medication),
      if (session.isDoctor) ('/worklist', 'Рабочий список', 'Пациенты на маршруте с приоритетами и флагами', Icons.list_alt),
      if (session.isDoctor) ('/referral', 'Ассистент направления', 'Прогноз, альтернативы и запись решения', Icons.assignment),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Darumen Care'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => context.push('/settings'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'citizen', label: Text('Гражданин'), icon: Icon(Icons.person)),
              ButtonSegment(value: 'doctor', label: Text('Врач'), icon: Icon(Icons.medical_services)),
            ],
            selected: {session.role},
            onSelectionChanged: (s) => session.update(role: s.first),
          ),
          const SizedBox(height: 8),
          Text('${Session.demoActors[session.role]} · демо-режим · регион ${session.region}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final c in cards)
            Card(
              child: ListTile(
                leading: Icon(c.$4),
                title: Text(c.$2),
                subtitle: Text(c.$3),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(c.$1),
              ),
            ),
          const SizedBox(height: 16),
          Text('Данные МЗ РК, I квартал 2025. Без персональных данных.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

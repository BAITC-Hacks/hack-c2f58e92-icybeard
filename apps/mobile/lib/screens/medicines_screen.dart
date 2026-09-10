import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({super.key});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  List<Nosology> nosologies = [];
  List<Mnn> mnns = [];
  String? nosologyId;
  String? mnnId;
  CheckResponse? result;
  Object? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    try {
      nosologies = await api.nosologies();
      nosologyId = nosologies.firstOrNull?.id;
      await _loadMnn();
      await _check();
    } catch (e) {
      setState(() => error = e);
    }
  }

  Future<void> _loadMnn() async {
    if (nosologyId == null) return;
    mnns = await context.read<Session>().api.mnn(nosologyId!);
    setState(() => mnnId = mnns.firstOrNull?.id);
  }

  Future<void> _check() async {
    final session = context.read<Session>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await session.api.checkMedicine(mnnId: mnnId, nosologyId: nosologyId, regionKato: session.region);
      setState(() => result = r);
    } catch (e) {
      setState(() => error = e);
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка рецепта')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: nosologyId,
            decoration: const InputDecoration(labelText: 'Нозология (по объёму рецептов)'),
            items: [for (final n in nosologies) DropdownMenuItem(value: n.id, child: Text('Нозология ${n.id} · ${n.issued12m} рецептов/год'))],
            onChanged: (v) async {
              setState(() => nosologyId = v);
              await _loadMnn();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: mnns.any((m) => m.id == mnnId) ? mnnId : null,
            decoration: const InputDecoration(labelText: 'МНН'),
            items: [for (final m in mnns) DropdownMenuItem(value: m.id, child: Text('МНН ${m.id} · ${m.issued12m} рецептов/год'))],
            onChanged: (v) => setState(() => mnnId = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : _check, icon: const Icon(Icons.check_circle), label: const Text('Проверить')),
          ErrorBox(error: error),
          if (result != null) ...[
            const SectionTitle('Покрытие'),
            Chip(
              label: Text(result!.covered ? 'покрыт программой${result!.program != null ? ' · ${result!.program}' : ''}' : 'активных спецификаций нет'),
              backgroundColor: result!.covered ? Colors.green.shade100 : Colors.orange.shade100,
            ),
            const SectionTitle('Сроки обеспечения'),
            Row(children: [
              Expanded(child: KpiTile(value: days(result!.fillDaysP50), label: 'медиана, дн.')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: days(result!.fillDaysP90), label: 'p90, дн.')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: pct(result!.pFilled14d), label: 'за 14 дней')),
            ]),
            Text(result!.basis, style: Theme.of(context).textTheme.bodySmall),
            const SectionTitle('Дефицит'),
            Chip(
              label: Text(result!.shortage.flag ? 'признаки дефицита, балл ${result!.shortage.score}' : 'без признаков дефицита'),
              backgroundColor: result!.shortage.flag ? Colors.red.shade100 : Colors.green.shade100,
            ),
            Text(result!.shortage.basis, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Аптеки рядом появятся после справочника аптек с координатами.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Оценки охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану. Публичный справочник,
/// без ролевых ограничений.
class VaccinationScreen extends StatefulWidget {
  const VaccinationScreen({super.key});

  @override
  State<VaccinationScreen> createState() => _VaccinationScreenState();
}

class _VaccinationScreenState extends State<VaccinationScreen> {
  List<VaccinationEstimate> items = [];
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<Session>().api.vaccination();
      setState(() {
        items = list;
        error = null;
      });
    } catch (e) {
      setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context.watch<Session>().locale);
    return Scaffold(
      appBar: AppBar(title: Text(s.vaccinationTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(s.vaccinationCaption, style: const TextStyle(fontSize: 12)),
          ),
          ErrorBox(error: error),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    title: Text('${item.title} · ${item.year}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.coveragePct.toStringAsFixed(0)}% · ${item.source}'),
                        if (item.note != null && item.note!.isNotEmpty)
                          Text(item.note!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

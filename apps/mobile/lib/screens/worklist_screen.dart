import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class WorklistScreen extends StatefulWidget {
  const WorklistScreen({super.key});

  @override
  State<WorklistScreen> createState() => _WorklistScreenState();
}

class _WorklistScreenState extends State<WorklistScreen> {
  List<WorklistItem> items = [];
  String? flag;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<Session>().api.worklist(flag: flag);
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
    final flagLabels = {'stuck_over_30': s.flagOver30, 'refusal_risk': s.flagRefusalRisk, 'faster_alternative': s.flagFasterAlt};
    return Scaffold(
      appBar: AppBar(title: Text(s.worklistTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: Text(s.flagAll), selected: flag == null, onSelected: (_) => setState(() { flag = null; _load(); })),
                for (final f in flagLabels.entries)
                  ChoiceChip(label: Text(f.value), selected: flag == f.key, onSelected: (_) => setState(() { flag = f.key; _load(); })),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(s.worklistCaption, style: const TextStyle(fontSize: 12)),
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
                    title: Text(s.waitingHeadline(item.patientRef, item.daysWaiting, item.priority)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.moName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Wrap(spacing: 4, children: [for (final f in item.riskFlags) Chip(label: Text(flagLabels[f] ?? f), visualDensity: VisualDensity.compact)]),
                        Text(item.nextAction),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => context.push('/referral?moCode=${item.moCode}&profileCode=${item.profileCode}'),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Врач: журнал собственных решений по направлениям (GET /api/v1/journal/decisions?actor=me).
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key});

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  List<DecisionRecord> items = [];
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<Session>().api.myDecisions();
      setState(() {
        items = list;
        error = null;
      });
    } catch (e) {
      setState(() => error = e);
    }
  }

  static String _formatted(String iso) {
    final parts = iso.split('T');
    if (parts.length != 2) return iso;
    final time = parts[1].length >= 5 ? parts[1].substring(0, 5) : parts[1];
    return '${parts[0]} $time';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context.watch<Session>().locale);
    return Scaffold(
      appBar: AppBar(title: Text(s.decisionsTitle)),
      body: Column(
        children: [
          ErrorBox(error: error),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(s.emptyDecisions)),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    title: Text('${_formatted(item.recordedAt)} · ${item.subject}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.recommendedChosen(item.recommendedMoCode, item.chosenMoCode)),
                        if (item.reason != null && item.reason!.isNotEmpty) Text(s.reasonPrefix(item.reason!)),
                      ],
                    ),
                    isThreeLine: item.reason != null && item.reason!.isNotEmpty,
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

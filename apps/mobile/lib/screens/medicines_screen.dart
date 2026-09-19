import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
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
    final s = S.of(context.watch<Session>().locale);
    return Scaffold(
      appBar: AppBar(title: Text(s.medicinesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: nosologyId,
            decoration: InputDecoration(labelText: s.nosologyLabel),
            items: [for (final n in nosologies) DropdownMenuItem(value: n.id, child: Text(s.nosologyItem(n.id, n.issued12m)))],
            onChanged: (v) async {
              setState(() => nosologyId = v);
              await _loadMnn();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: mnns.any((m) => m.id == mnnId) ? mnnId : null,
            decoration: InputDecoration(labelText: s.mnnLabel),
            items: [for (final m in mnns) DropdownMenuItem(value: m.id, child: Text(s.mnnItem(m.id, m.issued12m)))],
            onChanged: (v) => setState(() => mnnId = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : _check, icon: const Icon(Icons.check_circle), label: Text(s.checkButton)),
          ErrorBox(error: error),
          if (result != null) ...[
            SectionTitle(s.coverageSection),
            Chip(
              label: Text(result!.covered ? s.coveredBy(result!.program) : s.notCovered),
              backgroundColor: result!.covered ? Colors.green.shade100 : Colors.orange.shade100,
            ),
            SectionTitle(s.fillTimeSection),
            Row(children: [
              Expanded(child: KpiTile(value: days(result!.fillDaysP50), label: s.kpiMedianDays)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: days(result!.fillDaysP90), label: s.kpiP90Days)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: pct(result!.pFilled14d), label: s.kpiWithin14)),
            ]),
            Text(result!.basis, style: Theme.of(context).textTheme.bodySmall),
            SectionTitle(s.shortageSection),
            Chip(
              label: Text(result!.shortage.flag ? s.shortageFlag(result!.shortage.score) : s.noShortage),
              backgroundColor: result!.shortage.flag ? Colors.red.shade100 : Colors.green.shade100,
            ),
            Text(result!.shortage.basis, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(s.pharmacyHint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

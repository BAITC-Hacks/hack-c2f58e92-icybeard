import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Гражданин: ожидание по региону и профилю, альтернативы, место региона в индексе.
class WaitScreen extends StatefulWidget {
  const WaitScreen({super.key});

  @override
  State<WaitScreen> createState() => _WaitScreenState();
}

class _WaitScreenState extends State<WaitScreen> {
  List<Region> regions = [];
  List<BedProfile> profiles = [];
  String? region;
  String profile = '381';
  PredictResponse? prediction;
  List<Alternative> alternatives = [];
  IndexItem? indexItem;
  Object? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    region = context.read<Session>().region;
    _loadRefdata();
  }

  Future<void> _loadRefdata() async {
    final api = context.read<Session>().api;
    try {
      final results = await Future.wait([api.regions(), api.profiles()]);
      setState(() {
        regions = results[0] as List<Region>;
        profiles = results[1] as List<BedProfile>;
      });
      await _run();
    } catch (e) {
      setState(() => error = e);
    }
  }

  Future<void> _run() async {
    final api = context.read<Session>().api;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {'regionKato': region, 'profileCode': profile};
      final results = await Future.wait([api.predict(body), api.alternatives(body), api.index(profileCode: profile)]);
      setState(() {
        prediction = results[0] as PredictResponse;
        alternatives = results[1] as List<Alternative>;
        indexItem = (results[2] as List<IndexItem>).where((i) => i.regionKato == region).firstOrNull;
      });
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
      appBar: AppBar(title: Text(s.waitTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: regions.any((r) => r.kato == region) ? region : null,
            decoration: InputDecoration(labelText: s.regionLabel),
            items: [for (final r in regions) DropdownMenuItem(value: r.kato, child: Text(r.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => region = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: profiles.any((p) => p.code == profile) ? profile : null,
            decoration: InputDecoration(labelText: s.profileLabel),
            isExpanded: true,
            items: [for (final p in profiles) DropdownMenuItem(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => profile = v ?? profile),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : _run, icon: const Icon(Icons.search), label: Text(s.findButton)),
          ErrorBox(error: error),
          if (prediction != null) ...[
            SectionTitle(s.avgRegionSection),
            Row(children: [
              Expanded(child: KpiTile(value: days(prediction!.p50Days), label: s.kpiHalfWaits)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: days(prediction!.p90Days), label: s.kpiNineOfTen)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: pct(prediction!.pWithin30Days), label: s.kpiWithin30)),
            ]),
            const SizedBox(height: 8),
            Text(indexItem == null ? s.indexUnavailable : s.indexShown(indexItem!.indexValue.toStringAsFixed(1), indexItem!.rank)),
            SectionTitle(s.fasterSection),
            if (alternatives.isEmpty) Text(s.noOrgsForProfile),
            for (final a in alternatives)
              ListTile(
                dense: true,
                title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${s.flagRefusalRisk}: ${pct(a.pRefusal)}${a.distanceKm > 0 ? ' · ${a.distanceKm.round()} ${s.kmUnit}' : ''}'),
                trailing: Text('${days(a.p50Days)} ${s.daysUnit}', style: Theme.of(context).textTheme.titleMedium),
              ),
          ],
        ],
      ),
    );
  }
}

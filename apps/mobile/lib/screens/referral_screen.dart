import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key, this.moCode, this.profileCode});
  final String? moCode;
  final String? profileCode;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  List<BedProfile> profiles = [];
  List<Organization> organizations = [];
  late String profile = widget.profileCode ?? '381';
  String? moCode;
  final icd = TextEditingController(text: 'H25.1');
  final reason = TextEditingController();
  PredictResponse? prediction;
  List<Alternative> alternatives = [];
  Object? error;
  bool busy = false;
  String? recorded;

  @override
  void initState() {
    super.initState();
    moCode = widget.moCode;
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      profiles = await session.api.profiles();
      await _loadOrganizations();
      await _predict();
    } catch (e) {
      setState(() => error = e);
    }
  }

  Future<void> _loadOrganizations() async {
    final session = context.read<Session>();
    organizations = await session.api.organizations(session.region, profile);
    if (!organizations.any((o) => o.moCode == moCode)) moCode = organizations.firstOrNull?.moCode;
    setState(() {});
  }

  Map<String, dynamic> get _request => {
        'regionKato': context.read<Session>().region,
        'moCode': moCode,
        'profileCode': profile,
        'icd10': icd.text,
        'referralPurpose': 'Оперативное лечение',
        'territorialType': 'Город',
        'financeSource': 'Активы Фонда на ОСМС',
      };

  Future<void> _predict() async {
    final api = context.read<Session>().api;
    setState(() {
      busy = true;
      error = null;
      recorded = null;
    });
    try {
      final results = await Future.wait([api.predict(_request), api.alternatives(_request)]);
      setState(() {
        prediction = results[0] as PredictResponse;
        alternatives = results[1] as List<Alternative>;
      });
    } catch (e) {
      setState(() => error = e);
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _record(String chosen) async {
    final session = context.read<Session>();
    final s = S.of(session.locale);
    try {
      final id = await session.api.recordDecision({
        'subject': 'referral',
        'subjectId': '${session.region}.$moCode.$profile.mobile',
        'recommended': {'moCode': alternatives.firstOrNull?.moCode ?? moCode},
        'chosen': {'moCode': chosen},
        'reason': reason.text,
      }, DateTime.now().microsecondsSinceEpoch.toString());
      setState(() => recorded = id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.snackRecorded(id))));
    } on ApiException catch (e) {
      setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context.watch<Session>().locale);
    return Scaffold(
      appBar: AppBar(title: Text(s.referralTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: profiles.any((p) => p.code == profile) ? profile : null,
            decoration: InputDecoration(labelText: s.profileLabel),
            isExpanded: true,
            items: [for (final p in profiles) DropdownMenuItem(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) async {
              setState(() => profile = v ?? profile);
              await _loadOrganizations();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: organizations.any((o) => o.moCode == moCode) ? moCode : null,
            decoration: InputDecoration(labelText: s.organizationLabel),
            isExpanded: true,
            items: [for (final o in organizations) DropdownMenuItem(value: o.moCode, child: Text(o.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => moCode = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: icd, decoration: InputDecoration(labelText: s.icdLabel)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : _predict, icon: const Icon(Icons.calculate), label: Text(s.calculateButton)),
          ErrorBox(error: error),
          if (prediction != null) ...[
            SectionTitle(s.forecastSection),
            Row(children: [
              Expanded(child: KpiTile(value: days(prediction!.p50Days), label: s.kpiMedianDays)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: days(prediction!.p90Days), label: s.kpiP90Days)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: KpiTile(value: pct(prediction!.pWithin30Days), label: s.kpiWithin30)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(value: pct(prediction!.pRefusal), label: s.flagRefusalRisk)),
            ]),
            if (prediction!.queue != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.queueInfo(prediction!.queue!.len, days(prediction!.queue!.ageP50), prediction!.queue!.throughputPerDay.toStringAsFixed(1))),
              ),
            const SizedBox(height: 8),
            ExplanationCard(explanation: prediction!.explanation, model: prediction!.model),
            SectionTitle(s.alternativesSection),
            for (final a in alternatives)
              ListTile(
                dense: true,
                title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.altSubtitle(days(a.p50Days), days(a.p90Days), pct(a.pRefusal))),
                trailing: TextButton(onPressed: () => _record(a.moCode), child: Text(s.referButton)),
              ),
            TextField(controller: reason, decoration: InputDecoration(labelText: s.reasonLabel)),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: moCode == null ? null : () => _record(moCode!), icon: const Icon(Icons.check), label: Text(s.keepButton)),
            if (recorded != null) Text(s.recordedLabel(recorded!), style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

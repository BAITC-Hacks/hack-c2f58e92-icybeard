import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/explanation_card.dart';
import '../widgets/format.dart';
import '../widgets/kpi_tile.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Значения категориальных признаков — контракт модели (русские литералы, как в вебе); в интерфейсе — переводимые
/// подписи из S.purposeLabels / S.territorialLabels в том же порядке.
abstract final class ReferralOptions {
  static const purposes = ['Оперативное лечение', 'Консервативное лечение', 'Диагностика', 'Реабилитация'];
  static const territorial = ['Город', 'Село'];
  static const financeSource = 'Активы Фонда на ОСМС';
}

/// Ассистент направления: прогноз ожидания и риска отказа («ML‑модель»), факторы, альтернативы региона и запись
/// решения врача. Один Idempotency-Key на расчёт — повторное нажатие не создаёт вторую запись. Открытый с маршрута
/// пациента экран пишет решение в его маршрут (`/route/{ref}/redirect`), иначе — обычное решение по направлению.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key, this.patientRef, this.moCode, this.profileCode});

  final String? patientRef;
  final String? moCode;
  final String? profileCode;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _Forecast {
  const _Forecast(this.prediction, this.alternatives);

  final PredictResponse prediction;
  final List<Alternative> alternatives;
}

class _ReferralScreenState extends State<ReferralScreen> {
  List<BedProfile> _profiles = const [];
  List<Organization> _organizations = const [];
  String? _profile;
  String? _moCode;
  String _purpose = ReferralOptions.purposes.first;
  String _territorial = ReferralOptions.territorial.first;
  final _icd = TextEditingController();
  final _reason = TextEditingController();
  LoadState<_Forecast>? _state;
  Object? _refdataError;
  String _decisionKey = '';
  String? _recorded;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _profile = widget.profileCode ?? session.lastProfile;
    _moCode = widget.moCode;
    _load();
  }

  @override
  void dispose() {
    _icd.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profiles = await context.read<Session>().api.profiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles;
        _refdataError = null;
      });
      if (_profile != null) {
        await _loadOrganizations();
        if (_moCode != null) {
          await _predict();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  Future<void> _loadOrganizations() async {
    final session = context.read<Session>();
    final profile = _profile;
    if (profile == null) {
      return;
    }
    final organizations = await session.api.organizations(session.region, profile);
    if (mounted) {
      setState(() {
        _organizations = organizations;
        if (!organizations.any((o) => o.moCode == _moCode)) {
          _moCode = null;
        }
      });
    }
  }

  Map<String, dynamic> _request(Session session) => {
        'regionKato': session.region,
        'moCode': _moCode,
        'profileCode': _profile,
        'icd10': _icd.text.trim().isEmpty ? null : _icd.text.trim(),
        'referralPurpose': _purpose,
        'territorialType': _territorial,
        'financeSource': ReferralOptions.financeSource,
      };

  Future<void> _predict() async {
    final session = context.read<Session>();
    if (_moCode == null || _profile == null) {
      return;
    }
    setState(() {
      _state = const Loading();
      _recorded = null;
    });
    try {
      final request = _request(session);
      final results = await Future.wait<Object>([session.api.predict(request), session.api.alternatives(request)]);
      await session.rememberProfile(_profile!);
      if (mounted) {
        final random = Random.secure();
        setState(() {
          _state = Loaded(_Forecast(results[0] as PredictResponse, results[1] as List<Alternative>));
          _decisionKey = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _record(String chosen, List<Alternative> alternatives) async {
    final session = context.read<Session>();
    final s = S.at(context);
    final patientRef = widget.patientRef;
    setState(() => _recording = true);
    try {
      final String id;
      if (patientRef != null && chosen != _moCode) {
        id = await session.api.redirectRoute(patientRef, toMoCode: chosen, reason: _reason.text.trim(), idempotencyKey: _decisionKey);
      } else {
        id = await session.api.recordDecision({
          'subject': patientRef != null ? 'route' : 'referral',
          'subjectId': patientRef ?? '${session.region}.$_moCode.$_profile.mobile',
          'recommended': {'moCode': alternatives.firstOrNull?.moCode ?? _moCode},
          'chosen': {'moCode': chosen},
          'reason': _reason.text.trim(),
        }, _decisionKey);
      }
      if (mounted) {
        setState(() => _recorded = id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.snackRecorded(id)),
          action: SnackBarAction(label: s.decisionsTitle, onPressed: () => context.go('/doctor/referral/decisions')),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    } finally {
      if (mounted) {
        setState(() => _recording = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final state = _state;
    final ready = _moCode != null && _profile != null;
    return PageScaffold(
      title: s.referralTitle,
      children: [
        if (widget.patientRef != null) ...[
          StatusChip('${s.patientRouteTitle}: ${widget.patientRef}', tone: StatusTone.accent, icon: Icons.person_outline),
          const SizedBox(height: AppSpacing.md),
        ],
        DropdownButtonFormField<String>(
          initialValue: _profiles.any((p) => p.code == _profile) ? _profile : null,
          decoration: InputDecoration(labelText: s.profileLabel),
          isExpanded: true,
          items: [for (final p in _profiles) DropdownMenuItem(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) async {
            setState(() => _profile = v);
            await _loadOrganizations();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _organizations.any((o) => o.moCode == _moCode) ? _moCode : null,
          decoration: InputDecoration(labelText: s.organizationLabel),
          isExpanded: true,
          items: [for (final o in _organizations) DropdownMenuItem(value: o.moCode, child: Text(o.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _moCode = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _purpose,
                decoration: InputDecoration(labelText: s.purposeLabel),
                isExpanded: true,
                items: [
                  for (final (i, value) in ReferralOptions.purposes.indexed)
                    DropdownMenuItem(value: value, child: Text(s.purposeLabels[i], overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _purpose = v ?? _purpose),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _territorial,
                decoration: InputDecoration(labelText: s.territorialLabel),
                isExpanded: true,
                items: [
                  for (final (i, value) in ReferralOptions.territorial.indexed)
                    DropdownMenuItem(value: value, child: Text(s.territorialLabels[i], overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _territorial = v ?? _territorial),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _icd,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: s.icdLabel, hintText: 'H25.1', helperText: s.icdOptionalHint),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(onPressed: ready && state is! Loading ? _predict : null, icon: const Icon(Icons.calculate_outlined), label: Text(s.calculateButton)),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _load)],
        if (state == null)
          EmptyState(icon: Icons.assignment_outlined, title: s.selectOrganizationHint)
        else
          switch (state) {
            Loading<_Forecast>() => const Padding(padding: EdgeInsets.only(top: AppSpacing.lg), child: KpiRowSkeleton()),
            Failed<_Forecast>(:final error) => Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: ErrorBox(error: error, onRetry: _predict)),
            Loaded<_Forecast>(:final data) => _Results(
                data: data,
                s: s,
                theme: theme,
                reason: _reason,
                recorded: _recorded,
                busy: _recording,
                currentMoCode: _moCode,
                onRecord: (chosen) => _record(chosen, data.alternatives),
              ),
          },
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.data,
    required this.s,
    required this.theme,
    required this.reason,
    required this.recorded,
    required this.busy,
    required this.currentMoCode,
    required this.onRecord,
  });

  final _Forecast data;
  final S s;
  final ThemeData theme;
  final TextEditingController reason;
  final String? recorded;
  final bool busy;
  final String? currentMoCode;
  final void Function(String chosen) onRecord;

  @override
  Widget build(BuildContext context) {
    final p = data.prediction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(s.forecastSection, origin: Origin.ml),
        KpiRow(
          children: [
            KpiTile(value: days(p.p50Days), label: s.kpiMedianDays),
            KpiTile(value: days(p.p90Days), label: s.kpiP90Days),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        KpiRow(
          children: [
            KpiTile(value: pct(p.pWithin30Days), label: s.kpiWithin30),
            KpiTile(value: p.refusalOrgInTraining ? pct(p.pRefusal) : _refusalWords(p.pRefusal), label: s.flagRefusalRisk),
          ],
        ),
        if (!p.refusalOrgInTraining) ...[const SizedBox(height: AppSpacing.xs), Text(s.refusalOrgUnknownNote, style: theme.textTheme.labelSmall)],
        if (p.queue != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(s.queueInfo(p.queue!.len, days(p.queue!.ageP50), p.queue!.throughputPerDay.toStringAsFixed(1)), style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
        ],
        const SizedBox(height: AppSpacing.md),
        ExplanationCard(explanation: p.explanation, model: p.model),
        SectionTitle(s.alternativesSection, origin: Origin.ml),
        if (data.alternatives.isEmpty)
          Text(s.noOrgsForProfile, style: theme.textTheme.bodySmall)
        else
          Card(
            child: Column(
              children: [
                for (final a in data.alternatives)
                  ListTile(
                    title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.altSubtitle(days(a.p50Days), days(a.p90Days), pct(a.pRefusal)), style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
                    trailing: TextButton(onPressed: busy || recorded != null ? null : () => onRecord(a.moCode), child: Text(s.referButton)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: reason, decoration: InputDecoration(labelText: s.reasonLabel), maxLines: 2),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: currentMoCode == null || busy || recorded != null ? null : () => onRecord(currentMoCode!),
          icon: const Icon(Icons.check),
          label: Text(s.keepButton),
        ),
        if (recorded != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(s.recordedLabel(recorded!), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
        ],
      ],
    );
  }

  String _refusalWords(double pRefusal) => pRefusal > 0.165 ? s.refusalAboveAverage : pRefusal > 0.055 ? s.refusalAroundAverage : s.refusalBelowAverage;
}

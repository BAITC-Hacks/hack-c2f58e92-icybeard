import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/alternative_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/explanation_card.dart';
import '../widgets/format.dart';
import '../widgets/hero_number.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/redirect_reason_dialog.dart';
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

/// Ассистент направления: форма в одной карточке (селекторы-листы, МКБ-10 необязательно, «Рассчитать»), главное
/// число «N дн. — половина» со строкой p90 / 30 дней / риск [ML], «Почему так» строками, альтернативы с
/// «Направить» (лист причины) и «Оставить в выбранной». Один Idempotency-Key на расчёт — повтор не создаёт
/// вторую запись. Открытый с маршрута пациента экран пишет решение в его маршрут.
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

  Future<void> _pickProfile() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.profileLabel,
      items: [for (final p in _profiles) PickerItem(p.code, p.name)],
      selected: _profile,
    );
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      _profile = chosen;
      _state = null;
    });
    await _loadOrganizations();
  }

  Future<void> _pickOrganization() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.organizationLabel,
      items: [for (final o in _organizations) PickerItem(o.moCode, shortOrgName(o.name), detail: o.name)],
      selected: _moCode,
    );
    if (chosen != null && mounted) {
      setState(() => _moCode = chosen);
    }
  }

  Future<void> _pickPurpose() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.purposeLabel,
      items: [for (final (i, value) in ReferralOptions.purposes.indexed) PickerItem(value, s.purposeLabels[i])],
      selected: _purpose,
      search: false,
    );
    if (chosen != null && mounted) {
      setState(() => _purpose = chosen);
    }
  }

  Future<void> _pickTerritorial() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.territorialLabel,
      items: [for (final (i, value) in ReferralOptions.territorial.indexed) PickerItem(value, s.territorialLabels[i])],
      selected: _territorial,
      search: false,
    );
    if (chosen != null && mounted) {
      setState(() => _territorial = chosen);
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
        setState(() {
          _state = Loaded(_Forecast(results[0] as PredictResponse, results[1] as List<Alternative>));
          _decisionKey = newIdempotencyKey();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _refer(Alternative alternative, List<Alternative> alternatives) async {
    final s = S.at(context);
    final reason = await RedirectReasonDialog.show(
      context,
      organization: alternative.name,
      subtitle: '≈ ${days(alternative.p50Days)} ${s.daysUnit} · ${s.riskShort(pct(alternative.pRefusal))}',
      label: s.reasonLabel,
      confirmLabel: s.referButton,
    );
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    await _record(alternative.moCode, reason, alternatives);
  }

  Future<void> _keep(List<Alternative> alternatives) async {
    final s = S.at(context);
    final chosen = _moCode;
    if (chosen == null) {
      return;
    }
    final name = _organizations.where((o) => o.moCode == chosen).map((o) => o.name).firstOrNull ?? chosen;
    final reason = await RedirectReasonDialog.show(context, organization: name, label: s.reasonLabel, confirmLabel: s.keepInChosen, optional: true);
    if (reason == null || !mounted) {
      return;
    }
    await _record(chosen, reason, alternatives);
  }

  Future<void> _record(String chosen, String reason, List<Alternative> alternatives) async {
    final session = context.read<Session>();
    final s = S.at(context);
    final patientRef = widget.patientRef;
    setState(() => _recording = true);
    try {
      final String id;
      if (patientRef != null && chosen != _moCode) {
        id = await session.api.redirectRoute(patientRef, toMoCode: chosen, reason: reason, idempotencyKey: _decisionKey);
      } else {
        id = await session.api.recordDecision({
          'subject': patientRef != null ? 'route' : 'referral',
          'subjectId': patientRef ?? '${session.region}.$_moCode.$_profile.mobile',
          'recommended': {'moCode': alternatives.firstOrNull?.moCode ?? _moCode},
          'chosen': {'moCode': chosen},
          'reason': reason,
        }, _decisionKey);
      }
      if (mounted) {
        setState(() => _recorded = id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.decisionRecorded),
          action: SnackBarAction(label: s.journalShort, onPressed: () => context.go('/doctor/referral/decisions')),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
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
    final state = _state;
    final ready = _moCode != null && _profile != null;
    final profileName = _profiles.where((p) => p.code == _profile).map((p) => p.name).firstOrNull;
    final orgName = _organizations.where((o) => o.moCode == _moCode).map((o) => shortOrgName(o.name)).firstOrNull;
    return PageScaffold(
      title: s.referralTitle,
      children: [
        if (widget.patientRef != null) ...[
          StatusChip('${s.patientRouteTitle}: ${widget.patientRef}', tone: StatusTone.accent, icon: Icons.person_outline),
          const SizedBox(height: AppSpacing.md),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PickerRow(label: s.profileShort, value: profileName, placeholder: s.choosePlaceholder, onTap: _pickProfile, enabled: _profiles.isNotEmpty),
                const SizedBox(height: AppSpacing.sm),
                PickerRow(label: s.organizationLabel, value: orgName, placeholder: s.choosePlaceholder, onTap: _pickOrganization, enabled: _organizations.isNotEmpty),
                const SizedBox(height: AppSpacing.sm),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: PickerRow(label: s.purposeLabel, value: s.purposeLabels[ReferralOptions.purposes.indexOf(_purpose)], onTap: _pickPurpose)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: PickerRow(label: s.territoryShort, value: s.territorialLabels[ReferralOptions.territorial.indexOf(_territorial)], onTap: _pickTerritorial)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _icd,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: s.icdLabel, hintText: 'H25.1', helperText: s.icdOptionalHint),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(onPressed: ready && state is! Loading ? _predict : null, icon: const Icon(Icons.calculate_outlined), label: Text(s.calculateButton)),
              ],
            ),
          ),
        ),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _load)],
        if (state == null)
          EmptyState(icon: Icons.assignment_outlined, title: s.selectOrganizationHint, body: s.selectOrganizationBody)
        else
          switch (state) {
            Loading<_Forecast>() => const Padding(
                padding: EdgeInsets.only(top: AppSpacing.lg),
                child: Column(children: [Skeleton(height: 44, width: 160), SizedBox(height: AppSpacing.md), Skeleton(height: 16), SizedBox(height: AppSpacing.xl), ListSkeleton(count: 3)]),
              ),
            Failed<_Forecast>(:final error) => Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: ErrorBox(error: error, onRetry: _predict)),
            Loaded<_Forecast>(:final data) => _Results(
                data: data,
                recorded: _recorded,
                busy: _recording,
                canKeep: _moCode != null,
                onRefer: (a) => _refer(a, data.alternatives),
                onKeep: () => _keep(data.alternatives),
              ),
          },
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.data, required this.recorded, required this.busy, required this.canKeep, required this.onRefer, required this.onKeep});

  final _Forecast data;
  final String? recorded;
  final bool busy;
  final bool canKeep;
  final void Function(Alternative alternative) onRefer;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final p = data.prediction;
    final locked = busy || recorded != null;
    final risk = p.refusalOrgInTraining ? pct(p.pRefusal) : _refusalWords(s, p.pRefusal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        HeroNumber(
          value: days(p.p50Days),
          unit: s.daysUnit,
          caption: s.halfCaption,
          line: '${s.nineOfTenLine(days(p.p90Days))} · ${s.within30Line(pct(p.pWithin30Days))} · ${s.riskLine(risk)}',
          origin: Origin.ml,
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
                for (final (i, a) in data.alternatives.indexed) ...[
                  if (i > 0) const Divider(),
                  AlternativeRow(
                    alternative: a,
                    showRisk: true,
                    showP90: true,
                    trailing: TextButton(onPressed: locked ? null : () => onRefer(a), child: Text(s.referButton)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(onPressed: canKeep && !locked ? onKeep : null, icon: const Icon(Icons.check), label: Text(s.keepInChosen)),
        if (recorded != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(s.recordedLabel(recorded!), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
        ],
      ],
    );
  }

  static String _refusalWords(S s, double pRefusal) => pRefusal > 0.165 ? s.refusalAboveAverage : pRefusal > 0.055 ? s.refusalAroundAverage : s.refusalBelowAverage;
}

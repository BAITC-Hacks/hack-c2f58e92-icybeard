import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/explanation_card.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
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

/// Вариант выбора: организация с прогнозом (текущая — из predict, альтернативы — из alternatives).
class ReferralOption {
  const ReferralOption({required this.moCode, required this.name, required this.p50Days, required this.risk, this.alternative});

  final String moCode;
  final String name;
  final double p50Days;

  /// Риск отказа словами или процентом (организация вне обучения — словами).
  final String risk;
  final Alternative? alternative;
}

/// Ассистент направления по доске M-Referral: подпись «Пациент REF · цель · территория», профиль полем,
/// организации опция-карточками с чипом «рекомендация» (наименьший p50) и inset-обводкой у выбранной, поле
/// «Причина», «Подтвердить направление» внизу. Прогноз считается при выборе профиля и организации — без кнопки;
/// один Idempotency-Key на расчёт — повтор не создаёт вторую запись. Открытый с маршрута пациента экран пишет
/// решение в его маршрут.
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
  String? _chosen;
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
    _reason.addListener(() => setState(() {}));
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
          _state = null;
        }
      });
    }
  }

  Future<void> _pickProfile() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(context, title: s.profileLabel, items: [for (final p in _profiles) PickerItem(p.code, p.name)], selected: _profile);
    if (chosen == null || !mounted) {
      return;
    }
    setState(() {
      _profile = chosen;
      _state = null;
      _chosen = null;
    });
    await _loadOrganizations();
    if (_moCode != null) {
      await _predict();
    }
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
      setState(() {
        _moCode = chosen;
        _chosen = null;
      });
      await _predict();
    }
  }

  Future<void> _pickOption(String title, List<String> values, List<String> labels, String selected, void Function(String) apply) async {
    final chosen = await PickerSheet.show<String>(
      context,
      title: title,
      items: [for (final (i, value) in values.indexed) PickerItem(value, labels[i])],
      selected: selected,
      search: false,
    );
    if (chosen != null && mounted) {
      setState(() => apply(chosen));
      await _predict();
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
          _chosen = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  String _orgName(String code) => _organizations.where((o) => o.moCode == code).map((o) => o.name).firstOrNull ?? code;

  static String _refusalWords(S s, double pRefusal) => pRefusal > 0.165 ? s.refusalAboveAverage : pRefusal > 0.055 ? s.refusalAroundAverage : s.refusalBelowAverage;

  /// Опции: текущая организация с прогнозом predict, затем альтернативы; рекомендация — наименьший p50.
  List<ReferralOption> _options(S s, _Forecast data) {
    final p = data.prediction;
    return [
      ReferralOption(moCode: _moCode!, name: _orgName(_moCode!), p50Days: p.p50Days, risk: p.refusalOrgInTraining ? pct(p.pRefusal) : _refusalWords(s, p.pRefusal)),
      for (final a in data.alternatives)
        if (a.moCode != _moCode) ReferralOption(moCode: a.moCode, name: a.name, p50Days: a.p50Days, risk: pct(a.pRefusal), alternative: a),
    ];
  }

  static ReferralOption recommended(List<ReferralOption> options) => options.reduce((a, b) => a.p50Days <= b.p50Days ? a : b);

  Future<void> _confirm(List<ReferralOption> options) async {
    final session = context.read<Session>();
    final s = S.at(context);
    final chosen = _chosen ?? recommended(options).moCode;
    final reason = _reason.text.trim();
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
          'recommended': {'moCode': recommended(options).moCode},
          'chosen': {'moCode': chosen},
          'reason': reason,
        }, _decisionKey);
      }
      if (mounted) {
        setState(() => _recorded = id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.decisionRecorded),
          action: SnackBarAction(label: s.journalShort, onPressed: () => context.go('/doctor/decisions')),
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
    final theme = Theme.of(context);
    final state = _state;
    final data = switch (state) { Loaded<_Forecast>(:final data) => data, _ => null };
    final options = data == null ? const <ReferralOption>[] : _options(s, data);
    final chosen = options.isEmpty ? null : (_chosen ?? recommended(options).moCode);
    final locked = _recording || _recorded != null;
    final reasonOk = chosen == _moCode || _reason.text.trim().isNotEmpty;
    final profileName = _profiles.where((p) => p.code == _profile).map((p) => p.name).firstOrNull;
    final purpose = s.purposeLabels[ReferralOptions.purposes.indexOf(_purpose)];
    final territory = s.territorialLabels[ReferralOptions.territorial.indexOf(_territorial)];
    return PageScaffold(
      title: s.referralTitle,
      bottom: FilledButton(onPressed: options.isEmpty || locked || !reasonOk ? null : () => _confirm(options), child: Text(s.confirmReferral)),
      children: [
        Text(
          widget.patientRef != null ? s.patientLine(widget.patientRef!, purpose, territory) : '$purpose · $territory',
          style: theme.textTheme.bodySmall?.merge(AppType.numeric),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(s.profileShort),
            PickerRow(label: s.profileShort, value: profileName, placeholder: s.choosePlaceholder, onTap: _pickProfile, enabled: _profiles.isNotEmpty),
          ],
        ),
        Row(
          children: [
            Expanded(child: PickerRow(label: s.purposeLabel, value: purpose, onTap: () => _pickOption(s.purposeLabel, ReferralOptions.purposes, s.purposeLabels, _purpose, (v) => _purpose = v))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: PickerRow(label: s.territoryShort, value: territory, onTap: () => _pickOption(s.territorialLabel, ReferralOptions.territorial, s.territorialLabels, _territorial, (v) => _territorial = v))),
          ],
        ),
        PickerRow(
          label: s.organizationLabel,
          value: _moCode == null ? null : shortOrgName(_orgName(_moCode!)),
          placeholder: s.choosePlaceholder,
          onTap: _pickOrganization,
          enabled: _organizations.isNotEmpty,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel('${s.icdLabel} · ${s.icdOptionalHint}'),
            TextField(
              controller: _icd,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _predict(),
              decoration: const InputDecoration(hintText: 'H25.1', isDense: true),
            ),
          ],
        ),
        if (_refdataError != null) ErrorBox(error: _refdataError, onRetry: _load),
        if (state == null)
          EmptyState(icon: Icons.assignment_outlined, title: s.selectOrganizationHint, body: s.selectOrganizationBody)
        else
          switch (state) {
            Loading<_Forecast>() => const Column(children: [CardSkeleton(height: 96), SizedBox(height: AppSpacing.sm), CardSkeleton(height: 96)]),
            Failed<_Forecast>(:final error) => ErrorBox(error: error, onRetry: _predict),
            Loaded<_Forecast>(:final data) => _Options(
                options: options,
                chosen: chosen!,
                locked: locked,
                onSelect: (code) => setState(() => _chosen = code),
                prediction: data.prediction,
                reason: _reason,
                recorded: _recorded,
              ),
          },
      ],
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.options, required this.chosen, required this.locked, required this.onSelect, required this.prediction, required this.reason, required this.recorded});

  final List<ReferralOption> options;
  final String chosen;
  final bool locked;
  final void Function(String moCode) onSelect;
  final PredictResponse prediction;
  final TextEditingController reason;
  final String? recorded;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final best = _ReferralScreenState.recommended(options).moCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardLabel(s.organizationLabel, trailing: const OriginTag(Origin.ml)),
        const SizedBox(height: AppSpacing.sm),
        for (final (i, o) in options.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
            child: AppCard(
              padding: AppCard.plain,
              onTap: locked ? null : () => onSelect(o.moCode),
              color: o.moCode == chosen ? colors.surfaceInfo : null,
              border: o.moCode == chosen ? Border.all(color: colors.accent, width: 2) : null,
              semanticsLabel: '${shortOrgName(o.name)}, ${s.altLine(days(o.p50Days), o.risk)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(shortOrgName(o.name), style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      if (o.moCode == best) ...[const SizedBox(width: 10), StatusChip(s.recommendationChip, tone: StatusTone.accent)],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s.altLine(days(o.p50Days), o.risk), style: theme.textTheme.bodySmall?.copyWith(color: colors.muted).merge(AppType.numeric)),
                ],
              ),
            ),
          ),
        if (!prediction.refusalOrgInTraining) ...[const SizedBox(height: AppSpacing.sm), Text(s.refusalOrgUnknownNote, style: theme.textTheme.labelSmall)],
        const SizedBox(height: AppSpacing.md),
        FieldLabel(s.reasonShortLabel),
        TextField(controller: reason, enabled: !locked, maxLines: 2, decoration: InputDecoration(hintText: s.reasonHint)),
        const SizedBox(height: AppSpacing.md),
        CollapsibleSection(title: s.whySo, summary: '${prediction.explanation.factors.length}', origin: Origin.ml, child: FactorList(explanation: prediction.explanation, model: prediction.model)),
        const SizedBox(height: AppSpacing.md),
        Text(recorded == null ? s.modelDisclaimer : s.recordedLabel(recorded!), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
      ],
    );
  }
}

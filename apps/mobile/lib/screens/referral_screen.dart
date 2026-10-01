import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/almaty_time.dart';
import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/api_error.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/referral/referral_form.dart';
import '../widgets/referral/referral_options.dart';
import '../widgets/referral/referral_params.dart';
import '../widgets/referral/referral_result.dart';
import '../widgets/section.dart';

/// Ассистент направления — только для НОВОГО направления, до постановки в лист ожидания (решение Q-5; решения по
/// пациентам, которые уже ждут, принимаются на странице пациента). Веб ReferralView одной колонкой: «Параметры
/// направления» → «Куда направить» → «Прогноз для «…»» → «Решение»; «Записать выбор» — в нижней зоне. Прогноз
/// (`/queue/predict` и `/queue/alternatives`) пересчитывается сам при каждом изменении полной формы; ответ
/// устаревшего расчёта отбрасывается. Выбор врача и рекомендация системы пишутся в журнал решений с subjectId
/// `регион.организация.профиль.ГГГГ-ММ-ДД`; причина необязательна (Q-6); один ключ идемпотентности на нажатие.
/// Ошибки: 422 — под полями «Профиль койки» и «Дата постановки в очередь» (и в плашке), сервис моделей недоступен —
/// плашка без чисел, 403 — «нет доступа».
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key, this.moCode, this.profileCode});

  /// Организация и профиль — из перехода «Подобрать в ассистенте»; иначе врач выбирает сам.
  final String? moCode;
  final String? profileCode;

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  List<Region> _regions = const [];
  List<BedProfile> _profiles = const [];
  List<Organization> _organizations = const [];
  List<Organization> _referring = const [];
  late ReferralForm _form;
  PredictResponse? _prediction;
  List<Alternative> _alternatives = const [];
  bool _busy = false;
  Object? _error;
  String? _profileError;
  String? _dateError;
  String? _reasonError;
  String _chosen = '';
  String? _recorded;
  bool _recording = false;
  int _run = 0;
  final _icd = TextEditingController();
  final _date = TextEditingController();
  final _reason = TextEditingController();

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _form = ReferralForm(regionKato: session.region, moCode: widget.moCode ?? '', profileCode: widget.profileCode ?? session.lastProfile ?? '');
    unawaited(_load());
  }

  @override
  void dispose() {
    _icd.dispose();
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  // ---------- данные ----------

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([_api.regions(), _api.profiles()]);
      if (!mounted) return;
      final profiles = results[1] as List<BedProfile>;
      setState(() {
        _regions = results[0] as List<Region>;
        _profiles = profiles;
        if (!profiles.any((p) => p.code == _form.profileCode)) _form = _form.copyWith(profileCode: '');
      });
      await Future.wait([_loadOrganizations(), _loadReferring()]);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    await _predict();
  }

  /// Организации региона с профилем; выбранная, которой в новом списке нет, сбрасывается.
  Future<void> _loadOrganizations() async {
    final form = _form;
    if (form.regionKato.isEmpty || form.profileCode.isEmpty) {
      setState(() => _organizations = const []);
      return;
    }
    final list = await _api.organizations(form.regionKato, form.profileCode);
    if (!mounted || form.regionKato != _form.regionKato || form.profileCode != _form.profileCode) return;
    setState(() {
      _organizations = list;
      if (_form.moCode.isNotEmpty && !list.any((o) => o.moCode == _form.moCode)) _form = _form.copyWith(moCode: '');
    });
  }

  /// Все организации региона — для «Направляющая организация».
  Future<void> _loadReferring() async {
    final region = _form.regionKato;
    final list = await _api.organizations(region);
    if (!mounted || region != _form.regionKato) return;
    setState(() {
      _referring = list;
      if (_form.referringMoCode.isNotEmpty && !list.any((o) => o.moCode == _form.referringMoCode)) _form = _form.copyWith(referringMoCode: '');
    });
  }

  /// Новая форма → (справочники) → прогноз.
  Future<void> _change(ReferralForm next, {bool organizations = false, bool referring = false}) async {
    setState(() => _form = next);
    try {
      await Future.wait([if (organizations) _loadOrganizations(), if (referring) _loadReferring()]);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    await _predict();
  }

  Future<void> _predict() async {
    final form = _form;
    final run = ++_run;
    setState(() {
      _error = null;
      _profileError = null;
      _dateError = null;
      _recorded = null;
      if (!form.complete) {
        _prediction = null;
        _alternatives = const [];
      }
      _busy = form.complete;
    });
    if (!form.complete) return;
    try {
      final results = await Future.wait<Object>([_api.predict(form.toRequest()), _api.alternatives(form.toAlternativesRequest())]);
      if (!mounted || run != _run) return;
      setState(() {
        _prediction = results[0] as PredictResponse;
        _alternatives = referralAlternatives(results[1] as List<Alternative>, form.moCode);
        _chosen = form.moCode;
      });
      unawaited(context.read<Session>().rememberProfile(form.profileCode));
    } on Object catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _error = e;
        _prediction = null;
        _alternatives = const [];
        _profileError = apiFieldError(e, 'profileCode');
        _dateError = apiFieldError(e, 'registrationDate');
      });
    } finally {
      if (mounted && run == _run) setState(() => _busy = false);
    }
  }

  // ---------- действия ----------

  Future<void> _pick(String title, List<PickerItem<String>> items, String selected, ReferralForm Function(String value) apply,
      {bool search = true, bool organizations = false, bool referring = false}) async {
    final value = await PickerSheet.show<String>(context, title: title, items: items, selected: selected, search: search);
    if (value != null && value != selected && mounted) await _change(apply(value), organizations: organizations, referring: referring);
  }

  void _textDone() {
    final icd = _icd.text.trim();
    final date = _date.text.trim();
    if (icd != _form.icd10 || date != _form.registrationDate) unawaited(_change(_form.copyWith(icd10: icd, registrationDate: date)));
  }

  Future<void> _record() async {
    final s = S.at(context);
    final prediction = _prediction;
    if (prediction == null || _recorded != null || _recording || _chosen.isEmpty) return;
    final key = newIdempotencyKey();
    setState(() {
      _recording = true;
      _reasonError = null;
    });
    try {
      final id = await _api.recordDecision({
        'subject': DecisionCodes.subjectReferral,
        'subjectId': referralSubjectId(_form, today: almatyTodayString()),
        'recommended': {'moCode': referralRecommended(prediction, _alternatives, _form.moCode)},
        'chosen': {'moCode': _chosen},
        'reason': _reason.text.trim(),
      }, idempotencyKey: key);
      if (!mounted) return;
      setState(() => _recorded = id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${s.assistDecisionRecorded}\n${s.assistToJournal}')));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _reasonError = apiFieldError(e, 'reason'));
      await showApiError(context, e, fields: const ['reason']);
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  // ---------- экран ----------

  String? _regionName(String? kato) => _regions.where((r) => r.kato == kato).map((r) => r.name).firstOrNull;

  String _orgName(String code) =>
      [..._organizations, ..._referring].where((o) => o.moCode == code).map((o) => o.name).firstOrNull ?? code;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final p = _prediction;
    final locked = _recorded != null || _recording;
    final orgShort = shortOrgName(_orgName(_form.moCode));
    final profileName = _profiles.where((x) => x.code == _form.profileCode).map((x) => x.name).firstOrNull;
    final purposeIndex = ReferralContract.purposes.indexOf(_form.purpose);
    final chosenAlternative = _alternatives.where((a) => a.moCode == _chosen).firstOrNull;
    return PageScaffold(
      title: s.assistTitle,
      bottom: p == null
          ? null
          : FilledButton(
              onPressed: locked || _chosen.isEmpty ? null : _record,
              child: _recording
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_recorded != null ? s.assistRecorded : s.assistSaveChoice),
            ),
      children: [
        Text(p == null ? s.assistLead : '${s.assistLead} · ${s.assistAsOf(p.model.trainedThrough)}', style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) ErrorBox(error: _error, onRetry: _regions.isEmpty || _profiles.isEmpty ? _load : _predict),
        ReferralParamsCard(
          form: _form,
          regionName: _regionName(_form.regionKato),
          profileName: profileName,
          referringName: _form.referringMoCode.isEmpty ? null : shortOrgName(_orgName(_form.referringMoCode)),
          icd: _icd,
          registrationDate: _date,
          profileError: _profileError,
          dateError: _dateError,
          profilesReady: _profiles.isNotEmpty,
          onRegion: () => _pick(s.assistRegion, [for (final r in _regions) PickerItem(r.kato, r.name)], _form.regionKato,
              (v) => _form.copyWith(regionKato: v, moCode: '', referringMoCode: ''), organizations: true, referring: true),
          onProfile: () => _pick(s.profileLabel, [for (final x in _profiles) PickerItem(x.code, x.name)], _form.profileCode, (v) => _form.copyWith(profileCode: v),
              organizations: true),
          onPurpose: () => _pick(s.assistPurpose, [for (final (i, v) in ReferralContract.purposes.indexed) PickerItem(v, s.purposeLabels[i])], _form.purpose,
              (v) => _form.copyWith(purpose: v), search: false),
          onTerritory: () => _pick(s.assistTerritory, [for (final (i, v) in ReferralContract.territorial.indexed) PickerItem(v, s.territorialLabels[i])],
              _form.territorial, (v) => _form.copyWith(territorial: v), search: false),
          onReferring: () => _pick(
            s.assistReferringOrg,
            [PickerItem('', s.assistNotSpecified), for (final o in _referring) PickerItem(o.moCode, shortOrgName(o.name), detail: o.moCode)],
            _form.referringMoCode,
            (v) => _form.copyWith(referringMoCode: v),
          ),
          onNeighbors: (v) => _change(_form.copyWith(includeNeighbors: v)),
          onTextDone: _textDone,
        ),
        ReferralWhereCard(
          form: _form,
          prediction: p,
          alternatives: _alternatives,
          chosen: _chosen,
          orgName: _orgName(_form.moCode),
          regionName: _regionName,
          canPick: _organizations.isNotEmpty,
          locked: locked,
          onPickOrg: () => _pick(s.assistPickOrg, [for (final o in _organizations) PickerItem(o.moCode, shortOrgName(o.name), detail: o.moCode)], _form.moCode,
              (v) => _form.copyWith(moCode: v)),
          onChangeOrg: () => _change(_form.copyWith(moCode: '')),
          onChoose: (code) => setState(() => _chosen = code),
        ),
        ReferralForecastCard(
          busy: _busy,
          prediction: p,
          orgName: orgShort,
          factors: p == null ? const [] : referralFactors(s, p, profileName: profileName, referringSet: _form.referringMoCode.isNotEmpty),
        ),
        if (p != null)
          ReferralDecisionCard(
            where: chosenAlternative == null ? orgShort : shortOrgName(chosenAlternative.name),
            insteadOf: chosenAlternative == null ? null : orgShort,
            what: [profileName ?? _form.profileCode, if (purposeIndex >= 0) s.purposeLabels[purposeIndex], if (_form.icd10.isNotEmpty) _form.icd10].join(' · '),
            reason: _reason,
            reasonError: _reasonError,
            locked: locked,
            recorded: _recorded != null,
            onJournal: () => context.go('/doctor/decisions'),
            onWorklist: () => context.go('/doctor/patients'),
          ),
      ],
    );
  }
}

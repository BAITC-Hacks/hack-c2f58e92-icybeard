import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/hero_number.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/wait_bars.dart';

/// «Сколько ждут» по доске M-Wait: два soft-селектора (регион, профиль), hero-карточка «≈ N дн. · половина
/// госпитализированных ждёт не дольше · 9 из 10 — до M дн. · ориентир МЗ РК», карточка «Где быстрее» с барами
/// (ширина пропорциональна p50, коралловый бар — у организации, которую предложил врач) и CTA внизу «Попросить
/// рассмотреть …». Результат считается при выборе обоих селекторов — без кнопки.
class WaitScreen extends StatefulWidget {
  const WaitScreen({super.key, this.regionKato, this.profileCode});

  final String? regionKato;
  final String? profileCode;

  @override
  State<WaitScreen> createState() => _WaitScreenState();
}

class _WaitData {
  const _WaitData(this.prediction, this.alternatives, this.index);

  final PredictResponse prediction;
  final List<Alternative> alternatives;
  final IndexItem? index;
}

class _WaitScreenState extends State<WaitScreen> {
  List<Region> _regions = const [];
  List<BedProfile> _profiles = const [];
  RouteBenchmark? _target;
  String? _region;
  String? _profile;
  LoadState<_WaitData>? _state;
  Object? _refdataError;

  /// Маршрут гражданина — чтобы подсветить организацию, которую предложил врач, и не дублировать открытый запрос.
  PatientRoute? _route;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _region = widget.regionKato ?? session.region;
    _profile = widget.profileCode ?? session.lastProfile;
    _loadRefdata();
    if (session.isCitizen) {
      _loadRoute();
    }
  }

  Future<void> _loadRoute() async {
    final session = context.read<Session>();
    try {
      final route = await session.api.myRoute(regionKato: session.regionFromAccount ? null : session.region);
      if (mounted) {
        setState(() => _route = route);
      }
    } catch (_) {
      // без маршрута экран остаётся публичным справочником
    }
  }

  Future<void> _loadRefdata() async {
    final api = context.read<Session>().api;
    try {
      final results = await Future.wait<Object>([api.regions(), api.profiles(), api.routeStandard()]);
      if (!mounted) {
        return;
      }
      setState(() {
        _regions = results[0] as List<Region>;
        _profiles = results[1] as List<BedProfile>;
        _target = (results[2] as RouteStandard).target;
        _refdataError = null;
      });
      if (_profile != null && _profiles.any((p) => p.code == _profile)) {
        await _run();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  Future<void> _run() async {
    final session = context.read<Session>();
    final region = _region;
    final profile = _profile;
    if (region == null || profile == null) {
      return;
    }
    setState(() => _state = const Loading());
    try {
      final body = {'regionKato': region, 'profileCode': profile};
      final results = await Future.wait<Object>([session.api.predict(body), session.api.alternatives(body), session.api.index(profileCode: profile)]);
      await session.rememberProfile(profile);
      if (!session.regionFromAccount) {
        await session.setRegion(region);
      }
      if (mounted) {
        setState(() => _state = Loaded(_WaitData(
              results[0] as PredictResponse,
              results[1] as List<Alternative>,
              (results[2] as List<IndexItem>).where((i) => i.regionKato == region).firstOrNull,
            )));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _pickRegion() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.regionLabel,
      items: [for (final r in _regions) PickerItem(r.kato, r.name)],
      selected: _region,
    );
    if (chosen == null || !mounted) {
      return;
    }
    setState(() => _region = chosen);
    await _run();
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
    setState(() => _profile = chosen);
    await _run();
  }

  /// Вошедший гражданин просит врача рассмотреть организацию: сигнал по своему маршруту, комментарий необязателен.
  Future<void> _request(Alternative alternative) async {
    final s = S.at(context);
    final session = context.read<Session>();
    final comment = await RedirectReasonDialog.show(
      context,
      organization: alternative.name,
      subtitle: s.requestTitle(''),
      label: s.requestCommentLabel,
      confirmLabel: s.requestSend,
      optional: true,
    );
    if (comment == null || !mounted) {
      return;
    }
    try {
      await session.api.sendRouteSignal(
        RouteCodes.requestRedirect,
        toMoCode: alternative.moCode,
        comment: comment,
        idempotencyKey: newIdempotencyKey(),
        regionKato: session.regionFromAccount ? null : session.region,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.requestSent)));
        await _loadRoute();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    }
  }

  /// CTA: предложенная врачом организация, если она в списке, иначе самая быстрая; пока запрос открыт — кнопки нет.
  Alternative? _ctaTarget(_WaitData data) {
    if (!context.read<Session>().isCitizen || data.alternatives.isEmpty || _route?.openRequest != null) {
      return null;
    }
    final proposed = _route?.latestRedirect?.toMoCode;
    return data.alternatives.where((a) => a.moCode == proposed).firstOrNull ?? data.alternatives.first;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final state = _state;
    final data = switch (state) { Loaded<_WaitData>(:final data) => data, _ => null };
    final cta = data == null ? null : _ctaTarget(data);
    final regionName = _regions.where((r) => r.kato == _region).map((r) => r.name).firstOrNull ?? _region;
    final profileName = _profiles.where((p) => p.code == _profile).map((p) => p.name).firstOrNull;
    return PageScaffold(
      title: s.waitTitle,
      gap: AppSpacing.sm,
      bottom: cta == null ? null : FilledButton(onPressed: () => _request(cta), child: Text(s.requestConsiderName(shortOrgName(cta.name)))),
      children: [
        PickerRow(label: s.regionLabel, value: regionName, placeholder: s.choosePlaceholder, onTap: _pickRegion, enabled: _regions.isNotEmpty),
        PickerRow(label: s.profileShort, value: profileName, placeholder: s.choosePlaceholder, onTap: _pickProfile, enabled: _profiles.isNotEmpty),
        if (_refdataError != null) ErrorBox(error: _refdataError, onRetry: _loadRefdata),
        const SizedBox(height: AppSpacing.xs),
        if (state == null)
          EmptyState(icon: Icons.tune, title: s.chooseRegionProfile, body: s.chooseRegionProfileBody)
        else
          switch (state) {
            Loading<_WaitData>() => const Column(children: [CardSkeleton(height: 200), SizedBox(height: AppSpacing.md), CardSkeleton(height: 220)]),
            Failed<_WaitData>(:final error) => _noData(error)
                ? EmptyState(
                    icon: Icons.search_off,
                    title: s.noDataForProfile,
                    body: s.noDataForProfileBody,
                    action: OutlinedButton(onPressed: _pickProfile, child: Text(s.changeProfile)),
                  )
                : ErrorBox(error: error, onRetry: _run),
            Loaded<_WaitData>(:final data) => _Result(
                data: data,
                target: _target,
                proposedMoCode: _route?.latestRedirect?.toMoCode,
                onRequest: session.isCitizen && _route?.openRequest == null ? _request : null,
              ),
          },
      ],
    );
  }

  static bool _noData(Object error) => error is ApiException && (error.status == 404 || error.status == 422);
}

class _Result extends StatelessWidget {
  const _Result({required this.data, required this.target, this.proposedMoCode, this.onRequest});

  final _WaitData data;
  final RouteBenchmark? target;
  final String? proposedMoCode;
  final void Function(Alternative alternative)? onRequest;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final p = data.prediction;
    final index = data.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: HeroNumber(
            label: s.waitLabel,
            origin: Origin.ml,
            value: '≈ ${days(p.p50Days)}',
            unit: s.daysUnit,
            caption: s.halfHospitalized,
            line: [s.nineOfTenShort(days(p.p90Days)), if (target != null) s.benchmarkShort(days(target!.value))].join('\n'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(s.fasterSection, style: theme.textTheme.titleMedium)),
                  const OriginTag(Origin.ml),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (data.alternatives.isEmpty)
                Text(s.noOrgsForProfile, style: theme.textTheme.bodySmall)
              else
                WaitBars(alternatives: data.alternatives, proposedMoCode: proposedMoCode, onTap: onRequest),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CollapsibleSection(
          title: s.howCounted,
          origin: Origin.formula,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(index == null ? s.indexUnavailable : s.indexShown(index.indexValue.toStringAsFixed(1), index.rank), style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(s.nhsNote, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              Text(s.modelTrained(p.model.name, p.model.version, p.model.trainedThrough), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
            ],
          ),
        ),
      ],
    );
  }
}

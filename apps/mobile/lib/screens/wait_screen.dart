import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/alternative_row.dart';
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

/// «Сколько ждут»: две строки-селектора (регион, профиль) открывают листы с поиском, результат считается при
/// выборе обоих — без кнопки. Главное число «≈ N дней — половина ждёт не дольше» [ML], ориентир МЗ РК [формула],
/// «Где быстрее» с чипом риска и «Попросить» для вошедшего гражданина, «Как считается» свёрнуто.
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

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _region = widget.regionKato ?? session.region;
    _profile = widget.profileCode ?? session.lastProfile;
    _loadRefdata();
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final state = _state;
    final regionName = _regions.where((r) => r.kato == _region).map((r) => r.name).firstOrNull ?? _region;
    final profileName = _profiles.where((p) => p.code == _profile).map((p) => p.name).firstOrNull;
    return PageScaffold(
      title: s.waitTitle,
      children: [
        PickerRow(label: s.regionLabel, value: regionName, placeholder: s.choosePlaceholder, onTap: _pickRegion, enabled: _regions.isNotEmpty),
        const SizedBox(height: AppSpacing.sm),
        PickerRow(label: s.profileShort, value: profileName, placeholder: s.choosePlaceholder, onTap: _pickProfile, enabled: _profiles.isNotEmpty),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _loadRefdata)],
        const SizedBox(height: AppSpacing.lg),
        if (state == null)
          EmptyState(icon: Icons.tune, title: s.chooseRegionProfile, body: s.chooseRegionProfileBody)
        else
          switch (state) {
            Loading<_WaitData>() => const Column(
                children: [
                  Skeleton(height: 44, width: 160, radius: AppRadius.sm),
                  SizedBox(height: AppSpacing.md),
                  Skeleton(height: 16),
                  SizedBox(height: AppSpacing.xl),
                  ListSkeleton(count: 3),
                ],
              ),
            Failed<_WaitData>(:final error) => _noData(error)
                ? EmptyState(
                    icon: Icons.search_off,
                    title: s.noDataForProfile,
                    body: s.noDataForProfileBody,
                    action: OutlinedButton(onPressed: _pickProfile, child: Text(s.changeProfile)),
                  )
                : ErrorBox(error: error, onRetry: _run),
            Loaded<_WaitData>(:final data) => _Result(data: data, target: _target, onRequest: session.isCitizen ? _request : null),
          },
      ],
    );
  }

  static bool _noData(Object error) => error is ApiException && (error.status == 404 || error.status == 422);
}

class _Result extends StatelessWidget {
  const _Result({required this.data, required this.target, this.onRequest});

  final _WaitData data;
  final RouteBenchmark? target;
  final void Function(Alternative alternative)? onRequest;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final p = data.prediction;
    final index = data.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroNumber(
          value: '≈ ${days(p.p50Days)}',
          unit: s.daysWord,
          caption: s.halfCaption,
          line: s.heroLine(days(p.p90Days), pct(p.pWithin30Days)),
          origin: Origin.ml,
        ),
        if (target != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: Text(s.benchmarkShort(days(target!.value)), style: theme.textTheme.bodyMedium?.merge(AppType.numeric))),
              const SizedBox(width: AppSpacing.sm),
              const OriginTag(Origin.formula),
            ],
          ),
        ],
        SectionTitle(s.fasterSection),
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
                    trailing: onRequest == null ? null : TextButton(onPressed: () => onRequest!(a), child: Text(s.requestConsider)),
                  ),
                ],
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
              Text(s.modelTrained(p.model.name, p.model.version, p.model.trainedThrough), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/citizen_route_controller.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/citizen/citizen_action_button.dart';
import '../widgets/citizen/citizen_actions.dart';
import '../widgets/citizen/citizen_route_rules.dart';
import '../widgets/citizen/route_action_zone.dart';
import '../widgets/citizen/route_head_card.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Главная гражданина (§13.2, «взглянуть и ответить»): сначала запрос записи приёма и карточка состояния маршрута
/// с рабочими кнопками — та же, что в «Моём пути» (решение Q2), или ответ врача; затем сводка «Ваша больница» с
/// тремя фактами, полоской этапов (только узлы, Q3), строкой «Вы ещё ждёте? — Да, жду» (если сервер её ждёт и
/// разрешает) и ссылкой «Открыть маршрут»; плитки «Сколько ждут» · «Лекарства» · «Вакцинация» и подпись о данных.
/// Маршрут — из общего [CitizenRouteController] (одна копия на главную и «Мой путь»). Маршрута в регионе нет —
/// «Маршрут не найден…», сбой — плашка ошибки с «Повторить»; плитки работают в любом случае.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // после кадра: загрузка сразу оповещает слушателей, а во время построения дерева это запрещено
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CitizenRouteController?>()?.ensureLoaded();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final controller = context.watch<CitizenRouteController?>();
    final state = controller?.state ?? const Loading<PatientRoute>();
    final seen = context.select<Session, String?>((session) => session.seenDecisionId);
    return PageScaffold(
      title: s.navHome,
      hero: true,
      leading: const HomeMarkAnchor(),
      actions: const [LanguageButton()],
      onRefresh: controller?.load,
      children: [
        ...switch (state) {
          Loading<PatientRoute>() => const [CardSkeleton(height: 260)],
          Failed<PatientRoute>(error: ApiException(isNotFound: true)) => [
              EmptyState(
                icon: Icons.map_outlined,
                title: s.myRouteNotFound,
                compact: true,
                action: ArrowLink(s.waitTitle, onTap: () => context.go('/home/wait')),
              ),
            ],
          Failed<PatientRoute>(:final error) => [ErrorBox(error: error, onRetry: controller?.load)],
          Loaded<PatientRoute>(data: final route) => [
              ...routeActionCards(context, route, validation: false),
              RouteHeadCard(
                route: route,
                compact: true,
                onOpen: () => context.go('/home/route'),
                footer: actionCardOf(route, seenDecisionId: seen) == ActionCard.validation ? const _ValidationLine() : null,
              ),
            ],
        },
        const _Tiles(),
        Text(s.dataNote, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// «Вы ещё ждёте? — Да, жду» строкой в сводке — там, где «Моём пути» стоит карточка вопроса (сервер ждёт
/// подтверждения и разрешает `still_waiting`, другой карточки действия нет).
class _ValidationLine extends StatelessWidget {
  const _ValidationLine();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Row(
      children: [
        Expanded(child: Text(s.validationShort, style: Theme.of(context).textTheme.titleSmall)),
        CitizenActionButton(label: s.validationStill, kind: CitizenButtonKind.link, onPressed: () => stillWaiting(context)),
      ],
    );
  }
}

/// Три плитки: «Сколько ждут», «Лекарства» (при `medicines.check`), «Вакцинация» — белые, radius 18, иконка
/// в круге 36 surface-sunken/accent и подпись 13.5/700 (доска m-home-new `.tile`).
class _Tiles extends StatelessWidget {
  const _Tiles();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final medicines = context.select<Session, bool>((x) => x.can(Perm.medicinesCheck));
    final tiles = [
      _Tile(icon: Icons.schedule_outlined, label: s.homeTileWait, onTap: () => context.go('/home/wait')),
      if (medicines) _Tile(icon: Icons.medication_outlined, label: s.homeTileMedicines, onTap: () => context.go('/home/medicines')),
      _Tile(icon: Icons.vaccines_outlined, label: s.homeTileVaccination, onTap: () => context.go('/home/vaccination')),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: tile),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      onTap: onTap,
      semanticsLabel: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceSunken),
            child: Icon(icon, color: colors.accent, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: Theme.of(context).textTheme.rowDetail.copyWith(fontWeight: FontWeight.w700, color: colors.ink, height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

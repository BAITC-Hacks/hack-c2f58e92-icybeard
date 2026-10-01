import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/citizen_route_controller.dart';
import '../state/load_state.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_state_view.dart';
import '../widgets/route_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// «Мой путь» гражданина (`/home/route`, RouteCitizenView.vue в телефонной раскладке §13.2). Маршрут и запросы
/// записи приёма — из общего [CitizenRouteController] (тот же, что у главной: действие на одном экране сразу видно
/// на другом); pull-to-refresh перечитывает их. Маршрута в регионе нет (404) — «Маршрут не найден…» со ссылкой на
/// «Сколько ждут»; другие ошибки — состояние ошибки с «Повторить». Без контроллера в дереве (экран вне `AppScope`)
/// показывается скелетон.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
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
    return PageScaffold(
      title: s.routeTitle,
      onRefresh: controller?.load,
      children: [
        if (state case Failed<PatientRoute>(error: ApiException(isNotFound: true)))
          EmptyState(
            icon: Icons.map_outlined,
            title: s.myRouteNotFound,
            action: ArrowLink(s.waitTitle, onTap: () => context.go('/home/wait')),
          )
        else
          LoadStateView<PatientRoute>(
            state: state,
            onRetry: controller?.load,
            skeleton: const Column(children: [CardSkeleton(height: 260), SizedBox(height: AppSpacing.md), CardSkeleton(height: 200)]),
            builder: (_, route) => RouteView(route: route, leaflets: controller?.leaflets ?? const []),
          ),
      ],
    );
  }
}

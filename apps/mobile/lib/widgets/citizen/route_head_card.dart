import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../inline_disclosure.dart';
import '../org_name.dart';
import '../route/stage_list.dart';
import '../route/stage_strip.dart';

/// Шапка маршрута «Ваша больница» (RouteCitizenView.vue, блок B): короткое имя больницы (тап — полное юридическое
/// имя; после подтверждённого перевода — принимающая), профиль, три факта «В листе ожидания с» · «Вы ждёте» ·
/// «Данные на», под чертой «Этапы маршрута» и полоска узлов (решения Q3 и 9). В «Моём пути» под полоской —
/// раскрывашка «{n} этапов · {m} пройдено» с вертикальным списком этапов (заголовки сервера, даты, нормы): открыта,
/// когда под шапкой нет карточки действия ([stagesExpanded]), и закрыта, когда есть, — иначе шесть этапов с нормами
/// уводят кнопки согласия за нижний край телефона. На главной ([compact]) — подпись с числом этапов, [footer]
/// (строка «Вы ещё ждёте?») и ссылка «Открыть маршрут», вся карточка ведёт в маршрут ([onOpen]).
class RouteHeadCard extends StatelessWidget {
  const RouteHeadCard({super.key, required this.route, this.compact = false, this.stagesExpanded = true, this.onOpen, this.footer});

  final PatientRoute route;
  final bool compact;

  /// Список этапов «Моего пути» открыт при первом показе.
  final bool stagesExpanded;
  final VoidCallback? onOpen;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final org = route.organization;
    final done = route.timeline.where((stage) => stage.status == RouteCodes.done).length;
    final count = s.routeStagesCount(route.timeline.length, done);
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(s.myHospital),
          const SizedBox(height: AppSpacing.xs),
          OrgName(org.moName, style: theme.textTheme.titleLarge, maxLines: 2),
          if (org.profileName.isNotEmpty) Text(org.profileName, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              _Fact(label: s.myFactSince, value: routeDate(route.dates.registeredAt)),
              _Fact(label: s.myFactWaiting, value: s.myFactDays(route.daysWaiting)),
              _Fact(label: s.myFactAsOf, value: routeDate(route.asOf)),
            ],
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.md), child: Divider(height: 1, color: colors.hairline)),
          CardLabel(s.routeStagesTitle, trailing: compact ? Text(count, style: theme.textTheme.labelSmall) : null),
          const SizedBox(height: AppSpacing.md),
          StageStrip(stages: route.timeline),
          if (!compact)
            InlineDisclosure(
              title: count,
              initiallyExpanded: stagesExpanded,
              child: Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: StageList(stages: route.timeline)),
            ),
          if (footer != null) ...[const SizedBox(height: AppSpacing.md), footer!],
          if (compact) ...[
            const SizedBox(height: AppSpacing.md),
            Align(alignment: AlignmentDirectional.centerEnd, child: ArrowLink(s.openRoute)),
          ],
        ],
      ),
    );
  }
}

/// Факт шапки: подпись 12 над значением 14.5/600 табличными цифрами.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.row.merge(AppType.numeric)),
      ],
    );
  }
}

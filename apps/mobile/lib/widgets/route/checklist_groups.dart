import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';

/// Группа анализов одного статуса: `expired | expiring | valid` и её пункты в серверном порядке.
typedef ChecklistGroup = ({String status, List<ChecklistItem> items});

/// Порядок групп, как в вебе: сначала то, что надо пересдать, затем то, что скоро истечёт, затем действующие.
const checklistGroupOrder = [RouteCodes.expired, RouteCodes.expiring, RouteCodes.valid];

/// Пункты чек-листа → непустые группы в порядке [checklistGroupOrder]. Пункт с незнакомым статусом в группы не
/// попадает (как в RouteChecklist.vue: сервер считает статус только по датам и шлёт одно из трёх). Чистая
/// функция: вход не меняется, списки групп неизменяемые.
List<ChecklistGroup> groupChecklist(List<ChecklistItem> items) => [
      for (final status in checklistGroupOrder)
        if (items.any((item) => item.status == status)) (status: status, items: List.unmodifiable(items.where((item) => item.status == status))),
    ];

/// Анализы по Стандарту группами (RouteChecklist.vue, §2.11): блок группы — рамка border-soft radius 12 с цветной
/// полосой 4 слева (истёк — danger, скоро истекут — warn-strong, действуют — ok), шапка на тонированном фоне со
/// значком, заголовком в цвете группы, счётчиком «анализов: N» и пояснением «что это значит»; пункты — название,
/// «действителен {срок} после сдачи» и прямая дата «истёк {дата}» (красным) или «действует до {дата}», на телефоне
/// одна под другой. Внизу — источник перечня из [standard] (без него сноски нет). Пустой список — «Данных нет».
/// Это логистика документов, а не медицинская интерпретация. Заголовок раздела «Анализы» и итог — у экрана.
class ChecklistGroups extends StatelessWidget {
  const ChecklistGroups({super.key, required this.items, this.standard});

  /// `PatientRoute.checklist`.
  final List<ChecklistItem> items;

  /// `PatientRoute.standard` — источник и дата перечня для сноски.
  final RouteStandardRef? standard;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final groups = groupChecklist(items);
    final source = standard;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty) Text(s.routeNoData, style: muted),
        for (final (i, group) in groups.indexed) ...[if (i > 0) const SizedBox(height: AppSpacing.md), _ChecklistBlock(group: group)],
        if (source != null && source.source.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(s.routeChecklistNote(source.source, dateShort(source.sourceDate)), style: muted),
        ],
      ],
    );
  }
}

/// Цвета и значок группы: полоса, фон шапки, заголовок и значок.
({Color bar, Color headBg, Color fg, IconData icon}) _groupStyle(String status, ColorTokens colors, AppTones tones) => switch (status) {
      RouteCodes.expired => (bar: tones.danger.fg, headBg: tones.danger.bg, fg: tones.danger.fg, icon: Icons.error_outline),
      RouteCodes.expiring => (bar: colors.warnStrong, headBg: tones.warn.bg, fg: tones.warn.fg, icon: Icons.schedule),
      _ => (bar: tones.ok.fg, headBg: tones.ok.bg, fg: tones.ok.fg, icon: Icons.check_circle_outline),
    };

class _ChecklistBlock extends StatelessWidget {
  const _ChecklistBlock({required this.group});

  final ChecklistGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final style = _groupStyle(group.status, colors, AppTones.of(context));
    return Container(
      decoration: BoxDecoration(color: colors.card, border: Border.all(color: colors.borderSoft), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - 1),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ChecklistHead(group: group, headBg: style.headBg, fg: style.fg, icon: style.icon),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final (i, item) in group.items.indexed) _ChecklistItemRow(item: item, last: i == group.items.length - 1)],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(key: ValueKey('checklist-bar-${group.status}'), color: style.bar)),
          ],
        ),
      ),
    );
  }
}

class _ChecklistHead extends StatelessWidget {
  const _ChecklistHead({required this.group, required this.headBg, required this.fg, required this.icon});

  final ChecklistGroup group;
  final Color headBg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final hint = s.routeChecklistGroupHint(group.status);
    return Container(
      key: ValueKey('checklist-head-${group.status}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: headBg, border: Border(bottom: BorderSide(color: colors.borderSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: fg)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(s.routeChecklistGroupTitle(group.status), style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                    Text(s.routeChecklistCount(group.items.length), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700).merge(AppType.numeric)),
                  ],
                ),
                if (hint.isNotEmpty) ...[const SizedBox(height: 2), Text(hint, style: theme.textTheme.bodyMedium)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItemRow extends StatelessWidget {
  const _ChecklistItemRow({required this.item, required this.last});

  final ChecklistItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final expired = item.status == RouteCodes.expired;
    final date = dateShort(item.validUntil);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: theme.textTheme.row),
          Text(s.routeChecklistValidity(item.validityLabel), style: theme.textTheme.rowDetail.copyWith(color: colors.muted)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            expired ? s.routeChecklistExpiredOn(date) : s.routeChecklistValidTill(date),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: expired ? AppTones.of(context).danger.fg : colors.ink).merge(AppType.numeric),
          ),
        ],
      ),
    );
  }
}

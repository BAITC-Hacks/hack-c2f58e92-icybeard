import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../circle_button.dart';
import '../picker_sheet.dart';
import 'worklist_logic.dart';

/// Панель над списком пациентов (веб `list-toolbar`): селектор «Флаги» — лист из девяти пунктов со счётчиками
/// (вместо KPI-плиток, Q-3), под ним поиск по номеру пациента, круглая кнопка сортировки — лист из пяти колонок
/// веба, у текущей стрелка направления (повторный выбор колонки меняет направление), и кнопка ассистента нового
/// направления (если передан [onAssistant]). Ассистент здесь, а не в шапке: в шапке рядом с колокольчиком казахский
/// заголовок при крупном шрифте на узком телефоне переносился посреди слова.
class WorklistToolbar extends StatelessWidget {
  const WorklistToolbar({
    super.key,
    required this.counts,
    required this.filter,
    required this.onFilter,
    required this.sort,
    required this.onSort,
    required this.query,
    required this.onQuery,
    this.onAssistant,
  });

  /// Счётчики [worklistCounts] по всему загруженному списку.
  final Map<String, int> counts;
  final String filter;
  final ValueChanged<String> onFilter;
  final WorklistSort sort;
  final ValueChanged<WorklistSort> onSort;

  /// Поле поиска; владелец — экран.
  final TextEditingController query;
  final VoidCallback onQuery;

  /// Ассистент направления (`referral.assist`); null — кнопки нет.
  final VoidCallback? onAssistant;

  Future<void> _pickFilter(BuildContext context) async {
    final s = S.at(context);
    final picked = await PickerSheet.show<String>(
      context,
      title: s.worklistFlags,
      search: false,
      selected: filter,
      items: [
        for (final code in [worklistFilterAll, ...RouteCodes.riskFlags]) PickerItem(code, s.worklistFilterOption(code, counts[code] ?? 0)),
      ],
    );
    if (picked != null) {
      onFilter(picked);
    }
  }

  Future<void> _pickSort(BuildContext context) async {
    final s = S.at(context);
    final picked = await PickerSheet.show<WorklistSortKey>(
      context,
      title: s.worklistSortTitle,
      search: false,
      selected: sort.key,
      items: [for (final key in WorklistSortKey.values) PickerItem(key, key == sort.key ? worklistSortLabel(s, sort) : worklistColumnLabel(s, key))],
    );
    if (picked != null) {
      onSort(sort.tap(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerRow(label: s.worklistFlags, value: s.worklistFilterOption(filter, counts[filter] ?? 0), onTap: () => _pickFilter(context)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: query,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => onQuery(),
                decoration: InputDecoration(hintText: s.worklistSearch, prefixIcon: const Icon(Icons.search), isDense: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            CircleIconButton(icon: Icons.swap_vert, label: s.worklistSortTitle, onTap: () => _pickSort(context)),
            if (onAssistant != null) ...[
              const SizedBox(width: AppSpacing.sm),
              CircleIconButton(icon: Icons.post_add, label: s.worklistAssistant, onTap: onAssistant),
            ],
          ],
        ),
      ],
    );
  }
}

/// Подпись колонки сортировки — заголовки колонок веба («Пациент», «Профиль койки», «Организация», «Ждёт, дн.»,
/// «Приоритет»).
String worklistColumnLabel(S s, WorklistSortKey key) => switch (key) {
      WorklistSortKey.patient => s.worklistColumnPatient,
      WorklistSortKey.profile => s.profileLabel,
      WorklistSortKey.organization => s.organizationLabel,
      WorklistSortKey.days => s.worklistColumnDays,
      WorklistSortKey.priority => s.worklistColumnPriority,
    };

/// Текущая сортировка со стрелкой направления: «Приоритет ↓».
String worklistSortLabel(S s, WorklistSort sort) => '${worklistColumnLabel(s, sort.key)} ${sort.descending ? '↓' : '↑'}';

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../picker_sheet.dart';
import '../pill_filter.dart';
import 'incoming_filter.dart';

/// Значение «все этапы» в листе выбора этапа.
const _allStages = 'all';

/// Ряд фильтров входящих (веб — тулбар таблицы): пилюля этапа «Все этапы · 8 ⌄» открывает лист со счётчиками по
/// этапам, пилюля-переключатель «Только тяжёлые · N». При крупном шрифте пилюли переносятся строкой ниже, а не
/// вылезают за край. Поиск — кнопка в шапке экрана. Фильтр неизменяемый: каждое изменение — новый [IncomingFilter].
class IncomingFilterBar extends StatelessWidget {
  const IncomingFilterBar({super.key, required this.items, required this.filter, required this.onChanged});

  /// Весь загруженный список — по нему считаются числа.
  final List<IncomingReferral> items;
  final IncomingFilter filter;
  final ValueChanged<IncomingFilter> onChanged;

  /// Лист этапов со счётчиками — общий [PickerSheet] без поиска, на корневом навигаторе (над пилюлей вкладок).
  Future<void> _pickStage(BuildContext context) async {
    final s = S.at(context);
    final counts = incomingStageCounts(items);
    final options = [
      PickerItem(_allStages, '${s.incomingStageLabel(_allStages)} · ${items.length}'),
      for (final stage in IncomingStage.values) PickerItem(stage.name, '${s.incomingStageLabel(stage.name)} · ${counts[stage]}'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PickerSheet<String>(title: s.incomingStageField, items: options, selected: filter.stage?.name ?? _allStages, search: false),
    );
    if (picked != null) {
      onChanged(filter.withStage(picked == _allStages ? null : IncomingStage.values.byName(picked)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final stage = filter.stage;
    final stageCount = stage == null ? items.length : incomingStageCounts(items)[stage]!;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _SelectPill(
          key: const ValueKey('incoming-stage'),
          label: '${s.incomingStageLabel(stage?.name ?? _allStages)} · $stageCount',
          semanticsLabel: s.incomingStageField,
          selected: stage != null,
          onTap: () => _pickStage(context),
        ),
        Pill(
          key: const ValueKey('incoming-severe'),
          label: '${s.incomingSevereOnly} · ${incomingSevereCount(items)}',
          selected: filter.severeOnly,
          onTap: () => onChanged(filter.withSevereOnly(!filter.severeOnly)),
        ),
      ],
    );
  }
}

/// Пилюля-выбор 44 px в стиле [Pill] со стрелкой «⌄»: выбранный этап — accent-soft, «все» — surface-sunken.
class _SelectPill extends StatelessWidget {
  const _SelectPill({super.key, required this.label, required this.semanticsLabel, required this.selected, required this.onTap});

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final theme = Theme.of(context);
    final fg = selected ? colors.accentHover : colors.muted;
    return Semantics(
      button: true,
      label: '$semanticsLabel: $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.accentSoft : colors.surfaceSunken,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.compact),
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg), maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.expand_more, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

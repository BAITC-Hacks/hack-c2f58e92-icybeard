import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import '../route/priority_badge.dart';
import '../status_chip.dart';
import 'worklist_logic.dart';

/// Строка рабочего списка на телефоне (одна колонка вместо таблицы веба): слева бейдж приоритета 0…10, справа номер
/// пациента и главный чип статуса (переносится под номер, если не помещается), «ждёт N дн. · больница», профиль
/// койки, открытый запрос пациента с комментарием (строка подсвечена, как в вебе) и «Следующий шаг: …». Кнопок в
/// строке нет (Q-16): тап по всей строке открывает маршрут пациента (Q-4). Для чтения с экрана — одна кнопка.
class WorklistRow extends StatelessWidget {
  const WorklistRow({super.key, required this.item, required this.onOpen, this.profileName, this.last = false});

  final WorklistItem item;
  final VoidCallback onOpen;

  /// Название профиля койки из справочника; null — справочник не загрузился, строка без профиля.
  final String? profileName;

  /// Последняя строка — без линии снизу.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final chip = worklistChip(s, item);
    final signal = item.patientSignal;
    final next = s.worklistNextShort(item.nextActionCode, fallback: item.nextAction);
    final detail = theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.row),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: signal == null ? null : colors.accentSubtle,
              border: last ? null : Border(bottom: BorderSide(color: colors.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PriorityBadge(item.priority),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(item.patientRef, style: theme.textTheme.rowStrong.merge(AppType.numeric)),
                          StatusChip(chip.label, tone: chip.tone),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${s.waitingFor(item.daysWaiting)} · ${shortOrgName(item.moName)}', style: detail, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (profileName != null && profileName!.isNotEmpty)
                        Text(profileName!, style: detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (signal != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(_signalLine(s, signal), style: theme.textTheme.row, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                      if (next.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text('${s.nextActionLabel}: $next', style: detail, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Icon(Icons.chevron_right, size: 20, color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Пациент просит рассмотреть: Достар Мед — «живу рядом»» — запрос пациента и его комментарий (веб `route.patientSignal`).
String _signalLine(S s, PatientSignal signal) {
  final text = s.worklistSignal(signal.kind, name: shortOrgName(signal.toMoName ?? signal.toMoCode));
  final comment = signal.comment?.trim() ?? '';
  return comment.isEmpty ? text : '$text — «$comment»';
}

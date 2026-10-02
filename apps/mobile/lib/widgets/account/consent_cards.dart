import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../state/load_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../picker_sheet.dart';
import '../skeleton.dart';
import '../state_view.dart';
import '../status_chip.dart';

/// Карточки экрана «Данные и согласия» (веб `ConsentsView.vue`, F16): согласия, журнал доступа к моим данным, «Мои
/// данные». Ошибка загрузки карточки — компактное состояние W-States с «Повторить» вместо неё, пока грузится —
/// карточка со строками-скелетонами.

/// Отступы карточки со списком строк: снизу меньше — у последней строки свой отступ.
const _listPadding = EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs);

/// Карточка «Согласия»: строки с переключателями, обязательное — с замком и заблокировано. Пока одно согласие
/// сохраняется ([pending] не null), заблокированы все переключатели.
class ConsentsCard extends StatelessWidget {
  const ConsentsCard({super.key, required this.state, required this.onRetry, required this.onChanged, this.pending});

  final LoadState<List<AccountConsent>> state;
  final VoidCallback onRetry;
  final void Function(AccountConsent consent, bool granted) onChanged;

  /// Код согласия, которое сейчас сохраняется.
  final String? pending;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return _SectionCard(
      title: s.consentsSection,
      note: s.consentsRevokeNote,
      state: state,
      onRetry: onRetry,
      empty: s.consentsEmpty,
      builder: (items) => [
        for (final (i, c) in items.indexed)
          _ConsentRow(
            key: ValueKey('consent-${c.code}'),
            consent: c,
            last: i == items.length - 1,
            onChanged: c.required || pending != null ? null : (value) => onChanged(c, value),
          ),
      ],
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({super.key, required this.consent, required this.last, this.onChanged});

  final AccountConsent consent;
  final bool last;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final title = consent.title(s.locale);
    final sub = [
      if (consent.required) s.consentsRequiredNote,
      if (consent.updatedAt != null) s.consentsUpdatedOn(dateShort(consent.updatedAt)),
    ].join(' · ');
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.row),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.row),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (consent.required) ...[Icon(Icons.lock_outline, size: 18, color: colors.muted, semanticLabel: s.consentsRequiredNote), const SizedBox(width: AppSpacing.xs)],
            Switch(value: consent.granted, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Карточка «Журнал доступа к моим данным»: кто и роль, когда и что смотрел, код ответа чипом (до 300 — зелёный,
/// до 500 — янтарный, иначе красный), как в вебе.
class AccessLogCard extends StatelessWidget {
  const AccessLogCard({super.key, required this.state, required this.onRetry});

  final LoadState<List<AccessLogEntry>> state;
  final VoidCallback onRetry;

  static StatusTone toneOf(int status) => status < 300 ? StatusTone.ok : (status < 500 ? StatusTone.warn : StatusTone.danger);

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return _SectionCard(
      title: s.accessLogTitle,
      state: state,
      onRetry: onRetry,
      empty: s.accessLogEmpty,
      builder: (rows) => [
        for (final (i, e) in rows.indexed)
          ListRow(
            title: [e.actor, if (e.role.isNotEmpty) s.roleTitle(e.role)].join(' · '),
            subtitle: '${dateTimeShort(e.at)} · ${e.what}',
            trailing: StatusChip('${e.status}', tone: toneOf(e.status)),
            last: i == rows.length - 1,
          ),
      ],
    );
  }
}

/// Карточка «Мои данные»: копия данных открывается страницей веб-кабинета (решение Q17), удаление — через лист
/// подтверждения; пока запрос в полёте ([deleting]), кнопка удаления заблокирована.
class MyDataCard extends StatelessWidget {
  const MyDataCard({super.key, required this.onExport, required this.onDelete, this.deleting = false});

  final VoidCallback onExport;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.myDataTitle),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(onPressed: onExport, icon: const Icon(Icons.open_in_new, size: 18), label: Text(s.exportCopy, textAlign: TextAlign.center)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            style: AppButtons.danger(context),
            onPressed: deleting ? null : onDelete,
            child: Text(s.requestDeletion, textAlign: TextAlign.center),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(s.deletionNote, style: theme.textTheme.labelSmall?.copyWith(color: colors.textFaint, height: 1.5)),
        ],
      ),
    );
  }
}

/// Лист «Удалить учётную запись?» (веб — диалог): true — пользователь подтвердил запрос.
Future<bool> confirmDeletion(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      final s = S.at(sheet);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(s.deletionConfirmTitle),
            const SizedBox(height: AppSpacing.md),
            Text(s.deletionConfirmText, style: Theme.of(sheet).textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              key: const ValueKey('confirm-deletion'),
              style: AppButtons.danger(sheet),
              onPressed: () => Navigator.of(sheet).pop(true),
              child: Text(s.requestDeletion, textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: () => Navigator.of(sheet).pop(false), child: Text(s.cancel)),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// Карточка с kicker'ом и подписью над списком: скелетон, ошибка (компактное состояние вместо карточки), пустой
/// текст или строки.
class _SectionCard<T> extends StatelessWidget {
  const _SectionCard({required this.title, required this.state, required this.onRetry, required this.empty, required this.builder, this.note});

  final String title;
  final String? note;
  final LoadState<List<T>> state;
  final VoidCallback onRetry;
  final String empty;
  final List<Widget> Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = this.state;
    if (state is Failed<List<T>>) {
      return ErrorState(error: state.error, onRetry: onRetry, compact: true);
    }
    final items = switch (state) { Loaded<List<T>>(:final data) => data, _ => null };
    return AppCard(
      padding: _listPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(title),
          if (note != null) ...[const SizedBox(height: AppSpacing.xs), Text(note!, style: theme.textTheme.labelSmall)],
          if (items == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(children: [Skeleton(), SizedBox(height: AppSpacing.sm), Skeleton(), SizedBox(height: AppSpacing.sm), Skeleton()]),
            )
          else if (items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text(empty, style: theme.textTheme.bodySmall))
          else
            ...builder(items),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../api/almaty_time.dart';
import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../api_error.dart';
import '../format.dart';
import '../picker_sheet.dart';

/// Лист действия принимающей больницы (веб — диалог `IncomingReferralsView.vue`): заголовок, строка «реф ·
/// отправитель», поля и кнопки «Подтвердить приём» / «Отказать» / «Перенести» / «Выписать» и «Отмена».
enum IncomingSheetMode {
  /// Дата (по умолчанию сегодня) и необязательный комментарий.
  confirm(RouteCodes.actionConfirm, textField: 'comment'),

  /// Обязательная причина отказа.
  reject(RouteCodes.actionReject, textField: 'reason'),

  /// Новая дата (по умолчанию — текущая) и обязательная причина переноса.
  reschedule(RouteCodes.actionReschedule, textField: 'reason'),

  /// Обязательный эпикриз для направившего врача.
  discharge(RouteCodes.actionDischarge, textField: 'summary');

  const IncomingSheetMode(this.action, {required this.textField});

  /// Код действия в `item.allowed`.
  final String action;

  /// Имя текстового поля в теле запроса — по нему приходит ошибка 422.
  final String textField;

  bool get needsDate => this == confirm || this == reschedule;

  bool get textRequired => this != confirm;

  /// Лист для кода действия; null — действие без листа (admit, no_show) или незнакомое.
  static IncomingSheetMode? of(String action) => values.where((m) => m.action == action).firstOrNull;

  String title(S s) => switch (this) {
        confirm => s.incomingConfirmTitle,
        reject => s.incomingRejectTitle,
        reschedule => s.incomingRescheduleTitle,
        discharge => s.incomingDischargeTitle,
      };

  String textLabel(S s) => switch (this) {
        confirm => s.incomingComment,
        reject => s.incomingRejectReason,
        reschedule => s.incomingRescheduleReason,
        discharge => s.incomingDischargeSummary,
      };

  String submitLabel(S s) => switch (this) {
        confirm => s.incomingConfirmAction,
        reject => s.incomingRejectAction,
        reschedule => s.incomingRescheduleAction,
        discharge => s.incomingDischargeAction,
      };

  /// Тост после успеха.
  String doneText(S s) => switch (this) {
        confirm => s.incomingConfirmedDone,
        reject => s.incomingRejectedDone,
        reschedule => s.incomingRescheduledDone,
        discharge => s.incomingDischargedDone,
      };
}

/// Отправка из листа: [plannedAt] — `yyyy-MM-dd` (для листов без даты не используется), [text] — без пробелов по
/// краям. Возвращает null при успехе или ошибку запроса; 409 и 404 экран сначала перечитывает (список изменился).
typedef IncomingSubmit = Future<Object?> Function(String plannedAt, String text);

/// Чем закончился лист: успех или ошибка, после которой лист закрылся сам (409, 404 — список уже перечитан, текст
/// сервера показывает экран). Закрытый без отправки лист возвращает null.
@immutable
class IncomingSheetResult {
  const IncomingSheetResult._(this.error);

  static const done = IncomingSheetResult._(null);

  factory IncomingSheetResult.failed(Object error) => IncomingSheetResult._(error);

  final Object? error;

  bool get succeeded => error == null;
}

/// Подзаголовок листов: «реф · короткое имя отправителя».
String incomingSheetSubtitle(IncomingReferral item) => '${item.patientRef} · ${shortOrgName(item.fromMoName)}';

/// Открывает лист действия [mode] для [item]. Запрос делает [onSubmit] (новый ключ идемпотентности на каждое
/// нажатие — у экрана); лист держит кнопки выключенными, пока запрос в полёте, и не закрывается свайпом в это время.
/// Лист — на корневом навигаторе: он накрывает плавающую пилюлю вкладок, а не уходит под неё.
Future<IncomingSheetResult?> showIncomingActionSheet(
  BuildContext context, {
  required IncomingSheetMode mode,
  required IncomingReferral item,
  required IncomingSubmit onSubmit,
}) =>
    showModalBottomSheet<IncomingSheetResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => IncomingActionSheet(mode: mode, item: item, onSubmit: onSubmit),
    );

/// Содержимое листа действия: дата в окне «сегодня … +30 дней» по Алматы (календарь не даёт выйти за окно), текст,
/// кнопка, выключенная до корректного ввода (дата в окне, обязательный текст не пуст). Ошибка 422 — под своим полем,
/// остальные ошибки (сеть, 5xx, 403, 429) — строкой над кнопками: снекбар экрана под листом не виден. 409 и 404
/// закрывают лист с ошибкой — экран уже перечитал список и покажет текст сервера.
class IncomingActionSheet extends StatefulWidget {
  const IncomingActionSheet({super.key, required this.mode, required this.item, required this.onSubmit});

  final IncomingSheetMode mode;
  final IncomingReferral item;
  final IncomingSubmit onSubmit;

  @override
  State<IncomingActionSheet> createState() => _IncomingActionSheetState();
}

class _IncomingActionSheetState extends State<IncomingActionSheet> {
  final _text = TextEditingController();
  late String _plannedAt;
  bool _busy = false;
  String? _dateError;
  String? _textError;
  String? _general;

  IncomingSheetMode get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    final current = widget.item.plannedAt;
    _plannedAt = _mode == IncomingSheetMode.reschedule && current != null ? current : almatyTodayString();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => (!_mode.needsDate || isPlannedDateInWindow(_plannedAt)) && (!_mode.textRequired || _text.text.trim().isNotEmpty);

  Future<void> _pickDate() async {
    final window = plannedDateWindow();
    final current = parseApiDate(_plannedAt);
    final inWindow = current != null && !current.isBefore(window.start) && !current.isAfter(window.end);
    final picked = await showDatePicker(
      context: context,
      firstDate: window.start,
      lastDate: window.end,
      initialDate: inWindow ? current : window.start,
      helpText: S.at(context).incomingPlannedAt,
    );
    if (picked != null && mounted) {
      setState(() {
        _plannedAt = formatApiDate(picked);
        _dateError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy || !_valid) {
      return;
    }
    setState(() {
      _busy = true;
      _dateError = null;
      _textError = null;
      _general = null;
    });
    final error = await widget.onSubmit(_plannedAt, _text.text.trim());
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop(IncomingSheetResult.done);
      return;
    }
    final kind = apiErrorKind(error);
    if (kind == ApiErrorKind.conflict || kind == ApiErrorKind.notFound) {
      Navigator.of(context).pop(IncomingSheetResult.failed(error));
      return;
    }
    final dateError = _mode.needsDate ? apiFieldError(error, 'plannedAt') : null;
    final textError = apiFieldError(error, _mode.textField);
    final general = dateError == null && textError == null ? apiErrorText(S.at(context), error) : null;
    setState(() {
      _busy = false;
      _dateError = dateError;
      _textError = textError;
      _general = general;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(_mode.title(s), subtitle: incomingSheetSubtitle(widget.item)),
              const SizedBox(height: AppSpacing.lg),
              if (_mode.needsDate) ...[_dateField(s, theme), const SizedBox(height: AppSpacing.lg)],
              TextField(
                key: const ValueKey('incoming-sheet-text'),
                controller: _text,
                enabled: !_busy,
                minLines: _mode == IncomingSheetMode.discharge ? 4 : 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _textError = null),
                decoration: InputDecoration(
                  labelText: _mode.textLabel(s),
                  hintText: _mode == IncomingSheetMode.discharge ? s.incomingDischargePlaceholder : null,
                  hintMaxLines: 3,
                  alignLabelWithHint: true,
                  errorText: _textError,
                  errorMaxLines: 4,
                ),
              ),
              if (_general != null) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(_general!, style: theme.textTheme.bodyMedium?.copyWith(color: AppTones.of(context).danger.fg)),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                key: const ValueKey('incoming-sheet-submit'),
                onPressed: _valid && !_busy ? _submit : null,
                child: _ButtonLabel(text: _mode.submitLabel(s), busy: _busy),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(s.cancel)),
            ],
          ),
        ),
      ),
    );
  }

  /// Поле даты: `дд.мм.гггг`, календарь по нажатию, подсказка окна дат и ошибка 422 `plannedAt` под ним.
  Widget _dateField(S s, ThemeData theme) => Semantics(
        button: true,
        child: InkWell(
          key: const ValueKey('incoming-sheet-date'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: _busy ? null : _pickDate,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: s.incomingPlannedAt,
              helperText: s.incomingPlannedHint,
              helperMaxLines: 2,
              errorText: _dateError,
              errorMaxLines: 4,
              suffixIcon: const Icon(Icons.event_outlined),
              enabled: !_busy,
            ),
            child: Text(routeDate(_plannedAt), style: theme.textTheme.bodyLarge?.merge(AppType.numeric)),
          ),
        ),
      );
}

/// Подпись кнопки отправки; пока запрос в полёте — с индикатором слева.
class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.text, required this.busy});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Text(text);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: AppSizes.marker + 4, child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.of(context).muted)),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Подтверждение необратимой отметки перед «Госпитализирован» и «Не пришёл» (Q-13): заголовок-вопрос, «реф ·
/// отправитель», что произойдёт, кнопка с подписью действия ([danger] — красная, для неявки) и «Отмена». true —
/// подтверждено; закрытие свайпом — false.
Future<bool> askIncomingMark(
  BuildContext context, {
  required IncomingReferral item,
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final s = S.at(context);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title, subtitle: incomingSheetSubtitle(item)),
          const SizedBox(height: AppSpacing.md),
          Text(body, style: Theme.of(sheet).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xl),
          if (danger)
            OutlinedButton(
              key: const ValueKey('incoming-ask-confirm'),
              style: AppButtons.danger(sheet),
              onPressed: () => Navigator.of(sheet).pop(true),
              child: Text(action),
            )
          else
            FilledButton(key: const ValueKey('incoming-ask-confirm'), onPressed: () => Navigator.of(sheet).pop(true), child: Text(action)),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: () => Navigator.of(sheet).pop(false), child: Text(s.cancel)),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}

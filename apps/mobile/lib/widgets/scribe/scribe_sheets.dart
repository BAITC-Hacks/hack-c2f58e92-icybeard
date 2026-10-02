import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../picker_sheet.dart';

// Нижние листы экрана скрайба: вставка текста приёма, правка одной фразы, подтверждение отмены записи. На вебе это
// поле под кнопками, правка на месте и отмена без вопроса; на телефоне — листы (решение §6.3 отчёта врача): поле
// ввода с клавиатурой помещается целиком, а отмена, которая удаляет аудио и текст, спрашивает подтверждение.

/// Лист «Вставить текст»: поле «или напечатайте текст приёма», «Вставить пример» и «Использовать текст». Возвращает
/// текст без крайних пробелов; null — лист закрыт.
Future<String?> showScribePasteSheet(BuildContext context) {
  final s = S.at(context);
  return _showTextSheet(
    context,
    title: s.aiScribePasteText,
    label: s.aiScribeOrType,
    initial: '',
    primary: s.aiScribeUseText,
    extra: (s.aiScribePasteSample, s.aiScribeSampleTranscript),
  );
}

/// Лист правки фразы стенограммы [text] с меткой [stamp]: «Сохранить» (пустой текст не сохраняется) и «Отмена».
/// Возвращает новый текст; null — лист закрыт без сохранения.
Future<String?> showScribePhraseSheet(BuildContext context, {required String stamp, required String text}) {
  final s = S.at(context);
  return _showTextSheet(context, title: s.aiScribeEditHint, subtitle: stamp, initial: text, primary: s.aiScribeSave, secondary: s.cancel);
}

/// Подтверждение «Отменить запись приёма?» с тем же предупреждением, что и под карточкой записи: аудио и текст
/// удалятся, для новой записи понадобится новое согласие. true — врач подтвердил.
Future<bool> confirmScribeDiscard(BuildContext context) async {
  final s = S.at(context);
  final colors = AppPalette.of(context);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(s.aiScribeDiscardQuestion, subtitle: s.aiScribeDiscardHint),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: colors.dangerStrong, foregroundColor: colors.onAccent),
            onPressed: () => Navigator.of(sheet).pop(true),
            icon: const Icon(Icons.delete_outline, size: 20),
            label: Text(s.aiScribeDiscard),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: () => Navigator.of(sheet).pop(false), child: Text(s.aiScribeDiscardKeep)),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}

Future<String?> _showTextSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? label,
  required String initial,
  required String primary,
  String? secondary,
  (String label, String text)? extra,
}) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TextSheet(title: title, subtitle: subtitle, label: label, initial: initial, primary: primary, secondary: secondary, extra: extra),
    );

/// Лист с многострочным полем: заголовок, необязательная подпись поля, основная кнопка (неактивна при пустом поле),
/// необязательная вторая кнопка «Отмена» и необязательная кнопка, подставляющая готовый текст («Вставить пример»).
class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.title, this.subtitle, this.label, required this.initial, required this.primary, this.secondary, this.extra});

  final String title;
  final String? subtitle;
  final String? label;
  final String initial;
  final String primary;
  final String? secondary;
  final (String label, String text)? extra;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final extra = widget.extra;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(widget.title, subtitle: widget.subtitle),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: widget.initial.isNotEmpty,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: widget.label, alignLabelWithHint: true),
            ),
            if (extra != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => _controller.text = extra.$2, child: Text(extra.$1)),
              ),
            const SizedBox(height: AppSpacing.md),
            // текст читается в момент нажатия, а не при последней перестройке листа
            FilledButton(onPressed: text.isEmpty ? null : () => Navigator.of(context).pop(_controller.text.trim()), child: Text(widget.primary)),
            if (widget.secondary != null) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.secondary!)),
            ],
          ],
        ),
      ),
    );
  }
}

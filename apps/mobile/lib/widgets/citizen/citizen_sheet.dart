import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../picker_sheet.dart';

/// Нижний лист перед действием гражданина: подтверждение необратимого на вид шага (решение Q5: «Больше не нужно»,
/// «Отказаться от госпитализации», отказ от перевода, отзыв согласия) или просьба о больнице (Q20) — заголовок,
/// пояснение и необязательный комментарий врачу (Q7). Возвращает комментарий (обрезанный, пустой — без комментария),
/// null — «Отмена» или лист закрыт мимо. Контроллер поля живёт и освобождается внутри листа (после закрытия лист ещё
/// проигрывает анимацию).
Future<String?> showCitizenSheet(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  bool danger = false,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CitizenSheet(title: title, body: body, confirmLabel: confirmLabel, danger: danger),
    );

class _CitizenSheet extends StatefulWidget {
  const _CitizenSheet({required this.title, required this.body, required this.confirmLabel, required this.danger});

  final String title;
  final String? body;
  final String confirmLabel;
  final bool danger;

  @override
  State<_CitizenSheet> createState() => _CitizenSheetState();
}

class _CitizenSheetState extends State<_CitizenSheet> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(widget.title, subtitle: widget.body),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _comment,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: s.myCommentLabel, alignLabelWithHint: true),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            style: widget.danger ? AppButtons.danger(context) : null,
            onPressed: () => Navigator.of(context).pop(_comment.text.trim()),
            child: Text(widget.confirmLabel, textAlign: TextAlign.center),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        ],
      ),
    );
  }
}

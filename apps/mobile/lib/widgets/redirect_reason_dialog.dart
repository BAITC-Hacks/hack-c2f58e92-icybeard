import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Диалог с одним текстовым полем: причина перенаправления или ответа «оставить» (врач), комментарий к запросу
/// (гражданин, optional = true — пустой текст тоже ответ). Возвращает текст, null — отмена. Контроллер поля живёт
/// внутри диалога и освобождается в его dispose — после закрытия диалог ещё проигрывает анимацию, и внешнее
/// dispose сразу после showDialog роняло приложение («_dependents.isEmpty»).
class RedirectReasonDialog extends StatefulWidget {
  const RedirectReasonDialog({super.key, required this.organization, this.label, this.confirmLabel, this.optional = false});

  /// Заголовок: организация («Направить сюда») либо готовая фраза («Попросить врача рассмотреть: …»).
  final String organization;
  final String? label;
  final String? confirmLabel;
  final bool optional;

  static Future<String?> show(BuildContext context, {required String organization, String? label, String? confirmLabel, bool optional = false}) =>
      showDialog<String>(
        context: context,
        builder: (_) => RedirectReasonDialog(organization: organization, label: label, confirmLabel: confirmLabel, optional: optional),
      );

  @override
  State<RedirectReasonDialog> createState() => _RedirectReasonDialogState();
}

class _RedirectReasonDialogState extends State<RedirectReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return AlertDialog(
      title: Text(widget.organization, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: TextField(
        controller: _controller,
        autofocus: !widget.optional,
        maxLines: 3,
        decoration: InputDecoration(labelText: widget.label ?? s.redirectReasonLabel),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: Text(widget.confirmLabel ?? s.redirectHere)),
      ],
    );
  }
}
